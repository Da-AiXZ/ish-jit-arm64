// MemoryExtractor.swift
// CodingPad
//
// Analyzes conversation content to identify knowledge worth persisting.
// Primary path: LLM-driven extraction via an LLMProvider.
// Fallback path: Rule-based keyword matching and pattern recognition.
//
// The LLM path is designed for periodic use (not every turn) since it
// incurs API costs. The rule-based path runs locally at zero cost and
// can be called after every conversation turn.

import Foundation

// MARK: - Extraction Result

/// A suggested memory entry extracted from conversation content.
struct ExtractionSuggestion: Sendable {
    let name: String        // kebab-case slug
    let description: String // one-line summary
    let type: MemoryType
    let content: String
    let confidence: Double  // 0.0 - 1.0
}

// MARK: - MemoryExtractor

/// Analyzes messages to find knowledge worth persisting as memory entries.
///
/// Two extraction strategies are available:
/// 1. **LLM-driven** (`extractWithLLM`): Sends recent messages to an LLM
///    that identifies and classifies important information. Best used
///    periodically (e.g., every 5-10 turns) to manage API costs.
/// 2. **Rule-based** (`extractRuleBased`): Fast, local pattern matching
///    using keyword detection and regex. Safe to call every turn.
///
/// Both paths return `[ExtractionSuggestion]` with confidence scores.
struct MemoryExtractor {

    // MARK: - Configuration

    /// Maximum tokens to request from the LLM for extraction.
    private let llmMaxTokens: Int

    /// Timeout in seconds for the LLM call.
    private let llmTimeoutSeconds: Int

    /// Minimum confidence threshold for rule-based suggestions.
    private let minConfidence: Double

    /// Maximum number of recent messages to send to the LLM.
    private let maxMessagesForLLM: Int

    init(
        llmMaxTokens: Int = 2_048,
        llmTimeoutSeconds: Int = 60,
        minConfidence: Double = 0.4,
        maxMessagesForLLM: Int = 20
    ) {
        self.llmMaxTokens = llmMaxTokens
        self.llmTimeoutSeconds = llmTimeoutSeconds
        self.minConfidence = minConfidence
        self.maxMessagesForLLM = maxMessagesForLLM
    }

    // MARK: - Public API (LLM-driven)

    /// Extracts memory suggestions using an LLM, with rule-based fallback.
    ///
    /// Designed for periodic invocation (not every turn). The LLM receives
    /// recent messages and a list of already-known memory names to avoid
    /// duplicates.
    ///
    /// - Parameters:
    ///   - messages: Recent conversation messages to analyze.
    ///   - existingMemories: Already-stored memories (used for deduplication).
    ///   - llmProvider: The LLM provider to use for extraction.
    /// - Returns: An array of extraction suggestions, sorted by confidence.
    func extractWithLLM(
        messages: [Message],
        existingMemories: [MemoryEntry],
        llmProvider: any LLMProvider
    ) async -> [ExtractionSuggestion] {
        do {
            let suggestions = try await performLLMExtraction(
                messages: messages,
                existingMemories: existingMemories,
                provider: llmProvider
            )
            return suggestions
        } catch {
            #if DEBUG
            print("[MemoryExtractor] LLM extraction failed, falling back to rule-based: \(error.localizedDescription)")
            #endif
            // Fallback to rule-based extraction
            return extractRuleBased(messages: messages)
        }
    }

    // MARK: - Public API (Rule-based)

