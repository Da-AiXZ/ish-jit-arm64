// LLMProviderExtensions.swift
// CodingPad
//
// Shared utilities for collecting complete LLM responses from streaming APIs.
// Used by CompactService and MemoryExtractor for non-interactive LLM calls.

import Foundation

// MARK: - LLM Response Collection

/// Errors specific to LLM response collection.
enum LLMCollectionError: Error, Sendable, LocalizedError {
    /// The LLM call exceeded the allowed time limit.
    case timeout(seconds: Int)

    /// The LLM returned an empty response.
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "LLM call timed out after \(seconds) seconds."
        case .emptyResponse:
            return "LLM returned an empty response."
        }
    }
}

// MARK: - LLMProvider Extension

extension LLMProvider {

    /// Collects the full text response from a streaming LLM call.
    ///
    /// Iterates over the `AsyncThrowingStream` returned by `sendMessage`,
    /// accumulating all `.textDelta` events into a single string.
    ///
    /// - Parameters:
    ///   - messages: The conversation to send.
    ///   - systemPrompt: The system-level instruction.
    ///   - maxTokens: Maximum tokens in the response.
    ///   - timeoutSeconds: Maximum allowed duration (default: 120 seconds).
    /// - Returns: The complete text response.
    /// - Throws: `LLMCollectionError.timeout` if the call exceeds the time limit,
    ///   `LLMCollectionError.emptyResponse` if no text was returned,
    ///   or any error from the underlying stream.
    func collectFullResponse(
        messages: [Message],
        systemPrompt: String,
        maxTokens: Int,
        timeoutSeconds: Int = 120
    ) async throws -> String {
        let result = try await withThrowingTaskGroup(of: String.self) { group in
            // Worker: collect streaming text
            group.addTask {
                let stream = self.sendMessage(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    tools: [],
                    maxTokens: maxTokens
                )

                var fullText = ""
                for try await event in stream {
                    if case .textDelta(let text) = event {
                        fullText += text
                    }
                }
                return fullText
            }

            // Timeout: cancel if too slow
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                throw LLMCollectionError.timeout(seconds: timeoutSeconds)
            }

            // Return whichever finishes first
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        guard !result.isEmpty else {
            throw LLMCollectionError.emptyResponse
        }

        return result
    }
}

// MARK: - Message Formatting

/// Formats conversation messages into a text block for LLM prompts.
///
/// Each message is rendered as:
/// ```
/// [role]: content
/// ```
///
/// Only text content blocks are included; tool use/result blocks are skipped.
func formatMessagesForPrompt(_ messages: [Message]) -> String {
    messages.compactMap { message in
        let text = message.content.compactMap { block -> String? in
            if case .text(let t) = block { return t }
            return nil
        }.joined(separator: "\n")

        guard !text.isEmpty else { return nil }

        let roleLabel: String
        switch message.role {
        case .user:      roleLabel = "Human"
        case .assistant: roleLabel = "Assistant"
        case .system:    roleLabel = "System"
        }

        return "[\(roleLabel)]: \(text)"
    }.joined(separator: "\n\n")
}
