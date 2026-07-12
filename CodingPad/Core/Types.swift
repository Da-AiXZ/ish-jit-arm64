// Types.swift
// CodingPad
//
// Core type definitions shared across all modules.

import Foundation

// MARK: - Message Types

/// Represents a role in the conversation.
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// A content block within a message — can be text, tool use, or tool result.
enum ContentBlock: Codable, Sendable {
    case text(String)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)

    // MARK: - Nested Types

    struct ToolUseBlock: Codable, Sendable {
        let id: String
        let name: String
        let input: [String: JSONValue]
    }

    struct ToolResultBlock: Codable, Sendable {
        let toolUseId: String
        let content: String
        let isError: Bool
    }
}

/// A single message in the conversation history.
struct Message: Identifiable, Codable, Sendable {
    let id: String
    let role: MessageRole
    let content: [ContentBlock]
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: [ContentBlock],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    /// Convenience initializer for a simple text message.
    init(role: MessageRole, text: String) {
        self.init(role: role, content: [.text(text)])
    }
}

// MARK: - Tool Types

/// Schema-based input definition for a tool, following Anthropic's tool_use format.
struct ToolInputSchema: Codable, Sendable {
    let type: String // always "object"
    let properties: [String: PropertySchema]
    let required: [String]

    struct PropertySchema: Codable, Sendable {
        let type: String
        let description: String
        let enumValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }
}

/// Definition of a tool sent to the LLM API.
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let inputSchema: ToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// Input passed to a tool's execute method.
struct ToolInput: Sendable {
    let parameters: [String: JSONValue]

    func string(for key: String) -> String? {
        if case .string(let value) = parameters[key] {
            return value
        }
        return nil
    }

    func int(for key: String) -> Int? {
        if case .number(let value) = parameters[key] {
            return Int(value)
        }
        return nil
    }

    func bool(for key: String) -> Bool? {
        if case .bool(let value) = parameters[key] {
            return value
        }
        return nil
    }
}

/// Result returned by a tool execution.
struct ToolResult: Sendable {
    let content: String
    let isError: Bool
    let metadata: [String: String]

    init(content: String, isError: Bool = false, metadata: [String: String] = [:]) {
        self.content = content
        self.isError = isError
        self.metadata = metadata
    }

    static func success(_ content: String) -> ToolResult {
        ToolResult(content: content)
    }

    static func error(_ message: String) -> ToolResult {
        ToolResult(content: message, isError: true)
    }
}

// MARK: - Permission Types

/// The three-valued permission decision (ABAC model).
enum PermissionDecision: Sendable {
    case allow
    case ask(reason: String)
    case deny(reason: String)
}

/// Permission mode controlling the overall strictness.
enum PermissionMode: String, Codable, Sendable {
    case `default`   // Sensitive operations require confirmation
    case auto        // Most operations auto-allowed (personal use)
    case plan        // All write operations require confirmation
}

/// Resource scope for permission evaluation.
enum PermissionScope: String, Codable, Sendable {
    case tool
    case fs
    case net
    case secret
    case shell
}

// MARK: - LLM Types

/// Events emitted during streaming LLM responses.
enum StreamEvent: Sendable {
    case messageStart(messageId: String)
    case contentBlockStart(index: Int, type: String)
    case textDelta(text: String)
    case toolUseStart(id: String, name: String)
    case toolUseInputDelta(json: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageDone(usage: TokenUsage)
    case error(Error)
}

/// Token usage statistics for a single API call.
struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int

    init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Context Types

/// Levels of context loaded on demand (OpenViking-inspired L0/L1/L2).
enum ContextLevel: Int, Comparable, Sendable {
    case l0 = 0  // Always loaded: system prompt + user prefs + project meta (<2K tokens)
    case l1 = 1  // On-demand: CLAUDE.md + file summaries + recent memories (<8K tokens)
    case l2 = 2  // Deep: full file contents + git diff + search results (variable)

    static func < (lhs: ContextLevel, rhs: ContextLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A context segment assembled by the ContextEngine.
struct ContextSegment: Sendable {
    let level: ContextLevel
    let label: String
    let content: String
    let isCacheable: Bool
    let estimatedTokens: Int
}

// MARK: - Memory Types

/// Types of persistent memory entries.
enum MemoryType: String, Codable, Sendable {
    case user       // Who the user is (role, expertise, preferences)
    case feedback   // Guidance on how the agent should work
    case project    // Ongoing work, goals, constraints
    case reference  // Pointers to external resources
}

/// A single memory entry stored in the memory directory.
struct MemoryEntry: Identifiable, Codable, Sendable {
    let id: String
    let name: String         // kebab-case slug
    let description: String  // one-line summary
    let type: MemoryType
    let content: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        type: MemoryType,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Session Types

/// Represents a conversation session.
struct Session: Identifiable, Codable, Sendable {
    let id: String
    let projectPath: String?
    let createdAt: Date
    var updatedAt: Date
    var title: String?
    var messageCount: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int

    init(
        id: String = UUID().uuidString,
        projectPath: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.title = title
        self.messageCount = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
    }
}

// MARK: - JSON Value (for dynamic tool inputs)

/// A type-safe representation of arbitrary JSON values.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Agent Configuration

/// Global configuration for the agent.
struct AgentConfig: Codable, Sendable {
    var modelId: String
    var maxTokens: Int
    var maxTurns: Int
    var permissionMode: PermissionMode
    var autoCompactThreshold: Double // 0.0 - 1.0, e.g. 0.8 = 80% of context window
    var language: String
    var outputStyle: String

    static let `default` = AgentConfig(
        modelId: "claude-opus-4-8",
        maxTokens: 16384,
        maxTurns: 50,
        permissionMode: .default,
        autoCompactThreshold: 0.8,
        language: "zh-CN",
        outputStyle: "concise"
    )
}
