// AnthropicProvider.swift
// CodingPad
//
// Direct URLSession-based implementation of `LLMProvider` for the
// Anthropic Messages API. Supports streaming, prompt caching, tool use,
// and retry with exponential backoff.

import Foundation

// MARK: - Anthropic Provider

/// A streaming LLM provider backed by the Anthropic Messages API.
///
/// This provider makes raw HTTP requests via `URLSession` — no SDK dependency.
/// All responses are streamed using Server-Sent Events (SSE), parsed by
/// `SSEParser` into `StreamEvent` values.
///
/// **API Key Injection**: The key is supplied via a closure so it can be
/// fetched lazily from Keychain or another secure store at call time.
///
/// **Prompt Caching**: The system prompt is tagged with `cache_control` so
/// Anthropic caches it across requests, reducing latency and cost for
/// repeated system-level instructions.
///
/// **Retry Policy**:
/// - HTTP 429 (rate limited): exponential backoff, up to 3 retries.
/// - HTTP 500 / 503 (transient): same backoff, up to 3 retries.
/// - All other errors: no retry.
final class AnthropicProvider: LLMProvider {

    // MARK: - Constants

    private enum API {
        static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
        static let anthropicVersion = "2023-06-01"
        static let contentType = "application/json"
    }

    private enum RetryPolicy {
        static let maxRetries = 3
        /// Base delay for exponential backoff (in seconds).
        static let baseDelay: TimeInterval = 1.0
        /// Multiplier applied per retry attempt.
        static let backoffMultiplier: Double = 2.0
        /// Maximum delay cap (in seconds).
        static let maxDelay: TimeInterval = 30.0
    }

    // MARK: - Properties

    let name: String = "Anthropic"
    let modelId: String
    let contextWindowSize: Int

    /// Closure that returns the current API key. Allows lazy/secure key
    /// retrieval (e.g., from Keychain).
    private let apiKeyProvider: @Sendable () -> String?

