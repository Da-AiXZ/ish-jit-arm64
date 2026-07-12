// StreamHandler.swift
// CodingPad
//
// Converts LLM StreamEvent flow into AgentEvent flow.
// Accumulates tool_use input_json_delta fragments until content_block_stop,
// then triggers tool execution. Handles parallel tool calls.

import Foundation
import os

// MARK: - Agent Events

/// Events emitted by the agent loop, consumed by the UI layer.
enum AgentEvent: Sendable {
    /// A text delta from the assistant's response.
    case textDelta(String)
    /// A tool call has started.
    case toolCallStart(name: String, id: String)
    /// An incremental JSON fragment of tool input.
    case toolCallInput(json: String)
    /// A tool call has completed with a result.
    case toolCallComplete(name: String, result: ToolResult)
    /// A tool requires user permission before execution.
    case permissionRequired(tool: String, input: ToolInput, id: String)
    /// A complete turn has finished.
    case turnComplete(usage: TokenUsage)
    /// An error occurred.
    case error(Error)
    /// The agent has stopped with a reason.
    case done(stopReason: String)
}

// MARK: - Pending Tool Call

/// An in-progress tool call being assembled from stream deltas.
struct PendingToolCall: Sendable {
    let id: String
    let name: String
    var accumulatedJSON: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.accumulatedJSON = ""
    }

    /// Create a new PendingToolCall with additional JSON appended (immutable pattern).
    func appendingJSON(_ json: String) -> PendingToolCall {
        var copy = PendingToolCall(id: id, name: name)
        copy.accumulatedJSON = accumulatedJSON + json
        return copy
    }
}

// MARK: - Stream Handler

/// Processes raw `StreamEvent`s from the LLM provider and emits `AgentEvent`s.
///
/// Responsibilities:
/// - Converts text deltas to `AgentEvent.textDelta`
/// - Accumulates tool_use input JSON fragments
/// - On `contentBlockStop`, assembles the complete tool call
/// - Collects all completed tool calls for a turn
/// - Reports usage and stop reason
final class StreamHandler: Sendable {
    private let logger = Logger(subsystem: "com.codingpad", category: "StreamHandler")

    init() {}

    /// Processes a stream of LLM events and transforms them into agent events.
    ///
    /// This is a pure transformation: it does NOT execute tools.
    /// Tool execution is handled by the caller after receiving
    /// `completedToolCalls` from the returned `StreamResult`.
    ///
    /// - Parameter stream: The raw stream of LLM events.
    /// - Returns: An async stream of `AgentEvent` values.
    func process(
        stream: AsyncThrowingStream<StreamEvent, Error>
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [logger] in
                // Mutable state for accumulating tool calls
                var pendingToolCalls: [Int: PendingToolCall] = [:]
                var completedToolCalls: [PendingToolCall] = []
                var currentMessageId: String?
                var finalUsage: TokenUsage?
                var stopReason: String?

                do {
                    for try await event in stream {
                        if Task.isCancelled { break }

                        switch event {
                        case .messageStart(let messageId):
                            currentMessageId = messageId
                            logger.debug("Message started: \(messageId)")

                        case .contentBlockStart(let index, let type):
                            logger.debug("Content block start: index=\(index) type=\(type)")

                        case .textDelta(let text):
                            continuation.yield(.textDelta(text))

                        case .toolUseStart(let id, let name):
                            logger.debug("Tool use start: \(name) id=\(id)")
                            // Find the correct index for this tool call
                            let index = pendingToolCalls.count
                            pendingToolCalls[index] = PendingToolCall(id: id, name: name)
                            continuation.yield(.toolCallStart(name: name, id: id))

                        case .toolUseInputDelta(let json):
                            // Append to the most recently started pending tool call
                            if let lastIndex = pendingToolCalls.keys.max(),
                               let pending = pendingToolCalls[lastIndex] {
                                pendingToolCalls[lastIndex] = pending.appendingJSON(json)
                                continuation.yield(.toolCallInput(json: json))
                            }

                        case .contentBlockStop(let index):
                            // If this block was a tool use, mark it as complete
                            if let pending = pendingToolCalls[index] {
                                completedToolCalls.append(pending)
                                pendingToolCalls.removeValue(forKey: index)
                                logger.debug("Tool call assembled: \(pending.name) json=\(pending.accumulatedJSON.prefix(100))")
                            }
                            // Also check if any pending tool call matches by last-in order
                            // when index doesn't directly match (some APIs use sequential indices)
                            if pendingToolCalls[index] == nil, !pendingToolCalls.isEmpty {
                                let sortedKeys = pendingToolCalls.keys.sorted()
                                if let firstKey = sortedKeys.first {
                                    let pending = pendingToolCalls[firstKey]!
                                    completedToolCalls.append(pending)
                                    pendingToolCalls.removeValue(forKey: firstKey)
                                    logger.debug("Tool call assembled (re-indexed): \(pending.name)")
                                }
                            }

                        case .messageDelta(let reason):
                            stopReason = reason

                        case .messageDone(let usage):
                            finalUsage = usage
                            if let usage = finalUsage {
                                continuation.yield(.turnComplete(usage: usage))
                            }

                        case .error(let error):
                            continuation.yield(.error(error))
                        }
                    }

                    // Flush any remaining pending tool calls
                    for key in pendingToolCalls.keys.sorted() {
                        if let pending = pendingToolCalls[key] {
                            completedToolCalls.append(pending)
                        }
                    }

                    // Yield stop reason
                    let reason = stopReason ?? "end_turn"
                    if !completedToolCalls.isEmpty {
                        // Don't yield .done yet; the caller will process tool calls
                        // and potentially continue the loop.
                        // Signal completed tool calls via dedicated events.
                    } else {
                        continuation.yield(.done(stopReason: reason))
                    }

                    continuation.finish()

                } catch {
                    logger.error("Stream processing error: \(error.localizedDescription)")
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Parse accumulated JSON into a ToolInput.
    ///
    /// - Parameter json: The accumulated JSON string.
    /// - Returns: A ToolInput if parsing succeeds, nil otherwise.
    static func parseToolInput(json: String) -> ToolInput? {
        guard !json.isEmpty else {
            return ToolInput(parameters: [:])
        }

        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return nil
        }

        return ToolInput(parameters: parsed)
    }
}

// MARK: - Stream Processing Result

/// The result of processing one complete LLM response stream.
/// Collected after the stream finishes for use by the agent loop.
struct StreamProcessingResult: Sendable {
    /// Tool calls that were assembled and need execution.
    let completedToolCalls: [PendingToolCall]
    /// Whether the model wants to stop (no tool calls).
    let shouldStop: Bool
    /// The stop reason from the model.
    let stopReason: String
    /// Token usage for this turn.
    let usage: TokenUsage?
}

// MARK: - Synchronous Stream Collector

extension StreamHandler {

