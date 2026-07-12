// SSEParser.swift
// CodingPad
//
// Parses Server-Sent Events (SSE) from raw byte streams into structured
// `StreamEvent` values. Designed specifically for Anthropic's streaming
// format but follows the standard SSE specification for frame delimiting.

import Foundation

// MARK: - SSE Event Types

/// A raw SSE frame parsed from the byte stream, before semantic interpretation.
struct SSEFrame: Sendable {
    /// The `event:` field value (e.g., "message_start", "content_block_delta").
    let event: String?
    /// The `data:` field value (may contain multiple data lines concatenated).
    let data: String
    /// The `id:` field value, if present.
    let id: String?
    /// The `retry:` field value (reconnection delay in ms), if present.
    let retry: Int?
}

// MARK: - SSE Parser

/// A stateful parser that incrementally consumes raw bytes and emits
/// complete SSE frames.
///
/// SSE frames are delimited by double newlines (`\n\n`). Each frame may
/// contain multiple lines prefixed with `event:`, `data:`, `id:`, or
/// `retry:`. Lines starting with `:` are comments and are ignored.
///
/// This parser is a **value type** — it is safe to use from a single
/// concurrency context. For concurrent streaming, each task should own
/// its own instance or use proper synchronization.
struct SSEParser {

    /// Internal buffer accumulating unprocessed bytes.
    private(set) var buffer: Data = Data()

    /// Creates a new, empty parser.
    init() {}

    // MARK: - Feeding Data

    /// Appends raw bytes to the parser buffer.
    /// - Parameter data: The bytes received from the network.
    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    // MARK: - Frame Extraction

    /// Attempts to extract all complete frames currently in the buffer.
    ///
    /// Each call removes consumed bytes from the internal buffer.
    /// Remaining partial data stays buffered until more bytes arrive.
    /// - Returns: An array of fully parsed `SSEFrame` values (may be empty).
    mutating func parseFrames() -> [SSEFrame] {
        var frames: [SSEFrame] = []

        while let frameRange = findFrameDelimiter() {
            // Extract the raw bytes for this frame (excluding the delimiter).
            let frameData = buffer.subdata(in: 0..<frameRange.startIndex)
            // Remove the frame bytes + delimiter from the buffer.
            buffer.removeSubrange(0..<frameRange.endIndex)

            guard let frame = parseFrame(frameData) else {
                // Empty frames (blank lines) are valid — just skip them.
                continue
            }
            frames.append(frame)
        }

        return frames
    }

    // MARK: - Frame Parsing

    /// Finds the byte range of the next frame delimiter (`\n\n` or `\r\n\r\n`).
    private func findFrameDelimiter() -> Range<Data.Index>? {
        // Try `\r\n\r\n` (Windows-style line endings) first.
        if let range = findPattern([0x0D, 0x0A, 0x0D, 0x0A], in: buffer) {
            return range
        }
        // Then try `\n\n` (Unix-style).
        if let range = findPattern([0x0A, 0x0A], in: buffer) {
            return range
        }
        return nil
    }

    /// Searches for a byte pattern within `Data`, returning the range of the
    /// first match.
    private func findPattern(_ pattern: [UInt8], in data: Data) -> Range<Data.Index>? {
        guard data.count >= pattern.count else { return nil }

        let searchEnd = data.count - pattern.count
        for offset in 0...searchEnd {
            var matched = true
            for (i, byte) in pattern.enumerated() {
                if data[data.startIndex.advanced(by: offset + i)] != byte {
                    matched = false
                    break
                }
            }
            if matched {
                let start = data.startIndex.advanced(by: offset)
                let end = start.advanced(by: pattern.count)
                return start..<end
            }
        }
        return nil
    }

    /// Parses raw frame bytes into an `SSEFrame`, interpreting field prefixes.
    private func parseFrame(_ data: Data) -> SSEFrame? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var event: String?
        var dataLines: [String] = []
        var id: String?
        var retry: Int?

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            // Skip empty lines (shouldn't occur inside a frame, but be safe).
            if line.isEmpty { continue }

            // SSE comment — ignore.
            if line.hasPrefix(":") { continue }

            // Split into field name and value.
            if let colonIndex = line.firstIndex(of: ":") {
                let fieldName = String(line[..<colonIndex])
                // Per spec, a leading space after the colon is stripped.
                var value = String(line[line.index(after: colonIndex)...])
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }

                switch fieldName {
                case "event":
                    event = value
                case "data":
                    dataLines.append(value)
                case "id":
                    id = value
                case "retry":
                    retry = Int(value)
                default:
                    // Unknown field — ignore per SSE spec.
                    break
                }
            } else {
                // Line without a colon: the entire line is the field name
                // with an empty value.
                switch line {
                case "event": event = ""
                case "data": dataLines.append("")
                case "id": id = ""
                default: break
                }
            }
        }

        // A frame with no data lines is a keep-alive or empty event — skip it.
        if dataLines.isEmpty { return nil }

        return SSEFrame(
            event: event,
            data: dataLines.joined(separator: "\n"),
            id: id,
            retry: retry
        )
    }

    // MARK: - Reset

    /// Clears any buffered partial data. Call this when reusing the parser
    /// for a new connection.
    mutating func reset() {
        buffer.removeAll()
    }
}

// MARK: - Anthropic Event Decoding

