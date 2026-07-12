// AgentLoop.swift
// CodingPad
//
// Core harness loop that orchestrates the conversation cycle:
// user message -> context assembly -> LLM call -> tool execution -> loop.
// Modeled after the Claude Code QueryEngine pattern.

import Foundation
import os

// MARK: - AgentLoop Dependencies (Protocol-based DI)

/// Protocol for context assembly. Placeholder for the ContextEngine.
protocol ContextAssembler: Sendable {
    func assemble(
        messages: [Message],
        config: AgentConfig
    ) async throws -> [ContextSegment]
}

/// Protocol for system prompt building. Placeholder for the PromptAssembler.
protocol PromptBuilder: Sendable {
    func build(
        segments: [ContextSegment],
        tools: [any AgentTool],
        config: AgentConfig
    ) -> String
}

// MARK: - AgentLoop Errors

enum AgentLoopError: Error, LocalizedError {
    case noLLMProvider
    case noTools
    case turnLimitExceeded(turns: Int)
    case loopDetected(tool: String)
    case cancelled
    case streamFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noLLMProvider:
            return "No LLM provider configured."
        case .noTools:
            return "No tools available for the agent loop."
        case .turnLimitExceeded(let turns):
            return "Agent loop exceeded \(turns) turns."
        case .loopDetected(let tool):
            return "Loop detected on tool '\(tool)'."
        case .cancelled:
            return "Agent loop was cancelled."
        case .streamFailed(let error):
            return "Stream processing failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Default Placeholder Implementations

/// A no-op context assembler that returns an empty segment list.
/// Used until the real ContextEngine is implemented.
struct DefaultContextAssembler: ContextAssembler {
    func assemble(
        messages: [Message],
        config: AgentConfig
    ) async throws -> [ContextSegment] {
        []
    }
}

/// A minimal prompt builder that returns a basic system prompt.
/// Used until the real PromptAssembler is implemented.
struct DefaultPromptBuilder: PromptBuilder {
    func build(
        segments: [ContextSegment],
        tools: [any AgentTool],
        config: AgentConfig
    ) -> String {
        var prompt = "You are a coding assistant."
        if !segments.isEmpty {
            let contextContent = segments.map(\.content).joined(separator: "\n\n")
            prompt += "\n\n" + contextContent
        }
        return prompt
    }
}

// MARK: - Permission Resolution Callback

/// Callback for resolving permission prompts asynchronously.
/// Called when a tool requires user confirmation.
/// Returns `true` if the user grants permission.
typealias PermissionResolver = @Sendable (String, ToolInput, String) async -> Bool

// MARK: - AgentLoop

/// The core agent harness loop.
///
/// Orchestrates the full conversation cycle:
/// 1. Assemble context from messages and project state.
/// 2. Build the system prompt.
/// 3. Stream an LLM response.
/// 4. Process tool_use blocks from the response.
/// 5. Evaluate permissions for each tool call.
/// 6. Execute approved tool calls.
/// 7. Inject tool results as messages.
/// 8. Loop back to step 3 until the model stops or maxTurns is reached.
///
/// Uses `@Observable` for UI binding (iOS 17+).
@Observable
final class AgentLoop {
    // MARK: - Observable State

    /// Whether the loop is currently processing.
    private(set) var isRunning: Bool = false

    // MARK: - Dependencies (injected)

    private let llmProvider: any LLMProvider
    private let toolRouter: ToolRouter
    let permissionEngine: PermissionEngine
    private let contextAssembler: any ContextAssembler
    private let promptBuilder: any PromptBuilder
    private let streamHandler: StreamHandler
    private let logger = Logger(subsystem: "com.codingpad", category: "AgentLoop")

    /// Bridge that syncs tool side-effects to AppState.
    /// Set after init so the loop can run without a UI during tests.
    weak var bridge: ToolAppStateBridge?

    // MARK: - Lifecycle

    private var currentTask: Task<Void, Never>?

    init(
        llmProvider: any LLMProvider,
        toolRouter: ToolRouter = ToolRouter(),
        permissionEngine: PermissionEngine = PermissionEngine(),
        contextAssembler: any ContextAssembler = DefaultContextAssembler(),
        promptBuilder: any PromptBuilder = DefaultPromptBuilder()
    ) {
        self.llmProvider = llmProvider
        self.toolRouter = toolRouter
        self.permissionEngine = permissionEngine
        self.contextAssembler = contextAssembler
        self.promptBuilder = promptBuilder
        self.streamHandler = StreamHandler()
    }

