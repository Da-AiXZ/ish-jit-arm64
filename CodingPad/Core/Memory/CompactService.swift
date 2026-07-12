// CompactService.swift
// CodingPad
//
// Two-phase context compression service inspired by Claude Code's /compact.
// Primary path: LLM-driven compression via an LLMProvider.
// Fallback path: Rule-based extraction (keyword matching + truncation).
//
// When an LLMProvider is available, the service sends a structured prompt
// to the model asking it to produce a summary organized into 9 categories.
// If the LLM call fails for any reason, the service degrades gracefully
// to the original rule-based implementation.

import Foundation

// MARK: - CompactService

/// Compresses conversation history while preserving critical context.
///
/// Two compression strategies are available:
/// 1. **LLM-driven** (`compact`): Sends older messages to an LLM with a
///    structured prompt that produces a rich, context-aware summary.
/// 2. **Rule-based** (`compactRuleBased`): Fast, local keyword matching
///    that produces a reasonable summary without any API calls.
///
/// The `compact` method accepts an optional `LLMProvider`. When `nil`,
/// or when the LLM call fails, the service automatically falls back
/// to the rule-based path.
struct CompactService {

    // MARK: - Result Type

    /// The result of compacting a conversation.
    struct CompactResult: Sendable {
        /// The structured summary text.
        let summary: String

        /// Messages that were preserved verbatim (e.g., last N messages).
        let preservedMessages: [Message]

        /// Approximate number of tokens saved by compaction.
        let tokensSaved: Int

        /// Whether the LLM-driven path was used (`false` for rule-based).
        let usedLLM: Bool
    }

    // MARK: - Configuration

    /// Number of recent messages to preserve verbatim (not summarized).
    private let preserveRecentCount: Int

    /// Maximum summary length in characters (for rule-based path).
    private let maxSummaryLength: Int

    /// Maximum tokens to request from the LLM for the summary.
    private let llmMaxTokens: Int

    /// Timeout in seconds for the LLM call.
    private let llmTimeoutSeconds: Int

    init(
        preserveRecentCount: Int = 4,
        maxSummaryLength: Int = 6_000,
        llmMaxTokens: Int = 4_096,
        llmTimeoutSeconds: Int = 120
    ) {
        self.preserveRecentCount = preserveRecentCount
        self.maxSummaryLength = maxSummaryLength
        self.llmMaxTokens = llmMaxTokens
        self.llmTimeoutSeconds = llmTimeoutSeconds
    }

    // MARK: - Public API (LLM-driven)

    /// Compacts a conversation using LLM-driven summarization with rule-based fallback.
    ///
    /// - Parameters:
    ///   - messages: The full message history to compact.
    ///   - systemPrompt: The current system prompt (for context awareness).
    ///   - llmProvider: An optional LLM provider. Pass `nil` to use rule-based only.
    /// - Returns: A `CompactResult` with summary, preserved messages, and savings.
    func compact(
        messages: [Message],
        systemPrompt: String,
        llmProvider: (any LLMProvider)? = nil
    ) async -> CompactResult {
        guard messages.count > preserveRecentCount else {
            return CompactResult(
                summary: "",
                preservedMessages: messages,
                tokensSaved: 0,
                usedLLM: false
            )
        }

        // Split: older messages to summarize, recent ones to preserve
        let splitIndex = messages.count - preserveRecentCount
        let toSummarize = Array(messages[..<splitIndex])
        let toPreserve = Array(messages[splitIndex...])

        // Try LLM-driven compression first
        if let provider = llmProvider {
            do {
                let result = try await compactWithLLM(
                    messagesToSummarize: toSummarize,
                    preservedMessages: toPreserve,
                    systemPrompt: systemPrompt,
                    provider: provider
                )
                return result
            } catch {
                // LLM failed — fall through to rule-based
                #if DEBUG
                print("[CompactService] LLM compression failed, falling back to rule-based: \(error.localizedDescription)")
                #endif
            }
        }

        // Fallback: rule-based compression
        return compactRuleBased(
            messagesToSummarize: toSummarize,
            preservedMessages: toPreserve
        )
    }