    /// Collects all events from a stream, accumulating tool calls and yielding agent events.
    ///
    /// This is used by the AgentLoop to fully consume a single turn's stream,
    /// collecting tool calls for subsequent execution.
    ///
    /// - Parameters:
    ///   - stream: The raw LLM stream.
    ///   - onEvent: Callback for each AgentEvent emitted during processing.
    /// - Returns: The collected processing result.
    func collectStream(
        stream: AsyncThrowingStream<StreamEvent, Error>,
        onEvent: @Sendable (AgentEvent) async -> Void
    ) async throws -> StreamProcessingResult {
        var pendingToolCalls: [Int: PendingToolCall] = [:]
        var completedToolCalls: [PendingToolCall] = []
        var finalUsage: TokenUsage?
        var stopReason: String = "end_turn"

        for try await event in stream {
            if Task.isCancelled { break }

            switch event {
            case .messageStart:
                break

            case .contentBlockStart:
                break

            case .textDelta(let text):
                await onEvent(.textDelta(text))

            case .toolUseStart(let id, let name):
                let index = pendingToolCalls.count
                pendingToolCalls[index] = PendingToolCall(id: id, name: name)
                await onEvent(.toolCallStart(name: name, id: id))

            case .toolUseInputDelta(let json):
                if let lastIndex = pendingToolCalls.keys.max(),
                   let pending = pendingToolCalls[lastIndex] {
                    pendingToolCalls[lastIndex] = pending.appendingJSON(json)
                    await onEvent(.toolCallInput(json: json))
                }

            case .contentBlockStop(let index):
                // Try exact index match first
                if let pending = pendingToolCalls[index] {
                    completedToolCalls.append(pending)
                    pendingToolCalls.removeValue(forKey: index)
                } else if !pendingToolCalls.isEmpty {
                    // Fallback: take the first pending
                    let sortedKeys = pendingToolCalls.keys.sorted()
                    if let firstKey = sortedKeys.first {
                        completedToolCalls.append(pendingToolCalls[firstKey]!)
                        pendingToolCalls.removeValue(forKey: firstKey)
                    }
                }

            case .messageDelta(let reason):
                stopReason = reason ?? "end_turn"

            case .messageDone(let usage):
                finalUsage = usage
                await onEvent(.turnComplete(usage: usage))

            case .error(let error):
                await onEvent(.error(error))
            }
        }

        // Flush remaining
        for key in pendingToolCalls.keys.sorted() {
            if let pending = pendingToolCalls[key] {
                completedToolCalls.append(pending)
            }
        }

        let shouldStop = completedToolCalls.isEmpty
        return StreamProcessingResult(
            completedToolCalls: completedToolCalls,
            shouldStop: shouldStop,
            stopReason: stopReason,
            usage: finalUsage
        )
    }
}
