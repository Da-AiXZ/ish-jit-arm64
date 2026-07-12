// HelpTool.swift
// CodingPad
//
// Displays help information about available tools and usage.

import Foundation

// MARK: - HelpTool

/// Displays help information about available tools and their usage.
///
/// Can show a summary of all tools or detailed help for a specific tool.
/// Read-only and concurrency-safe.
struct HelpTool: AgentTool {
    let name = "help"

    let description = "Displays help information about available tools and their usage."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "topic": .init(
                type: "string",
                description: "Optional topic or tool name to get detailed help for. If omitted, shows a summary of all tools.",
                enumValues: nil
            )
        ],
        required: []
    )

    let usagePrompt = """
    Displays help information about available tools.

    - Without a `topic`, returns a summary list of all available tools with descriptions.
    - With a `topic` set to a tool name, returns detailed usage information for that tool.
    - Use this to discover what tools are available and how to use them.
    """

    let isReadOnly = true
    let isConcurrencySafe = true

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        .allow
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        let topic = input.string(for: "topic")

        let registry = ToolRegistry.shared
        let allTools = await registry.allTools()

        // If a specific topic is requested, find that tool
        if let topic = topic, !topic.isEmpty {
            return await showToolDetail(topic: topic, allTools: allTools)
        }

        // Otherwise, show summary of all tools
        return showAllTools(allTools)
    }

    // MARK: - Formatting

    /// Shows detailed help for a specific tool.
    private func showToolDetail(topic: String, allTools: [any AgentTool]) async -> ToolResult {
        // Try exact match first
        if let tool = allTools.first(where: { $0.name == topic }) {
            return formatToolDetail(tool)
        }

        // Try case-insensitive match
        let loweredTopic = topic.lowercased()
        if let tool = allTools.first(where: { $0.name.lowercased() == loweredTopic }) {
            return formatToolDetail(tool)
        }

        // Try partial match
        let partialMatches = allTools.filter {
            $0.name.lowercased().contains(loweredTopic) ||
            $0.description.lowercased().contains(loweredTopic)
        }

        if partialMatches.isEmpty {
            let availableNames = allTools.map(\.name).sorted().joined(separator: ", ")
            return .error("No tool found matching '\(topic)'. Available tools: \(availableNames)")
        }

        if partialMatches.count == 1 {
            return formatToolDetail(partialMatches[0])
        }

        // Multiple matches
        var output = "Multiple tools match '\(topic)':\n\n"
        for tool in partialMatches {
            output += "  - \(tool.name): \(tool.description)\n"
        }
        output += "\nUse the exact tool name for detailed help."
        return .success(output)
    }

    /// Formats detailed help for a single tool.
    private func formatToolDetail(_ tool: any AgentTool) -> ToolResult {
        var output = "# \(tool.name)\n\n"
        output += "\(tool.description)\n\n"

        // Properties
        output += "## Parameters\n\n"
        let requiredSet = Set(tool.inputSchema.required)
        if tool.inputSchema.properties.isEmpty {
            output += "  (no parameters)\n"
        } else {
            for (name, prop) in tool.inputSchema.properties.sorted(by: { $0.key < $1.key }) {
                let requiredMark = requiredSet.contains(name) ? " (required)" : " (optional)"
                output += "  - `\(name)` (\(prop.type))\(requiredMark): \(prop.description)\n"
                if let enumValues = prop.enumValues {
                    output += "    Allowed values: \(enumValues.joined(separator: ", "))\n"
                }
            }
        }

        // Attributes
        output += "\n## Attributes\n\n"
        output += "  - Read-only: \(tool.isReadOnly ? "Yes" : "No")\n"
        output += "  - Concurrency-safe: \(tool.isConcurrencySafe ? "Yes" : "No")\n"

        // Usage prompt
        output += "\n## Usage\n\n"
        output += tool.usagePrompt

        return .success(output)
    }

    /// Shows a summary of all available tools.
    private func showAllTools(_ tools: [any AgentTool]) -> ToolResult {
        let sorted = tools.sorted { $0.name < $1.name }

        var output = "# Available Tools\n\n"
        output += "| Tool | Description | Read-Only |\n"
        output += "|------|-------------|----------|\n"

        for tool in sorted {
            let ro = tool.isReadOnly ? "Yes" : "No"
            output += "| \(tool.name) | \(tool.description) | \(ro) |\n"
        }

        output += "\nUse `help` with a tool name as the `topic` for detailed usage information."
        output += "\nTotal: \(sorted.count) tools available."

        return .success(output)
    }
}