    /// Compacts only if the message history exceeds a token threshold.
    ///
    /// - Parameters:
    ///   - messages: The full message history.
    ///   - systemPrompt: The current system prompt.
    ///   - tokenThreshold: Minimum estimated tokens before compaction triggers.
    ///   - llmProvider: An optional LLM provider.
    /// - Returns: A `CompactResult` if compaction was performed, or `nil`.
    func compactIfNeeded(
        messages: [Message],
        systemPrompt: String,
        tokenThreshold: Int,
        llmProvider: (any LLMProvider)? = nil
    ) async -> CompactResult? {
        let currentTokens = estimateTokens(for: messages)
        guard currentTokens > tokenThreshold else {
            return nil
        }
        return await compact(
            messages: messages,
            systemPrompt: systemPrompt,
            llmProvider: llmProvider
        )
    }

    // MARK: - Public API (Rule-based)

    /// Compacts a conversation using rule-based extraction only.
    ///
    /// This is the zero-cost fallback that uses keyword matching and
    /// pattern extraction. No API calls are made.
    func compactRuleBased(messages: [Message], systemPrompt: String) -> CompactResult {
        guard messages.count > preserveRecentCount else {
            return CompactResult(
                summary: "",
                preservedMessages: messages,
                tokensSaved: 0,
                usedLLM: false
            )
        }

        let splitIndex = messages.count - preserveRecentCount
        let toSummarize = Array(messages[..<splitIndex])
        let toPreserve = Array(messages[splitIndex...])

        return compactRuleBased(
            messagesToSummarize: toSummarize,
            preservedMessages: toPreserve
        )
    }

    // MARK: - LLM Compression

    /// Performs LLM-driven compression on the given messages.
    private func compactWithLLM(
        messagesToSummarize: [Message],
        preservedMessages: [Message],
        systemPrompt: String,
        provider: any LLMProvider
    ) async throws -> CompactResult {
        let conversationText = formatMessagesForPrompt(messagesToSummarize)
        let compactPrompt = buildCompactPrompt(conversationText: conversationText)

        // Build a single-message request with the compact prompt
        let promptMessage = Message(role: .user, text: compactPrompt)

        let fullResponse = try await provider.collectFullResponse(
            messages: [promptMessage],
            systemPrompt: "You are a conversation summarizer. Follow the instructions precisely.",
            maxTokens: llmMaxTokens,
            timeoutSeconds: llmTimeoutSeconds
        )

        // Extract <summary> content from the response
        let summary = extractSummaryTag(from: fullResponse)

        // Calculate savings
        let originalTokens = estimateTokens(for: messagesToSummarize)
        let summaryTokens = summary.count / 4
        let saved = max(0, originalTokens - summaryTokens)

        return CompactResult(
            summary: summary,
            preservedMessages: preservedMessages,
            tokensSaved: saved,
            usedLLM: true
        )
    }

    /// Builds the structured compact prompt sent to the LLM.
    private func buildCompactPrompt(conversationText: String) -> String {
        """
        Your task is to create a summary of the conversation so far. \
        This summary will be used as context for continuing the conversation.

        <instructions>
        1. First, within <analysis> tags, analyze the conversation to identify:
           - The main task or question being addressed
           - Key technical decisions made
           - Important files, code, or data references
           - Errors encountered and their resolutions
           - Current state of the work
           - Any user preferences or instructions expressed
           - Pending tasks or next steps

        2. Then, within <summary> tags, write a concise but thorough summary \
        organized into these sections:

        ## Primary Requests and Goals
        What the user asked for and the overall objectives.

        ## Technical Concepts and Decisions
        Architecture choices, patterns, libraries, or approaches decided on.

        ## Files and Code References
        Key files read, written, or discussed. Include paths.

        ## Error Fix History
        Bugs found and how they were resolved.

        ## Problem Solving Status
        What's been completed, what's in progress, what remains.

        ## User Instructions and Preferences
        Explicit requests about how to work (language, style, approach).

        ## Todo Items
        Any tracked tasks and their status.

        ## Current Work State
        Where things stand right now — what was the last action taken.

        ## Next Steps
        What should happen next.

        IMPORTANT: Be specific. Include file paths, function names, error messages, \
        and concrete details. Vague summaries are useless.
        </instructions>

        <conversation>
        \(conversationText)
        </conversation>
        """
    }

