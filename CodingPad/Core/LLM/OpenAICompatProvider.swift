// OpenAICompatProvider.swift
// CodingPad
//
// LLM Provider for OpenAI-compatible APIs (DeepSeek, GPT, Gemini, local models).
//
// DeepSeek API specifics:
//   - Endpoint: https://api.deepseek.com/chat/completions
//   - Auth: Bearer token in Authorization header
//   - Format: OpenAI chat completion format
//   - Models: deepseek-chat, deepseek-reasoner
//   - Tool calling: Supported, but in streaming mode tool calls
//     arrive complete in the LAST chunk only (not incrementally)
//
// References:
//   https://api-docs.deepseek.com/api/create-chat-completion
//   https://api-docs.deepseek.com/guides/function_calling

import Foundation

// MARK: - OpenAICompatProvider

/// LLM provider for any OpenAI-compatible API (DeepSeek, OpenAI, etc).
final class OpenAICompatProvider: LLMProvider, @unchecked Sendable {

    let name: String
    let modelId: String
    let contextWindowSize: Int

    private let baseURL: String
    private let apiKeyProvider: @Sendable () -> String?
    private let session: URLSession

    /// Known provider presets.
    enum Preset {
        case deepseek
        case openai
        case custom(baseURL: String, name: String)

        var baseURL: String {
            switch self {
            case .deepseek: return "https://api.deepseek.com"
            case .openai: return "https://api.openai.com"
            case .custom(let url, _): return url
            }
        }

        var displayName: String {
            switch self {
            case .deepseek: return "DeepSeek"
            case .openai: return "OpenAI"
            case .custom(_, let name): return name
            }
        }
    }

