// ToolProtocol.swift
// CodingPad
//
// Defines the AgentTool protocol and ToolRegistry for tool discovery and registration.

import Foundation

// MARK: - AgentTool Protocol

/// Protocol that all agent tools must conform to.
/// Each tool is self-contained: schema, permissions, execution, and usage prompt
/// are all defined within a single conforming type.
protocol AgentTool: Sendable {
    /// Unique identifier for this tool (e.g. "file_read", "grep").
    var name: String { get }

    /// Human-readable description of what this tool does.
    var description: String { get }

    /// JSON Schema describing the tool's input parameters.
    var inputSchema: ToolInputSchema { get }

    /// Detailed usage instructions injected into the system prompt.
    /// Should describe parameters, use cases, and examples in Claude Code style.
    var usagePrompt: String { get }

    /// Whether this tool only reads data and never modifies state.
    var isReadOnly: Bool { get }

    /// Whether this tool is safe to run concurrently with other tools.
    var isConcurrencySafe: Bool { get }

    /// Check whether the tool should be allowed to run with the given input.
    /// Returns `.allow`, `.ask(reason:)`, or `.deny(reason:)`.
    func checkPermission(_ input: ToolInput) -> PermissionDecision

    /// Execute the tool with the given input.
    /// Throws on unrecoverable errors; returns `ToolResult.error` for expected failures.
    func execute(_ input: ToolInput) async throws -> ToolResult
}

// MARK: - AgentTool Default Implementations

extension AgentTool {
    /// Converts this tool into a `ToolDefinition` for the LLM API.
    var toolDefinition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            inputSchema: inputSchema
        )
    }
}

// MARK: - ToolRegistry

/// Thread-safe registry that holds all available tools keyed by name.
/// Tools are registered once at startup and looked up by the ToolRouter.
actor ToolRegistry {
    /// Singleton shared instance.
    static let shared = ToolRegistry()

    private var tools: [String: any AgentTool] = [:]

    private init() {}

    /// Register a single tool. Overwrites any existing tool with the same name.
    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    /// Register multiple tools at once.
    func registerAll(_ newTools: [any AgentTool]) {
        for tool in newTools {
            tools[tool.name] = tool
        }
    }

    /// Look up a tool by name. Returns nil if not found.
    func tool(named name: String) -> (any AgentTool)? {
        tools[name]
    }

    /// Returns all registered tools.
    func allTools() -> [any AgentTool] {
        Array(tools.values)
    }

    /// Returns tool definitions for all registered tools (for LLM API).
    func allToolDefinitions() -> [ToolDefinition] {
        tools.values.map(\.toolDefinition)
    }

    /// Returns the names of all registered tools.
    func allToolNames() -> [String] {
        Array(tools.keys).sorted()
    }

    /// Returns the number of registered tools.
    var count: Int {
        tools.count
    }

    /// Removes all registered tools.
    func removeAll() {
        tools.removeAll()
    }

    /// Creates the default set of all built-in tools and registers them.
    func registerDefaults() {
        let defaultTools: [any AgentTool] = [
            FileReadTool(),
            FileWriteTool(),
            FileEditTool(),
            GlobTool(),
            GrepTool(),
            WebFetchTool(),
            TodoWriteTool(),
            CompactTool(),
            HelpTool()
        ]
        registerAll(defaultTools)
    }
}