    /// Extracts memory suggestions using rule-based pattern matching.
    ///
    /// Zero-cost, local analysis. Safe to call after every conversation turn.
    /// Only user messages are analyzed (assistant messages are skipped).
    ///
    /// - Parameter messages: Messages to analyze.
    /// - Returns: Suggestions sorted by confidence (highest first).
    func extractRuleBased(messages: [Message]) -> [ExtractionSuggestion] {
        var suggestions: [ExtractionSuggestion] = []

        for message in messages where message.role == .user {
            let text = extractText(from: message)
            guard !text.isEmpty else { continue }

            let messageSuggestions = analyzeMessageRuleBased(
                text: text,
                timestamp: message.timestamp
            )
            suggestions.append(contentsOf: messageSuggestions)
        }

        let deduplicated = deduplicateSuggestions(suggestions)

        return deduplicated
            .filter { $0.confidence >= minConfidence }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Analyzes a single text string for extractable knowledge (rule-based).
    func extractFromText(_ text: String) -> [ExtractionSuggestion] {
        analyzeMessageRuleBased(text: text, timestamp: Date())
            .filter { $0.confidence >= minConfidence }
    }

    // MARK: - LLM Extraction

    /// Performs the LLM-driven extraction flow.
    private func performLLMExtraction(
        messages: [Message],
        existingMemories: [MemoryEntry],
        provider: any LLMProvider
    ) async throws -> [ExtractionSuggestion] {
        // Limit messages sent to LLM
        let recentMessages = Array(messages.suffix(maxMessagesForLLM))
        let conversationText = formatMessagesForPrompt(recentMessages)
        let existingNames = existingMemories.map(\.name)
        let prompt = buildExtractionPrompt(
            conversationText: conversationText,
            existingMemoryNames: existingNames
        )

        let promptMessage = Message(role: .user, text: prompt)

        let fullResponse = try await provider.collectFullResponse(
            messages: [promptMessage],
            systemPrompt: "You are a memory extraction assistant. Respond only with valid JSON.",
            maxTokens: llmMaxTokens,
            timeoutSeconds: llmTimeoutSeconds
        )

        // Parse JSON response
        let parsed = parseExtractionResponse(fullResponse)

        // Filter out duplicates with existing memories
        let existingNameSet = Set(existingNames)
        let filtered = parsed.filter { !existingNameSet.contains($0.name) }

        return filtered.sorted { $0.confidence > $1.confidence }
    }

    /// Builds the extraction prompt sent to the LLM.
    private func buildExtractionPrompt(
        conversationText: String,
        existingMemoryNames: [String]
    ) -> String {
        let existingList = existingMemoryNames.isEmpty
            ? "(none)"
            : existingMemoryNames.joined(separator: ", ")

        return """
        Analyze the conversation below and identify important information \
        that should be remembered for future sessions.

        Types of information to extract:
        - "user": Who the user is (role, expertise, preferences)
        - "feedback": Guidance on how you should work (corrections, confirmed approaches)
        - "project": Ongoing work, goals, constraints, decisions
        - "reference": External resources, URLs, tools mentioned

        For each piece of information:
        1. Give it a short kebab-case name (e.g., "prefers-swift-concurrency")
        2. Write a one-line description
        3. Classify the type
        4. Write the full content

        Already known memories (do not duplicate):
        \(existingList)

        Respond as JSON array:
        [
          {
            "name": "example-name",
            "description": "One-line summary",
            "type": "user|feedback|project|reference",
            "content": "Full content with context"
          }
        ]

        If nothing new worth remembering, respond with: []

        <conversation>
        \(conversationText)
        </conversation>
        """
    }

    /// Parses the LLM response into `ExtractionSuggestion` values.
    ///
    /// Handles common response formats:
    /// - A bare JSON array `[...]`
    /// - A JSON array wrapped in markdown code fences
    /// - An empty response or `[]` (returns empty array)
    private func parseExtractionResponse(_ response: String) -> [ExtractionSuggestion] {
        // Strip markdown code fences if present
        let cleaned = response
            .replacingOccurrences(
                of: #"```(?:json)?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find a JSON array in the response
        guard let jsonStart = cleaned.firstIndex(of: "["),
              let jsonEnd = cleaned.lastIndex(of: "]") else {
            return []
        }

        let jsonString = String(cleaned[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let items = try JSONDecoder().decode([LLMExtractionItem].self, from: data)
            return items.compactMap { item -> ExtractionSuggestion? in
                guard let memoryType = MemoryType(rawValue: item.type) else {
                    return nil
                }
                guard !item.name.isEmpty, !item.content.isEmpty else {
                    return nil
                }

                return ExtractionSuggestion(
                    name: item.name,
                    description: item.description,
                    type: memoryType,
                    content: item.content,
                    confidence: 0.8 // LLM-extracted items get high confidence
                )
            }
        } catch {
            #if DEBUG
            print("[MemoryExtractor] Failed to parse LLM JSON response: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Decodable model matching the LLM's expected JSON output.
    private struct LLMExtractionItem: Decodable {
        let name: String
        let description: String
        let type: String
        let content: String
    }

    // MARK: - Rule-Based Analysis

    /// Patterns that indicate user corrections or preferences.
    private static let correctionPatterns: [(pattern: String, type: MemoryType)] = [
        // User corrections
        (#"(?i)\b(actually|correction|no,?\s+I)\b.*\b(prefer|want|use|like|need)\b"#, .feedback),
        (#"(?i)\bdon'?t\b.*\b(instead|rather|use|prefer)\b"#, .feedback),
        (#"(?i)\bstop\b.*\b(doing|using|generating)\b"#, .feedback),

        // Explicit preferences
        (#"(?i)\b(from now on|going forward|always|never)\b"#, .feedback),
        (#"(?i)\b(I prefer|I like|I want|I need)\b.*\b(you to|it to|them to)\b"#, .feedback),
        (#"(?i)\bplease\s+(always|never|remember)\b"#, .feedback),

        // Project conventions
        (#"(?i)\b(we always|we never|our convention|our standard|the project)\b"#, .project),
        (#"(?i)\b(code style|naming convention|file structure|architecture)\b.*\b(is|uses|follows)\b"#, .project),
        (#"(?i)\b(tech stack|framework|library|database)\b.*\b(is|uses|we use)\b"#, .project),

        // User identity
        (#"(?i)\b(I am|I'm|my name is|my role is)\b"#, .user),
        (#"(?i)\b(I work on|I specialize in|my expertise|my background)\b"#, .user),

        // Reference pointers
        (#"(?i)\b(refer to|check out|see|look at|documentation at)\b.*\b(https?://|www\.)\b"#, .reference),
        (#"(?i)\b(the docs|the wiki|the readme|the guide)\b.*\b(is at|lives at|can be found)\b"#, .reference),
    ]

    /// Keywords that boost confidence when found in a message.
    private static let boostKeywords: Set<String> = [
        "remember", "important", "always", "never", "convention",
        "standard", "rule", "preference", "requirement", "must",
    ]

    /// Analyzes a single message text against all patterns (rule-based).
    private func analyzeMessageRuleBased(
        text: String,
        timestamp: Date
    ) -> [ExtractionSuggestion] {
        var suggestions: [ExtractionSuggestion] = []

        // Skip very short messages (unlikely to contain extractable knowledge)
        guard text.count >= 20 else { return [] }

        for (pattern, memoryType) in Self.correctionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            guard !matches.isEmpty else { continue }

            // Calculate confidence
            var confidence = baseConfidence(for: memoryType)

            // Boost for keyword presence
            let textLowered = text.lowercased()
            let boostCount = Self.boostKeywords.filter { textLowered.contains($0) }.count
            confidence += Double(boostCount) * 0.05

            // Boost for explicit phrasing (longer, more specific messages)
            if text.count > 100 { confidence += 0.1 }
            if text.count > 200 { confidence += 0.05 }

            // Cap confidence
            confidence = min(confidence, 1.0)

            // Generate entry fields
            let name = generateName(from: text, type: memoryType)
            let description = generateDescription(from: text)
            let content = extractRelevantContent(from: text)

            suggestions.append(ExtractionSuggestion(
                name: name,
                description: description,
                type: memoryType,
                content: content,
                confidence: confidence
            ))
        }

        return suggestions
    }

    /// Returns the base confidence for a memory type.
    private func baseConfidence(for type: MemoryType) -> Double {
        switch type {
        case .feedback:  return 0.6
        case .user:      return 0.7
        case .project:   return 0.5
        case .reference: return 0.5
        }
    }

    // MARK: - Content Generation (Rule-based)

    /// Generates a kebab-case name from the message text.
    private func generateName(from text: String, type: MemoryType) -> String {
        let prefix = type.rawValue

        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "i", "you", "we", "they", "it", "to", "of", "in", "for",
            "on", "with", "that", "this", "and", "or", "but", "not",
            "from", "by", "at", "do", "don't", "please", "always", "never",
        ]

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
            .prefix(4)

        let slug = words.joined(separator: "-")
        let truncated = String(slug.prefix(40))

        if truncated.isEmpty {
            return "\(prefix)-\(UUID().uuidString.prefix(8))"
        }

        return "\(prefix)-\(truncated)"
    }

    /// Generates a one-line description from the message text.
    private func generateDescription(from text: String) -> String {
        let firstSentence = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text

        let truncated = String(firstSentence.prefix(120))
        return truncated.count < firstSentence.count ? truncated + "..." : truncated
    }

    /// Extracts the most relevant content from the text.
    private func extractRelevantContent(from text: String) -> String {
        let maxLength = 2_000
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "\n\n[... truncated ...]"
    }

    // MARK: - Utilities

    /// Extracts plain text from a message's content blocks.
    private func extractText(from message: Message) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    /// Removes duplicate suggestions based on name similarity.
    private func deduplicateSuggestions(
        _ suggestions: [ExtractionSuggestion]
    ) -> [ExtractionSuggestion] {
        var seen: Set<String> = []
        return suggestions.filter { suggestion in
            let key = suggestion.name
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}
