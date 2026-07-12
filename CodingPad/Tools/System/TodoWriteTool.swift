// TodoWriteTool.swift
// CodingPad
//
// Task tracking list management tool.

import Foundation

// MARK: - TodoWriteTool

/// Manages a task tracking list for the current session.
///
/// The list is rendered to the user as a working plan. Each todo has
/// content, status (pending/in_progress/completed), and an activeForm label.
/// Sending a new list replaces the previous one entirely.
struct TodoWriteTool: AgentTool {
    let name = "todo_write"

    let description = "Create and update a task list for the current session. The list is rendered to the user as the working plan."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "todos": .init(
                type: "array",
                description: "The updated todo list as a JSON array. Each item must have: content (string), status (pending|in_progress|completed), and activeForm (present-tense label shown while in progress).",
                enumValues: nil
            )
        ],
        required: ["todos"]
    )

    let usagePrompt = """
    Create and update a task list for the current session. The list is rendered to the user as your working plan.

    - Each todo has `content`, `status` ("pending", "in_progress", "completed"), and `activeForm` (present-tense label shown while in progress).
    - Send the full list each call; it replaces the previous one.
    - Keep one item `in_progress` at a time and mark it `completed` when done.
    - Use this to track progress on multi-step tasks.
    - The todo list reveals out-of-order steps, missing items, extra unnecessary items, wrong granularity, and misinterpreted requirements.
    """

    let isReadOnly = false
    let isConcurrencySafe = false

    // MARK: - Todo Item

    /// Represents a single todo item.
    struct TodoItem: Sendable {
        let content: String
        let status: String
        let activeForm: String
    }

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        .allow
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        // Extract the todos array from input
        guard case .array(let todosArray) = input.parameters["todos"] else {
            return .error("Missing or invalid 'todos' parameter. Expected a JSON array.")
        }

        // Parse and validate todos
        var parsedTodos: [TodoItem] = []
        let validStatuses: Set<String> = ["pending", "in_progress", "completed"]

        for (index, todoValue) in todosArray.enumerated() {
            guard case .object(let todoDict) = todoValue else {
                return .error("Todo item at index \(index) is not a JSON object.")
            }

            guard case .string(let content) = todoDict["content"], !content.isEmpty else {
                return .error("Todo item at index \(index) is missing required field 'content'.")
            }

            guard case .string(let status) = todoDict["status"], validStatuses.contains(status) else {
                return .error("Todo item at index \(index) has invalid 'status'. Must be: pending, in_progress, or completed.")
            }

            guard case .string(let activeForm) = todoDict["activeForm"], !activeForm.isEmpty else {
                return .error("Todo item at index \(index) is missing required field 'activeForm'.")
            }

            parsedTodos.append(TodoItem(content: content, status: status, activeForm: activeForm))
        }

        if parsedTodos.isEmpty {
            return .error("Todo list cannot be empty.")
        }

        // Validate: at most one in_progress
        let inProgressCount = parsedTodos.filter { $0.status == "in_progress" }.count
        if inProgressCount > 1 {
            return .error("Only one todo item can be 'in_progress' at a time. Found \(inProgressCount).")
        }

        // Format output
        var output = "Todo list updated (\(parsedTodos.count) items):\n\n"
        for (index, todo) in parsedTodos.enumerated() {
            let icon: String
            switch todo.status {
            case "completed":
                icon = "[x]"
            case "in_progress":
                icon = "[>]"
            default:
                icon = "[ ]"
            }
            output += "\(index + 1). \(icon) \(todo.content)"
            if todo.status == "in_progress" {
                output += " — \(todo.activeForm)"
            }
            output += "\n"
        }

        let completedCount = parsedTodos.filter { $0.status == "completed" }.count
        let pendingCount = parsedTodos.filter { $0.status == "pending" }.count
        output += "\nProgress: \(completedCount)/\(parsedTodos.count) completed, \(pendingCount) pending"

        return ToolResult(
            content: output,
            metadata: [
                "total": "\(parsedTodos.count)",
                "completed": "\(completedCount)",
                "in_progress": "\(inProgressCount)",
                "pending": "\(pendingCount)"
            ]
        )
    }
}