    init(
        preset: Preset = .deepseek,
        modelId: String = "deepseek-chat",
        contextWindowSize: Int = 64_000,
        apiKeyProvider: @escaping @Sendable () -> String?
    ) {
        self.name = preset.displayName
        self.modelId = modelId
        self.contextWindowSize = contextWindowSize
        self.baseURL = preset.baseURL
        self.apiKeyProvider = apiKeyProvider

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performRequest(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request

    private func performRequest(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        retryCount: Int = 0
    ) async throws {
        guard let apiKey = apiKeyProvider() else {
            throw LLMError.authenticationFailed("No API key configured for \(name)")
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let body = buildRequestBody(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            maxTokens: maxTokens
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Stream response
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Not an HTTP response")
        }

        // Handle errors with retry
        if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
            if retryCount < 3 {
                let delay = Double(1 << retryCount) // 1, 2, 4 seconds
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try await performRequest(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens,
                    continuation: continuation,
                    retryCount: retryCount + 1
                )
                return
            }
            throw LLMError.rateLimited(retryAfter: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to read error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse SSE stream
        var messageId = ""
        var inputTokens = 0
        var outputTokens = 0

        continuation.yield(.messageStart(messageId: ""))

        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            guard line.hasPrefix("data: ") else { continue }

            let data = String(line.dropFirst(6))
            if data == "[DONE]" { break }

            guard let jsonData = data.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Extract message ID
            if let id = chunk["id"] as? String, messageId.isEmpty {
                messageId = id
            }

            // Extract usage (often in the last chunk)
            if let usage = chunk["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? 0
                outputTokens = usage["completion_tokens"] as? Int ?? 0
            }

            // Process choices
            guard let choices = chunk["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            let delta = choice["delta"] as? [String: Any] ?? [:]
            let finishReason = choice["finish_reason"] as? String

            // Text content
            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(text: content))
            }

            // Tool calls (DeepSeek gives complete tool_call in last chunk)
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for toolCall in toolCalls {
                    let tcFunction = toolCall["function"] as? [String: Any] ?? [:]
                    let tcId = toolCall["id"] as? String ?? UUID().uuidString
                    let tcName = tcFunction["name"] as? String ?? ""
                    let tcArgs = tcFunction["arguments"] as? String ?? "{}"

                    if !tcName.isEmpty {
                        continuation.yield(.toolUseStart(id: tcId, name: tcName))
                    }
                    if !tcArgs.isEmpty {
                        continuation.yield(.toolUseInputDelta(json: tcArgs))
                    }
                    // Since DeepSeek gives complete tool calls, immediately stop the block
                    if !tcName.isEmpty {
                        continuation.yield(.contentBlockStop(index: 0))
                    }
                }
            }

            // Finish reason
            if let reason = finishReason {
                let stopReason: String?
                switch reason {
                case "stop": stopReason = "end_turn"
                case "tool_calls": stopReason = "tool_use"
                case "length": stopReason = "max_tokens"
                default: stopReason = reason
                }
                continuation.yield(.messageDelta(stopReason: stopReason))
            }
        }

        // Final usage
        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        continuation.yield(.messageDone(usage: usage))
        continuation.finish()
    }

    // MARK: - Request Body

    private func buildRequestBody(
        messages: [Message],
        systemPrompt: String,
        tools: [ToolDefinition],
        maxTokens: Int
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelId,
            "stream": true,
            "max_tokens": maxTokens,
            "stream_options": ["include_usage": true]
        ]

        // Build messages array (OpenAI format)
        var apiMessages: [[String: Any]] = []

        // System message
        if !systemPrompt.isEmpty {
            apiMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        // Conversation messages
        for message in messages {
            let apiMsg = convertMessage(message)
            apiMessages.append(apiMsg)
        }

        body["messages"] = apiMessages

        // Tools (OpenAI function calling format)
        if !tools.isEmpty {
            let apiTools: [[String: Any]] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": convertSchema(tool.inputSchema)
                    ] as [String: Any]
                ]
            }
            body["tools"] = apiTools
        }

        return body
    }

    /// Convert our Message to OpenAI API format.
    private func convertMessage(_ message: Message) -> [String: Any] {
        var result: [String: Any] = ["role": message.role.rawValue]

        var textParts: [String] = []
        var toolCalls: [[String: Any]] = []
        var toolResultId: String?
        var toolResultContent: String?

        for block in message.content {
            switch block {
            case .text(let text):
                textParts.append(text)

            case .toolUse(let toolUse):
                let argsJson: String
                if let data = try? JSONSerialization.data(
                    withJSONObject: convertJSONValueDict(toolUse.input)),
                   let str = String(data: data, encoding: .utf8) {
                    argsJson = str
                } else {
                    argsJson = "{}"
                }
                toolCalls.append([
                    "id": toolUse.id,
                    "type": "function",
                    "function": [
                        "name": toolUse.name,
                        "arguments": argsJson
                    ]
                ])

            case .toolResult(let toolResult):
                toolResultId = toolResult.toolUseId
                toolResultContent = toolResult.content
            }
        }

        // Tool result message (role: "tool")
        if let resultId = toolResultId {
            result["role"] = "tool"
            result["tool_call_id"] = resultId
            result["content"] = toolResultContent ?? ""
            return result
        }

        // Assistant message with tool calls
        if !toolCalls.isEmpty {
            result["role"] = "assistant"
            result["tool_calls"] = toolCalls
            if !textParts.isEmpty {
                result["content"] = textParts.joined(separator: "\n")
            }
            return result
        }

        // Regular text message
        result["content"] = textParts.joined(separator: "\n")
        return result
    }

    /// Convert ToolInputSchema to OpenAI JSON Schema format.
    private func convertSchema(_ schema: ToolInputSchema) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (name, prop) in schema.properties {
            var propDict: [String: Any] = [
                "type": prop.type,
                "description": prop.description
            ]
            if let enumVals = prop.enumValues {
                propDict["enum"] = enumVals
            }
            properties[name] = propDict
        }

        return [
            "type": "object",
            "properties": properties,
            "required": schema.required
        ]
    }

    /// Convert [String: JSONValue] to [String: Any] for JSON serialization.
    private func convertJSONValueDict(_ dict: [String: JSONValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = convertJSONValue(value)
        }
        return result
    }

    private func convertJSONValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { convertJSONValue($0) }
        case .object(let obj): return convertJSONValueDict(obj)
        }
    }
}
