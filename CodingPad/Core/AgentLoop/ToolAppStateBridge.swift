// ToolAppStateBridge.swift
// CodingPad
//
// Bridges tool execution side-effects to AppState.
// After a tool completes, this bridge applies state changes
// (todo updates, compact requests, file-tree refreshes)
// so the UI reflects tool results immediately.

import Foundation
import os

// MARK: - ToolAppStateBridge

/// Synchronises tool execution results with observable AppState.
///
/// Each handler maps a tool name to an AppState mutation:
/// - `todo_write` → parse todos JSON and call `appState.updateTodos(_:)`
/// - `compact`    → set a flag so AgentLoop compacts on the next turn
/// - `file_write` / `file_edit` → post a notification for file-tree refresh
@MainActor
final class ToolAppStateBridge {
    private let appState: AppState
    private let logger = Logger(subsystem: "com.codingpad", category: "ToolAppStateBridge")

    /// When `true`, the AgentLoop should compact the context on the next turn.
    private(set) var needsCompact: Bool = false

    /// When `true`, the file-tree view should reload its data.
    private(set) var needsFileTreeRefresh: Bool = false

    /// Notification posted when a file-modifying tool completes.
    static let fileTreeNeedsRefreshNotification = Notification.Name("ToolAppStateBridge.fileTreeNeedsRefresh")

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    /// Called after every tool execution to apply side-effects to AppState.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - input:    The parsed input that was passed to the tool.
    ///   - result:   The result returned by the tool.
    func handleToolResult(toolName: String, input: ToolInput, result: ToolResult) {
        switch toolName {
        case "todo_write":
            handleTodoWrite(input: input)
        case "compact":
            handleCompactRequest()
        case "file_write", "file_edit":
            handleFileChange(input: input)
        default:
            break
        }
    }

    /// Resets the compact flag after the AgentLoop has acted on it.
    func clearCompactFlag() {
        needsCompact = false
    }

    /// Resets the file-tree refresh flag after the UI has refreshed.
    func clearFileTreeRefreshFlag() {
        needsFileTreeRefresh = false
    }

    // MARK: - Handlers

    /// Parse the `todos` JSON array from tool input and push it into AppState.
    private func handleTodoWrite(input: ToolInput) {
        guard case .array(let todosArray) = input.parameters["todos"] else {
            logger.warning("todo_write: missing or invalid 'todos' parameter")
            return
        }

        let parsedTodos = todosArray.compactMap { element -> TodoItem? in
            guard case .object(let dict) = element else { return nil }

            guard case .string(let content) = dict["content"],
                  case .string(let statusRaw) = dict["status"],
                  let status = TodoStatus(rawValue: statusRaw) else {
                return nil
            }

            let activeForm: String?
            if case .string(let form) = dict["activeForm"] {
                activeForm = form
            } else {
                activeForm = nil
            }

            return TodoItem(
                content: content,
                status: status,
                activeForm: activeForm
            )
        }

        appState.updateTodos(parsedTodos)
        logger.info("todo_write: updated \(parsedTodos.count) todos in AppState")
    }

    /// Mark that a context compaction is requested.
    private func handleCompactRequest() {
        needsCompact = true
        logger.info("compact: flagged for next turn")
    }

    /// Notify observers that a file-modifying tool has completed.
    private func handleFileChange(input: ToolInput) {
        needsFileTreeRefresh = true

        let path = input.string(for: "file_path") ?? "unknown"
        logger.info("file change detected: \(path)")

        NotificationCenter.default.post(
            name: Self.fileTreeNeedsRefreshNotification,
            object: nil,
            userInfo: ["file_path": path]
        )
    }
}
