// LLMProvider.swift
// CodingPad
//
// Protocol defining the interface for LLM providers.
// Designed for streaming responses via AsyncThrowingStream.

import Foundation

// MARK: - LLM Provider Protocol

/// A provider that can send messages to an LLM and receive streaming responses.
///
/// Conforming types must be `Sendable` to support safe usage across
/// concurrency boundaries. The protocol uses `AsyncThrowingStream` to
/// deliver incremental streaming events as they arrive from the API.
protocol LLMProvider: Sendable {

    /// Human-readable name of the provider (e.g., "Anthropic").
    var name: String { get }

    /// The model identifier sent to the API (e.g., "claude-opus-4-8").
    var modelId: String { get }

    /// Maximum input context window size in tokens.
    var contextWindowSize: Int { get }

    /// Sends a conversation to the LLM and returns a stream of events.
    ///
    /// - Parameters:
    ///   - messages: The conversation history to send.
    ///   - systemPrompt: The system-level instruction for the model.
    ///   - tools: Tool definitions the model may invoke.
    ///   - maxTokens: Maximum number of tokens in the response.
    /// - Returns: An async stream of `StreamEvent` values as they arrive.
    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - LLM Errors

/// Errors that can occur during LLM API interactions.
enum LLMError: Error, Sendable {
    /// The API key is missing or could not be retrieved.
    case missingAPIKey

    /// The server returned an HTTP error status code.
    case httpError(statusCode: Int, message: String)

    /// Rate limited by the API (HTTP 429). Contains the retry-after delay if available.
    case rateLimited(retryAfter: TimeInterval?)

    /// A transient server error (HTTP 500, 503) that may be retried.
    case serverError(statusCode: Int, message: String)

    /// The request could not be encoded as valid JSON.
    case requestEncodingFailed(String)

    /// The streaming response contained malformed data.
    case invalidStreamData(String)

    /// The API returned a structured error in the response body.
    case apiError(type: String, message: String)

    /// All retry attempts have been exhausted.
    case retriesExhausted(lastError: Error)

    /// A network-level or URLSession error.
    case networkError(Error)
}

extension LLMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing. Please configure your API key in settings."
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .rateLimited(let retryAfter):
            if let delay = retryAfter {
                return "Rate limited. Retry after \(Int(delay)) seconds."
            }
            return "Rate limited. Please try again later."
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .requestEncodingFailed(let detail):
            return "Failed to encode request: \(detail)"
        case .invalidStreamData(let detail):
            return "Invalid stream data: \(detail)"
        case .apiError(let type, let message):
            return "API error (\(type)): \(message)"
        case .retriesExhausted(let lastError):
            return "All retries exhausted. Last error: \(lastError.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
