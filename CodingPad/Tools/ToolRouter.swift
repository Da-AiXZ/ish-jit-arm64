// ToolRouter.swift
// CodingPad
//
// Routes tool calls to registered tools, handles permission checks,
// parallel execution, timeout control, and execution logging.

import Foundation
import os

// MARK: - ToolRouter Errors

/// Errors that can occur during tool routing and execution.
enum ToolRouterError: Error, LocalizedError {
    case toolNotFound(String)
    case permissionDenied(tool: String, reason: String)
    case executionTimeout(tool: String, seconds: TimeInterval)
    case executionFailed(tool: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' is not registered."
        case .permissionDenied(let tool, let reason):
            return "Permission denied for tool '\(tool)': \(reason)"
        case .executionTimeout(let tool, let seconds):
            return "Tool '\(tool)' timed out after \(Int(seconds)) seconds."
        case .executionFailed(let tool, let underlying):
            return "Tool '\(tool)' failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Execution Log Entry

/// An immutable record of a single tool execution.
struct ToolExecutionLog: Sendable {
    let toolName: String
    let startedAt: Date
    let duration: TimeInterval
    let result: ToolResult
    let wasParallel: Bool
}

// MARK: - Permission Handler

/// Callback type for handling permission prompts.
/// Returns `true` if the user grants permission, `false` otherwise.
typealias PermissionHandler = @Sendable (String, String) async -> Bool

// MARK: - ToolRouter

/// Routes tool_use requests to registered AgentTool implementations.
///
/// Responsibilities:
/// - Looks up tools by name from the ToolRegistry
/// - Checks permissions before execution
/// - Enforces timeout limits
/// - Supports parallel execution of concurrency-safe tools
/// - Records execution logs
actor ToolRouter {
    private let registry: ToolRegistry
    private let defaultTimeout: TimeInterval
    private var executionLogs: [ToolExecutionLog] = []
    private var permissionHandler: PermissionHandler?
    private let logger = Logger(subsystem: "com.codingpad", category: "ToolRouter")

    init(
        registry: ToolRegistry = .shared,
        defaultTimeout: TimeInterval = 30.0
    ) {
        self.registry = registry
        self.defaultTimeout = defaultTimeout
    }

    /// Set the handler that will be called when a tool needs user permission.
    func setPermissionHandler(_ handler: @escaping PermissionHandler) {
        permissionHandler = handler
    }

    // MARK: - Single Tool Execution

    /// Execute a single tool by name with the given input.
    ///
    /// Steps:
    /// 1. Look up the tool in the registry
    /// 2. Check permission
    /// 3. Execute with timeout
    /// 4. Log the result
    func execute(
        toolName: String,
        input: ToolInput,
        timeout: TimeInterval? = nil
    ) async -> ToolResult {
        let effectiveTimeout = timeout ?? defaultTimeout
        let startTime = Date()

        // 1. Look up tool
        guard let tool = await registry.tool(named: toolName) else {
            let result = ToolResult.error("Tool '\(toolName)' not found. Use the help tool to see available tools.")
            logExecution(toolName: toolName, startedAt: startTime, result: result, wasParallel: false)
            return result
        }

        // 2. Check permission
        let permissionResult = await checkToolPermission(tool: tool, input: input)
        if let denied = permissionResult {
            logExecution(toolName: toolName, startedAt: startTime, result: denied, wasParallel: false)
            return denied
        }

        // 3. Execute with timeout
        let result = await executeWithTimeout(
            tool: tool,
            input: input,
            timeout: effectiveTimeout
        )

        // 4. Log
        logExecution(toolName: toolName, startedAt: startTime, result: result, wasParallel: false)

        return result
    }

    // MARK: - Parallel Execution

    /// A request to execute a tool, used for batching parallel calls.
    struct ToolCall: Sendable {
        let id: String
        let toolName: String
        let input: ToolInput
    }

    /// Result of a parallel tool call, paired with its request ID.
    struct ToolCallResult: Sendable {
        let id: String
        let result: ToolResult
    }

    /// Execute multiple tool calls in parallel where safe.
    ///
    /// Tools marked as `isConcurrencySafe` run concurrently in a TaskGroup.
    /// Non-concurrent tools run sequentially after the parallel batch.
    func executeParallel(
        calls: [ToolCall],
        timeout: TimeInterval? = nil
    ) async -> [ToolCallResult] {
        let effectiveTimeout = timeout ?? defaultTimeout

        // Partition into concurrent and sequential
        var concurrentCalls: [ToolCall] = []
        var sequentialCalls: [ToolCall] = []

        for call in calls {
            if let tool = await registry.tool(named: call.toolName), tool.isConcurrencySafe {
                concurrentCalls.append(call)
            } else {
                sequentialCalls.append(call)
            }
        }

        var results: [ToolCallResult] = []

        // Run concurrent calls in a TaskGroup
        if !concurrentCalls.isEmpty {
            let parallelResults = await withTaskGroup(
                of: ToolCallResult.self,
                returning: [ToolCallResult].self
            ) { group in
                for call in concurrentCalls {
                    group.addTask { [self] in
                        let result = await self.executeSingle(
                            call: call,
                            timeout: effectiveTimeout,
                            wasParallel: true
                        )
                        return result
                    }
                }

                var collected: [ToolCallResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            results.append(contentsOf: parallelResults)
        }

        // Run sequential calls one at a time
        for call in sequentialCalls {
            let result = await executeSingle(
                call: call,
                timeout: effectiveTimeout,
                wasParallel: false
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Execution Logs

    /// Returns all recorded execution logs.
    func getExecutionLogs() -> [ToolExecutionLog] {
        executionLogs
    }

    /// Returns the most recent N execution logs.
    func getRecentLogs(count: Int) -> [ToolExecutionLog] {
        Array(executionLogs.suffix(count))
    }

    /// Clears all execution logs.
    func clearLogs() {
        executionLogs.removeAll()
    }

    // MARK: - Private Helpers

    /// Execute a single ToolCall and return a ToolCallResult.
    private func executeSingle(
        call: ToolCall,
        timeout: TimeInterval,
        wasParallel: Bool
    ) async -> ToolCallResult {
        let startTime = Date()

        guard let tool = await registry.tool(named: call.toolName) else {
            let result = ToolResult.error("Tool '\(call.toolName)' not found.")
            logExecution(toolName: call.toolName, startedAt: startTime, result: result, wasParallel: wasParallel)
            return ToolCallResult(id: call.id, result: result)
        }

        let permissionResult = await checkToolPermission(tool: tool, input: call.input)
        if let denied = permissionResult {
            logExecution(toolName: call.toolName, startedAt: startTime, result: denied, wasParallel: wasParallel)
            return ToolCallResult(id: call.id, result: denied)
        }

        let result = await executeWithTimeout(tool: tool, input: call.input, timeout: timeout)
        logExecution(toolName: call.toolName, startedAt: startTime, result: result, wasParallel: wasParallel)

        return ToolCallResult(id: call.id, result: result)
    }

    /// Check permission for a tool. Returns a denied ToolResult, or nil if allowed.
    private func checkToolPermission(
        tool: any AgentTool,
        input: ToolInput
    ) async -> ToolResult? {
        let decision = tool.checkPermission(input)

        switch decision {
        case .allow:
            return nil

        case .ask(let reason):
            guard let handler = permissionHandler else {
                logger.warning("No permission handler set; denying tool '\(tool.name)'")
                return ToolResult.error("Permission required for '\(tool.name)': \(reason). No permission handler configured.")
            }
            let granted = await handler(tool.name, reason)
            if granted {
                return nil
            } else {
                return ToolResult.error("User denied permission for '\(tool.name)': \(reason)")
            }

        case .deny(let reason):
            logger.info("Permission denied for tool '\(tool.name)': \(reason)")
            return ToolResult.error("Permission denied for '\(tool.name)': \(reason)")
        }
    }

    /// Execute a tool with a timeout. Returns an error ToolResult on timeout or failure.
    private func executeWithTimeout(
        tool: any AgentTool,
        input: ToolInput,
        timeout: TimeInterval
    ) async -> ToolResult {
        do {
            let result = try await withThrowingTaskGroup(of: ToolResult.self) { group in
                group.addTask {
                    try await tool.execute(input)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ToolRouterError.executionTimeout(tool: tool.name, seconds: timeout)
                }

                // Return the first successful result; cancel the other task
                guard let result = try await group.next() else {
                    throw ToolRouterError.executionFailed(
                        tool: tool.name,
                        underlying: ToolRouterError.executionTimeout(tool: tool.name, seconds: timeout)
                    )
                }
                group.cancelAll()
                return result
            }

            logger.debug("Tool '\(tool.name)' executed successfully")
            return result

        } catch let error as ToolRouterError {
            logger.error("Tool '\(tool.name)' error: \(error.localizedDescription)")
            return ToolResult.error(error.localizedDescription ?? "Unknown tool error")

        } catch {
            logger.error("Tool '\(tool.name)' unexpected error: \(error.localizedDescription)")
            return ToolResult.error("Tool '\(tool.name)' failed: \(error.localizedDescription)")
        }
    }

    /// Record an execution log entry.
    private func logExecution(
        toolName: String,
        startedAt: Date,
        result: ToolResult,
        wasParallel: Bool
    ) {
        let duration = Date().timeIntervalSince(startedAt)
        let log = ToolExecutionLog(
            toolName: toolName,
            startedAt: startedAt,
            duration: duration,
            result: result,
            wasParallel: wasParallel
        )
        executionLogs.append(log)

        let status = result.isError ? "ERROR" : "OK"
        logger.info("[\(status)] \(toolName) completed in \(String(format: "%.2f", duration))s (parallel: \(wasParallel))")
    }
}