    /// The URL session used for all network calls.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates a new Anthropic provider.
    ///
    /// - Parameters:
    ///   - modelId: The model to use (e.g., "claude-opus-4-8").
    ///   - contextWindowSize: Maximum context window in tokens.
    ///   - apiKeyProvider: A closure returning the API key (or `nil` if unavailable).
    ///   - session: A configured `URLSession`. Defaults to a streaming-optimized
    ///     shared session.
    init(
        modelId: String,
        contextWindowSize: Int,
        apiKeyProvider: @escaping @Sendable () -> String?,
        session: URLSession = AnthropicProvider.makeStreamingSession()
    ) {
        self.modelId = modelId
        self.contextWindowSize = contextWindowSize
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    // MARK: - LLMProvider Conformance

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await self.executeWithRetry(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        maxTokens: maxTokens
                    )

                    for try await event in stream {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Execution (with Retry)

    /// Builds and sends the streaming request, retrying on transient errors.
    private func executeWithRetry(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        var lastError: Error?

        for attempt in 0..<RetryPolicy.maxRetries {
            do {
                return try await performRequest(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens
                )
            } catch let error as LLMError {
                lastError = error

                // Determine if this error is retryable.
                guard let delay = retryDelay(for: error, attempt: attempt) else {
                    throw error
                }

                // Wait before retrying. Cancellation propagates here.
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // All retries exhausted.
        throw LLMError.retriesExhausted(lastError: lastError ?? LLMError.networkError(
            URLError(.unknown)
        ))
    }

    /// Returns the delay before the next retry, or `nil` if the error is not
    /// retryable.
    private func retryDelay(for error: LLMError, attempt: Int) -> TimeInterval? {
        switch error {
        case .rateLimited(let retryAfter):
            // If the server told us how long to wait, respect it.
            return max(retryAfter ?? 0, exponentialDelay(attempt: attempt))

        case .serverError:
            return exponentialDelay(attempt: attempt)

        default:
            return nil
        }
    }

    /// Computes an exponential backoff delay.
    private func exponentialDelay(attempt: Int) -> TimeInterval {
        let raw = RetryPolicy.baseDelay * pow(RetryPolicy.backoffMultiplier, Double(attempt))
        return min(raw, RetryPolicy.maxDelay)
    }

    // MARK: - HTTP Request

    /// Performs a single streaming request to the Anthropic Messages API.
    private func performRequest(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // 1. Obtain API key.
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        // 2. Build the request body.
        let body = try buildRequestBody(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens
        )

        // 3. Build the URLRequest.
        let request = try buildURLRequest(body: body, apiKey: apiKey)

        // 4. Send the request and get the streaming response.
        return try await streamResponse(for: request)
    }

    // MARK: - Request Body Construction

    /// Builds the JSON body for the Messages API request.
    private func buildRequestBody(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) throws -> Data {
        let body = AnthropicRequestBody(
            model: modelId,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: messages.map(AnthropicMessage.init),
            tools: tools.isEmpty ? nil : tools.map(AnthropicTool.init),
            stream: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            return try encoder.encode(body)
        } catch {
            throw LLMError.requestEncodingFailed(error.localizedDescription)
        }
    }

    // MARK: - URL Request Construction

    private func buildURLRequest(body: Data, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: API.baseURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(API.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(API.contentType, forHTTPHeaderField: "content-type")
        return request
    }

    // MARK: - Streaming Response

    /// Initiates the HTTP request and returns an `AsyncThrowingStream` that
    /// yields `StreamEvent` values parsed from the SSE response.
    private func streamResponse(
        for request: URLRequest
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let (bytes, response) = try await session.bytes(for: request)

        // Validate HTTP status before streaming.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidStreamData("Non-HTTP response")
        }

        try validateStatusCode(httpResponse)

        // Return the parsed event stream.
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()

                do {
                    for try await line in bytes.lines {
                        // URLSession's `.lines` splits on newlines, so we
                        // reconstruct the SSE framing. A blank line signals
                        // the end of a frame.
                        if line.isEmpty {
                            // Parse any accumulated complete frames.
                            let frames = parser.parseFrames()
                            for frame in frames {
                                if let event = AnthropicEventDecoder.decode(frame) {
                                    continuation.yield(event)
                                }
                            }
                        } else {
                            // Re-add the line (with trailing newline) to the
                            // parser buffer.
                            var lineData = Data((line + "\n").utf8)
                            parser.append(lineData)
                        }
                    }

                    // Flush any remaining buffered data.
                    let remaining = parser.parseFrames()
                    for frame in remaining {
                        if let event = AnthropicEventDecoder.decode(frame) {
                            continuation.yield(event)
                        }
                    }

                    continuation.finish()
                } catch {
                    // URLSession cancellation on Task.cancel() — not an error.
                    if error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.yield(.error(LLMError.networkError(error)))
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Status Code Validation

    /// Validates the HTTP status code, throwing the appropriate `LLMError`.
    private func validateStatusCode(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return

        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap(TimeInterval.init)
            throw LLMError.rateLimited(retryAfter: retryAfter)

        case 500, 503:
            let message = extractErrorMessage(from: response) ?? "Service unavailable"
            throw LLMError.serverError(statusCode: response.statusCode, message: message)

        default:
            let message = extractErrorMessage(from: response) ?? "Unexpected status code"
            throw LLMError.httpError(statusCode: response.statusCode, message: message)
        }
    }

    /// Attempts to extract an error message from the response body.
    /// For streaming responses, the body may not be available at this point,
    /// so this returns `nil` and the error details will come via SSE.
    private func extractErrorMessage(from response: HTTPURLResponse) -> String? {
        // In practice, for non-2xx streaming responses, Anthropic sends an
        // error event in the SSE stream. For non-streaming errors (e.g.,
        // auth failures), the status text is the best we have.
        return nil
    }

    // MARK: - Session Factory

    /// Creates a `URLSession` configured for streaming responses.
    private static func makeStreamingSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        // Explicitly enable HTTP/2 for multiplexed streaming.
        config.httpAdditionalHeaders = ["Accept": "text/event-stream"]
        return URLSession(configuration: config)
    }
}

// MARK: - Request Codable Types

/// The top-level JSON body for the Anthropic Messages API.
///
/// Note: `system` is encoded as an array of content blocks (rather than a
/// plain string) to support `cache_control` for prompt caching.
private struct AnthropicRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: [SystemBlock]
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case stream
    }

    /// System prompt is wrapped in a content block array with `cache_control`
    /// to enable prompt caching.
    struct SystemBlock: Encodable {
        let type: String = "text"
        let text: String
        let cacheControl: CacheControl?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case cacheControl = "cache_control"
        }

        struct CacheControl: Encodable {
            let type: String = "ephemeral"
        }

        init(text: String, enableCache: Bool = true) {
            self.text = text
            self.cacheControl = enableCache ? CacheControl() : nil
        }
    }

    init(
        model: String,
        maxTokens: Int,
        system: String,
        messages: [AnthropicMessage],
        tools: [AnthropicTool]?,
        stream: Bool
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = [SystemBlock(text: system, enableCache: !system.isEmpty)]
        self.messages = messages
        self.tools = tools
        self.stream = stream
    }
}

/// A message in the Anthropic API format.
private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContentBlock]

    init(from message: Message) {
        self.role = message.role.rawValue
        self.content = message.content.map(AnthropicContentBlock.init)
    }
}

/// A content block in the Anthropic API format.
private enum AnthropicContentBlock: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: String, isError: Bool)

    init(from block: ContentBlock) {
        switch block {
        case .text(let text):
            self = .text(text)

        case .toolUse(let toolUse):
            self = .toolUse(id: toolUse.id, name: toolUse.name, input: toolUse.input)

        case .toolResult(let result):
            self = .toolResult(
                toolUseId: result.toolUseId,
                content: result.content,
                isError: result.isError
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)

        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)

        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

/// A tool definition in the Anthropic API format.
private struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: ToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    init(from definition: ToolDefinition) {
        self.name = definition.name
        self.description = definition.description
        self.inputSchema = definition.inputSchema
    }
}