/// Decodes Anthropic-specific SSE frames into `StreamEvent` values.
///
/// Anthropic emits events like:
/// - `message_start` — contains the message ID and initial usage.
/// - `content_block_start` — a new content block (text or tool_use) begins.
/// - `content_block_delta` — incremental data for a content block.
/// - `content_block_stop` — a content block is complete.
/// - `message_delta` — message-level updates (e.g., stop_reason).
/// - `message_stop` — the entire message is done.
/// - `ping` — keep-alive.
/// - `error` — an error occurred.
enum AnthropicEventDecoder {

    /// Converts a single SSE frame into zero or more `StreamEvent` values.
    ///
    /// Most frames produce exactly one event, but `error` frames may produce
    /// an `.error` stream event. Returns `nil` for ignorable events (ping).
    static func decode(_ frame: SSEFrame) -> StreamEvent? {
        let eventType = frame.event ?? ""

        switch eventType {
        case "message_start":
            return decodeMessageStart(frame.data)

        case "content_block_start":
            return decodeContentBlockStart(frame.data)

        case "content_block_delta":
            return decodeContentBlockDelta(frame.data)

        case "content_block_stop":
            return decodeContentBlockStop(frame.data)

        case "message_delta":
            return decodeMessageDelta(frame.data)

        case "message_stop":
            return decodeMessageStop(frame.data)

        case "ping":
            return nil

        case "error":
            return decodeError(frame.data)

        default:
            return nil
        }
    }

    // MARK: - Individual Event Parsers

    private static func decodeMessageStart(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }

        // Message structure: { "message": { "id": "...", "usage": {...} } }
        let message = (json["message"] as? [String: Any]) ?? [:]
        guard let messageId = message["id"] as? String else { return nil }

        return .messageStart(messageId: messageId)
    }

    private static func decodeContentBlockStart(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }

        guard let index = json["index"] as? Int else { return nil }
        let block = (json["content_block"] as? [String: Any]) ?? [:]
        let type = (block["type"] as? String) ?? "text"

        switch type {
        case "tool_use":
            guard let id = block["id"] as? String,
                  let name = block["name"] as? String else {
                return nil
            }
            return .toolUseStart(id: id, name: name)

        default:
            return .contentBlockStart(index: index, type: type)
        }
    }

    private static func decodeContentBlockDelta(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }

        let delta = (json["delta"] as? [String: Any]) ?? [:]
        let deltaType = (delta["type"] as? String) ?? ""

        switch deltaType {
        case "text_delta":
            if let text = delta["text"] as? String {
                return .textDelta(text: text)
            }
            return nil

        case "input_json_delta":
            if let partialJson = delta["partial_json"] as? String {
                return .toolUseInputDelta(json: partialJson)
            }
            return nil

        default:
            return nil
        }
    }

    private static func decodeContentBlockStop(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }
        guard let index = json["index"] as? Int else { return nil }
        return .contentBlockStop(index: index)
    }

    private static func decodeMessageDelta(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }

        let delta = (json["delta"] as? [String: Any]) ?? [:]
        let stopReason = delta["stop_reason"] as? String

        return .messageDelta(stopReason: stopReason)
    }

    private static func decodeMessageStop(_ data: String) -> StreamEvent? {
        guard let json = parseJSON(data) else { return nil }

        // Anthropic's message_stop may include final usage in some
        // implementations. We extract usage if present; otherwise emit
        // a messageDone with zero usage (the usage from message_delta
        // or message_start will have been captured already).
        let usageDict = (json["usage"] as? [String: Any]) ?? json["message"] as? [String: Any]
        let usage = extractUsage(usageDict ?? [:])

        return .messageDone(usage: usage)
    }

    private static func decodeError(_ data: String) -> StreamEvent? {
        if let json = parseJSON(data),
           let error = json["error"] as? [String: Any] {
            let type = (error["type"] as? String) ?? "unknown"
            let message = (error["message"] as? String) ?? "Unknown API error"
            return .error(LLMError.apiError(type: type, message: message))
        }
        return .error(LLMError.invalidStreamData(data))
    }

    // MARK: - JSON Utilities

    /// Lightweight JSON parsing using `JSONSerialization`. Returns the top-level
    /// object as a dictionary.
    private static func parseJSON(_ string: String) -> [String: Any]? {
        guard let jsonData = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    /// Extracts `TokenUsage` from a dictionary containing token counts.
    private static func extractUsage(_ dict: [String: Any]) -> TokenUsage {
        TokenUsage(
            inputTokens: dict["input_tokens"] as? Int ?? 0,
            outputTokens: dict["output_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: dict["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadInputTokens: dict["cache_read_input_tokens"] as? Int ?? 0
        )
    }
}

// MARK: - Convenience: Full Pipeline

extension SSEParser {

    /// Convenience method: appends data and returns any decoded `StreamEvent`
    /// values from the newly completed frames.
    ///
    /// This combines `append(_:)`, `parseFrames()`, and
    /// `AnthropicEventDecoder.decode(_:)` in a single call, which is the
    /// typical usage during streaming.
    /// - Parameter data: Raw bytes received from the network.
    /// - Returns: Decoded `StreamEvent` values from complete frames.
    mutating func process(_ data: Data) -> [StreamEvent] {
        append(data)
        let frames = parseFrames()
        return frames.compactMap { AnthropicEventDecoder.decode($0) }
    }
}