    // MARK: - Public API

    /// Run the agent loop for a user message.
    ///
    /// Returns an `AsyncThrowingStream` of `AgentEvent`s that the UI can
    /// consume to display real-time progress.
    ///
    /// - Parameters:
    ///   - userMessage: The user's input message.
    ///   - messages: The conversation history (mutated in-place as the loop runs).
    ///   - tools: The list of tools available to the agent.
    ///   - config: The agent configuration.
    ///   - permissionResolver: Callback for resolving permission prompts.
    /// - Returns: An async stream of agent events.
    func run(
        userMessage: String,
        messages: inout [Message],
        tools: [any AgentTool],
        config: AgentConfig,
        permissionResolver: @escaping PermissionResolver
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        // Append user message
        let userMsg = Message(role: .user, text: userMessage)
        messages.append(userMsg)

        // Capture messages by value for the stream closure
        let capturedMessages = messages
        let toolDefs = tools.map(\.toolDefinition)

        return AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish(throwing: AgentLoopError.cancelled)
                return
            }

            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: AgentLoopError.cancelled)
                    return
                }

                await self.setRunning(true)
                defer {
                    Task { await self.setRunning(false) }
                }

                do {
                    var loopMessages = capturedMessages
                    let turnManager = TurnManager(maxTurns: config.maxTurns)

                    try await self.executeLoop(
                        messages: &loopMessages,
                        tools: tools,
                        toolDefinitions: toolDefs,
                        config: config,
                        turnManager: turnManager,
                        permissionResolver: permissionResolver,
                        continuation: continuation
                    )

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }

            self.currentTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Cancel the currently running agent loop.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private Loop Implementation

    /// The main harness loop.
    private func executeLoop(
        messages: inout [Message],
        tools: [any AgentTool],
        toolDefinitions: [ToolDefinition],
        config: AgentConfig,
        turnManager: TurnManager,
        permissionResolver: @escaping PermissionResolver,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        var shouldContinue = true

        while shouldContinue {
            if Task.isCancelled {
                continuation.yield(.done(stopReason: "cancelled"))
                return
            }

            // 1. Increment turn
            do {
                try turnManager.incrementTurn()
            } catch {
                continuation.yield(.error(error))
                continuation.yield(.done(stopReason: "max_turns"))
                return
            }

            // 2. Assemble context
            let segments = try await contextAssembler.assemble(
                messages: messages,
                config: config
            )

            // 3. Build system prompt
            let systemPrompt = promptBuilder.build(
                segments: segments,
                tools: tools,
                config: config
            )

            // 4. Stream LLM response
            let stream = llmProvider.sendMessage(
                messages: messages,
                systemPrompt: systemPrompt,
                tools: toolDefinitions,
                maxTokens: config.maxTokens
            )

            // 5. Collect and process stream
            let result = try await streamHandler.collectStream(
                stream: stream,
                onEvent: { event in
                    continuation.yield(event)
                }
            )

            // 6. Record token usage
            if let usage = result.usage {
                turnManager.addUsage(usage)
            }

            // 7. If no tool calls, we're done
            if result.shouldStop {
                continuation.yield(.done(stopReason: result.stopReason))
                shouldContinue = false
                continue
            }

            // 8. Process tool calls
            let toolCallResults = try await processToolCalls(
                completedToolCalls: result.completedToolCalls,
                tools: tools,
                config: config,
                turnManager: turnManager,
                permissionResolver: permissionResolver,
                continuation: continuation
            )

            // 9. Build assistant message with tool_use blocks
            let assistantContentBlocks = result.completedToolCalls.map { pending -> ContentBlock in
                let inputParams: [String: JSONValue]
                if let parsed = StreamHandler.parseToolInput(json: pending.accumulatedJSON) {
                    inputParams = parsed.parameters
                } else {
                    inputParams = [:]
                }
                return .toolUse(ContentBlock.ToolUseBlock(
                    id: pending.id,
                    name: pending.name,
                    input: inputParams
                ))
            }

            let assistantMsg = Message(
                role: .assistant,
                content: assistantContentBlocks
            )
            messages.append(assistantMsg)

            // 10. Build tool result messages
            let toolResultBlocks = toolCallResults.map { callResult -> ContentBlock in
                .toolResult(ContentBlock.ToolResultBlock(
                    toolUseId: callResult.id,
                    content: callResult.result.content,
                    isError: callResult.result.isError
                ))
            }

            let toolResultMsg = Message(
                role: .user,
                content: toolResultBlocks
            )
            messages.append(toolResultMsg)

            // 11. Continue the loop (back to step 3 in the next iteration)
            logger.info("Turn \(turnManager.currentTurnNumber) completed with \(toolCallResults.count) tool calls")
        }
    }

    /// Process all completed tool calls from a single turn.
    private func processToolCalls(
        completedToolCalls: [PendingToolCall],
        tools: [any AgentTool],
        config: AgentConfig,
        turnManager: TurnManager,
        permissionResolver: @escaping PermissionResolver,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> [ToolRouter.ToolCallResult] {
        var results: [ToolRouter.ToolCallResult] = []

        for pending in completedToolCalls {
            // Parse input
            guard let input = StreamHandler.parseToolInput(json: pending.accumulatedJSON) else {
                let errorResult = ToolResult.error(
                    "Failed to parse tool input JSON for '\(pending.name)'."
                )
                continuation.yield(.toolCallComplete(name: pending.name, result: errorResult))
                results.append(ToolRouter.ToolCallResult(id: pending.id, result: errorResult))
                continue
            }

            // Loop detection
            let loopDetected = turnManager.recordToolCall(
                toolName: pending.name,
                input: input
            )
            if loopDetected {
                let errorResult = ToolResult.error(
                    "Loop detected: tool '\(pending.name)' called repeatedly with identical parameters. Stopping."
                )
                continuation.yield(.toolCallComplete(name: pending.name, result: errorResult))
                continuation.yield(.done(stopReason: "loop_detected"))
                throw AgentLoopError.loopDetected(tool: pending.name)
            }

            // Permission check via PermissionEngine
            let scope = determineScope(for: pending.name)
            let decision = await permissionEngine.evaluate(
                tool: pending.name,
                input: input,
                scope: scope,
                mode: config.permissionMode
            )

            switch decision {
            case .allow:
                // Execute directly
                let result = await toolRouter.execute(
                    toolName: pending.name,
                    input: input
                )
                continuation.yield(.toolCallComplete(name: pending.name, result: result))
                await handleBridge(toolName: pending.name, input: input, result: result)
                results.append(ToolRouter.ToolCallResult(id: pending.id, result: result))

            case .ask(let reason):
                // Request permission from the user
                continuation.yield(.permissionRequired(
                    tool: pending.name,
                    input: input,
                    id: pending.id
                ))
                let granted = await permissionResolver(pending.name, input, reason)

                if granted {
                    let result = await toolRouter.execute(
                        toolName: pending.name,
                        input: input
                    )
                    continuation.yield(.toolCallComplete(name: pending.name, result: result))
                    await handleBridge(toolName: pending.name, input: input, result: result)
                    results.append(ToolRouter.ToolCallResult(id: pending.id, result: result))
                } else {
                    let deniedResult = ToolResult.error(
                        "User denied permission for tool '\(pending.name)': \(reason)"
                    )
                    continuation.yield(.toolCallComplete(name: pending.name, result: deniedResult))
                    results.append(ToolRouter.ToolCallResult(id: pending.id, result: deniedResult))
                }

            case .deny(let reason):
                let deniedResult = ToolResult.error(
                    "Permission denied for tool '\(pending.name)': \(reason)"
                )
                continuation.yield(.toolCallComplete(name: pending.name, result: deniedResult))
                results.append(ToolRouter.ToolCallResult(id: pending.id, result: deniedResult))
            }
        }

        return results
    }

    /// Forward a tool execution result to the bridge (if attached).
    @MainActor
    private func handleBridge(toolName: String, input: ToolInput, result: ToolResult) {
        bridge?.handleToolResult(toolName: toolName, input: input, result: result)
    }

    /// Determine the permission scope for a given tool name.
    private func determineScope(for toolName: String) -> PermissionScope {
        let fsTools: Set<String> = [
            "file_read", "file_write", "file_edit", "glob", "grep",
        ]
        let netTools: Set<String> = ["web_fetch"]
        let shellTools: Set<String> = ["shell", "bash"]

        if fsTools.contains(toolName) {
            return .fs
        } else if netTools.contains(toolName) {
            return .net
        } else if shellTools.contains(toolName) {
            return .shell
        }

        return .tool
    }

    /// Set the running state on the main actor.
    @MainActor
    private func setRunning(_ value: Bool) {
        isRunning = value
    }
}