    /// Extracts the content within `<summary>...</summary>` tags.
    ///
    /// If no tags are found, returns the full response as-is (the LLM
    /// may have produced useful content without following the tag format).
    private func extractSummaryTag(from response: String) -> String {
        let pattern = #"<summary>([\s\S]*?)</summary>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                  in: response,
                  range: NSRange(response.startIndex..., in: response)
              ),
              let captureRange = Range(match.range(at: 1), in: response)
        else {
            // No <summary> tag found — return trimmed full response
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(response[captureRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rule-Based Compression (Fallback)

    /// Internal rule-based compression on pre-split message arrays.
    private func compactRuleBased(
        messagesToSummarize: [Message],
        preservedMessages: [Message]
    ) -> CompactResult {
        let analysis = analyzeMessages(messagesToSummarize)
        let summary = buildRuleBasedSummary(from: analysis)

        let originalTokens = estimateTokens(for: messagesToSummarize)
        let summaryTokens = summary.count / 4
        let saved = max(0, originalTokens - summaryTokens)

        return CompactResult(
            summary: summary,
            preservedMessages: preservedMessages,
            tokensSaved: saved,
            usedLLM: false
        )
    }

    // MARK: - Phase 1: Rule-Based Analysis

    /// The 9 categories of information to preserve during compaction.
    private struct ConversationAnalysis {
        var primaryRequests: [String] = []
        var technicalDecisions: [String] = []
        var fileReferences: [String] = []
        var errorFixes: [String] = []
        var problemStatus: [String] = []
        var userInstructions: [String] = []
        var todoItems: [String] = []
        var currentWorkState: [String] = []
        var nextSteps: [String] = []
    }

    /// Analyzes messages to extract information for each of the 9 categories.
    private func analyzeMessages(_ messages: [Message]) -> ConversationAnalysis {
        var analysis = ConversationAnalysis()

        for message in messages {
            let text = extractText(from: message)
            guard !text.isEmpty else { continue }

            switch message.role {
            case .user:
                analyzeUserMessage(text, into: &analysis)
            case .assistant:
                analyzeAssistantMessage(text, into: &analysis)
            case .system:
                break
            }
        }

        return analysis
    }

    /// Extracts relevant info from a user message.
    private func analyzeUserMessage(_ text: String, into analysis: inout ConversationAnalysis) {
        let textLower = text.lowercased()

        // 1. Primary requests — first sentences of user messages
        let firstLine = text.components(separatedBy: "\n").first ?? text
        if firstLine.count > 10 {
            analysis.primaryRequests.append(String(firstLine.prefix(200)))
        }

        // 6. User instructions and preferences
        let instructionPatterns = [
            "please", "always", "never", "don't", "make sure",
            "I want", "I prefer", "I need", "remember",
        ]
        if instructionPatterns.contains(where: { textLower.contains($0) }) {
            analysis.userInstructions.append(String(text.prefix(300)))
        }

        // 3. File references
        extractFileReferences(from: text, into: &analysis)

        // 7. Todo items
        if textLower.contains("todo") || textLower.contains("to-do") ||
           textLower.contains("task") || textLower.contains("need to") {
            analysis.todoItems.append(String(text.prefix(200)))
        }
    }

    /// Extracts relevant info from an assistant message.
    private func analyzeAssistantMessage(_ text: String, into analysis: inout ConversationAnalysis) {
        let textLower = text.lowercased()

        // 2. Technical decisions
        let decisionKeywords = [
            "I'll use", "I chose", "the approach", "decision",
            "architecture", "design", "pattern", "strategy",
        ]
        if decisionKeywords.contains(where: { textLower.contains($0) }) {
            analysis.technicalDecisions.append(String(text.prefix(300)))
        }

        // 4. Error fixes
        let errorKeywords = [
            "error", "bug", "fix", "fixed", "issue", "problem",
            "resolved", "workaround",
        ]
        if errorKeywords.contains(where: { textLower.contains($0) }) {
            analysis.errorFixes.append(String(text.prefix(300)))
        }

        // 5. Problem status
        let statusKeywords = [
            "completed", "done", "finished", "working",
            "in progress", "remaining", "still need",
        ]
        if statusKeywords.contains(where: { textLower.contains($0) }) {
            analysis.problemStatus.append(String(text.prefix(200)))
        }

        // 3. File references
        extractFileReferences(from: text, into: &analysis)

        // 8. Current work state
        if textLower.contains("currently") || textLower.contains("so far") ||
           textLower.contains("at this point") {
            analysis.currentWorkState.append(String(text.prefix(200)))
        }

        // 9. Next steps
        if textLower.contains("next") || textLower.contains("then we") ||
           textLower.contains("after that") || textLower.contains("remaining") {
            analysis.nextSteps.append(String(text.prefix(200)))
        }
    }

    /// Extracts file path references from text.
    private func extractFileReferences(from text: String, into analysis: inout ConversationAnalysis) {
        let pattern = #"\b([A-Za-z0-9_]+(?:/[A-Za-z0-9_.]+)+\.[A-Za-z]{1,10})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            if let captureRange = Range(match.range, in: text) {
                let path = String(text[captureRange])
                if !analysis.fileReferences.contains(path) {
                    analysis.fileReferences.append(path)
                }
            }
        }
    }

    // MARK: - Phase 2: Rule-Based Summary

    /// Builds a structured summary from the rule-based analysis.
    private func buildRuleBasedSummary(from analysis: ConversationAnalysis) -> String {
        var sections: [String] = ["<summary>"]

        appendSection(
            &sections, title: "Primary Requests and Goals",
            items: analysis.primaryRequests, maxItems: 5
        )
        appendSection(
            &sections, title: "Technical Concepts and Decisions",
            items: analysis.technicalDecisions, maxItems: 5
        )

        if !analysis.fileReferences.isEmpty {
            sections.append("\n## Files Referenced")
            let uniqueFiles = Array(Set(analysis.fileReferences)).sorted().prefix(20)
            for file in uniqueFiles {
                sections.append("- \(file)")
            }
        }

        appendSection(
            &sections, title: "Error Fix History",
            items: analysis.errorFixes, maxItems: 5
        )
        appendSection(
            &sections, title: "Problem Solving Status",
            items: analysis.problemStatus, maxItems: 3
        )
        appendSection(
            &sections, title: "User Instructions and Preferences",
            items: analysis.userInstructions, maxItems: 5
        )
        appendSection(
            &sections, title: "Todo Items",
            items: analysis.todoItems, maxItems: 10
        )
        appendSection(
            &sections, title: "Current Work State",
            items: analysis.currentWorkState, maxItems: 3
        )
        appendSection(
            &sections, title: "Next Steps",
            items: analysis.nextSteps, maxItems: 5
        )

        sections.append("\n</summary>")

        let full = sections.joined(separator: "\n")

        if full.count > maxSummaryLength {
            return String(full.prefix(maxSummaryLength)) + "\n\n[... summary truncated ...]\n</summary>"
        }

        return full
    }

    /// Appends a titled section with bullet items.
    private func appendSection(
        _ sections: inout [String],
        title: String,
        items: [String],
        maxItems: Int
    ) {
        guard !items.isEmpty else { return }

        sections.append("\n## \(title)")
        for item in items.prefix(maxItems) {
            let cleaned = item
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append("- \(cleaned)")
        }
    }

    // MARK: - Utilities

    /// Extracts plain text from a message.
    private func extractText(from message: Message) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    /// Rough token estimate for a list of messages.
    private func estimateTokens(for messages: [Message]) -> Int {
        let totalChars = messages.reduce(0) { sum, message in
            sum + extractText(from: message).count
        }
        return max(1, totalChars / 4)
    }
}
