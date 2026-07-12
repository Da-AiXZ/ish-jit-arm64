// AppState.swift
// CodingPad
//
// Global application state using ObservableObject (iOS 16+).
// Single source of truth for session, messages, processing status,
// and configuration. All UI binds to this object.

import Foundation
import os

// MARK: - Todo Item

/// A single todo item tracked during the agent session.
struct TodoItem: Identifiable, Codable, Sendable {
    let id: String
    let content: String
    let status: TodoStatus
    let activeForm: String?

    init(
        id: String = UUID().uuidString,
        content: String,
        status: TodoStatus = .pending,
        activeForm: String? = nil
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }

    /// Create a new TodoItem with an updated status (immutable pattern).
    func withStatus(_ newStatus: TodoStatus) -> TodoItem {
        TodoItem(
            id: id,
            content: content,
            status: newStatus,
            activeForm: activeForm
        )
    }
}

// MARK: - Todo Status

enum TodoStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

// MARK: - App Error

/// Application-level errors surfaced to the user.
enum AppError: Error, LocalizedError, Identifiable {
    case missingAPIKey
    case sessionNotFound(String)
    case projectNotFound(String)
    case agentLoopFailed(Error)
    case storageFailed(Error)

    var id: String {
        switch self {
        case .missingAPIKey: return "missing_api_key"
        case .sessionNotFound(let id): return "session_not_found_\(id)"
        case .projectNotFound(let path): return "project_not_found_\(path)"
        case .agentLoopFailed: return "agent_loop_failed"
        case .storageFailed: return "storage_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not configured. Please add your API key in Settings."
        case .sessionNotFound(let id):
            return "Session '\(id)' not found."
        case .projectNotFound(let path):
            return "Project at '\(path)' not found."
        case .agentLoopFailed(let error):
            return "Agent loop failed: \(error.localizedDescription)"
        case .storageFailed(let error):
            return "Storage operation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - AppState

/// Global observable state for the CodingPad application.
///
/// Uses `ObservableObject` for SwiftUI integration (iOS 16+ compatible).
/// All state mutations happen on the main actor to ensure UI consistency.
///
/// Key responsibilities:
/// - Holds the current conversation session and messages
/// - Tracks processing state for the agent loop
/// - Manages todo items for multi-step task tracking
/// - Stores the active project path and configuration
/// - Surfaces errors for display in the UI
@MainActor
final class AppState: ObservableObject {

    // MARK: - Session State

    /// The current active conversation session.
    @Published var currentSession: Session?

    /// All messages in the current conversation.
    @Published var messages: [Message] = []

    /// Whether the agent loop is currently processing.
    @Published var isProcessing: Bool = false

    /// Streaming text being assembled for the current response.
    @Published var streamingText: String = ""

    // MARK: - Todo Tracking

    /// Todo items for the current multi-step task.
    @Published var todos: [TodoItem] = []

    // MARK: - Project State

    /// The file path of the currently active project.
    @Published var activeProjectPath: String?

    /// List of known project paths.
    @Published var recentProjects: [String] = []

    // MARK: - Configuration

    /// Global agent configuration.
    @Published var config: AgentConfig = .default

    // MARK: - Error State

    /// The most recent error to display to the user.
    @Published var currentError: AppError?

    /// Whether an error alert should be shown.
    @Published var showError: Bool = false

    // MARK: - Permission State

    /// A pending permission request waiting for user confirmation.
    /// When non-nil, the UI shows a permission alert.
    @Published var pendingPermission: PermissionRequest?

    // MARK: - Active Tool Calls (for UI display)

    /// Tool calls currently being executed, keyed by tool call ID.
    @Published var activeToolCalls: [String: String] = [:]

    // MARK: - File Tree State

    /// When `true`, the file-tree view should refresh its data.
    @Published var needsFileTreeRefresh: Bool = false

    // MARK: - Agent Loop Reference

    /// The AgentLoop instance driving this session (held for ChatView to consume).
    @Published var agentLoop: AgentLoop?

    // MARK: - Usage Statistics

    /// Token usage snapshot for the current session.
    @Published var sessionUsage: SessionUsageSnapshot?

    // MARK: - Initialization

    private let logger = Logger(subsystem: "com.codingpad", category: "AppState")

    init() {
        logger.debug("AppState initialized")
    }

    // MARK: - Session Management

    /// Start a new conversation session.
    func startNewSession(projectPath: String? = nil) {
        let session = Session(projectPath: projectPath ?? activeProjectPath)
        currentSession = session
        messages = []
        todos = []
        streamingText = ""
        currentError = nil
        sessionUsage = nil
        pendingPermission = nil
        activeToolCalls.removeAll()
        logger.info("New session started: \(session.id)")
    }

    /// Update the current session's metadata after a turn completes.
    func updateSessionAfterTurn(usage: TokenUsage) {
        guard var session = currentSession else { return }
        session.updatedAt = Date()
        session.messageCount = messages.count
        session.totalInputTokens += usage.inputTokens
        session.totalOutputTokens += usage.outputTokens
        currentSession = session
    }

    // MARK: - Message Management

    /// Append a message to the conversation.
    func appendMessage(_ message: Message) {
        messages.append(message)
    }

    /// Append streaming text delta.
    func appendStreamingText(_ delta: String) {
        streamingText += delta
    }

    /// Finalize streaming text into a message.
    func finalizeStreamingText() {
        guard !streamingText.isEmpty else { return }
        let message = Message(role: .assistant, text: streamingText)
        messages.append(message)
        streamingText = ""
    }

    /// Clear all messages.
    func clearMessages() {
        messages = []
        streamingText = ""
    }

    // MARK: - Todo Management

    /// Replace the entire todo list (immutable swap).
    func updateTodos(_ newTodos: [TodoItem]) {
        todos = newTodos
    }

    /// Update a single todo's status.
    func updateTodoStatus(id: String, status: TodoStatus) {
        todos = todos.map { todo in
            if todo.id == id {
                return todo.withStatus(status)
            }
            return todo
        }
    }

    // MARK: - Permission Management

    /// Display a permission request to the user.
    func requestPermission(_ request: PermissionRequest) {
        pendingPermission = request
    }

    /// Clear the pending permission request (user has responded).
    func clearPendingPermission() {
        pendingPermission = nil
    }

    // MARK: - Active Tool Call Management

    /// Record a tool call that has started (shown as "running" in the UI).
    func registerActiveToolCall(id: String, name: String) {
        activeToolCalls[id] = name
    }

    /// Remove a tool call that has completed.
    func unregisterActiveToolCall(id: String) {
        activeToolCalls.removeValue(forKey: id)
    }

    // MARK: - Processing State

    /// Mark the start of agent processing.
    func beginProcessing() {
        isProcessing = true
        currentError = nil
        streamingText = ""
    }

    /// Mark the end of agent processing.
    func endProcessing() {
        isProcessing = false
        activeToolCalls.removeAll()
    }

    // MARK: - Error Handling

    /// Surface an error to the user.
    func setError(_ error: AppError) {
        currentError = error
        showError = true
        logger.error("App error: \(error.localizedDescription ?? "unknown")")
    }

    /// Clear the current error.
    func clearError() {
        currentError = nil
        showError = false
    }

    // MARK: - Project Management

    /// Set the active project path.
    func setActiveProject(_ path: String) {
        activeProjectPath = path
        if !recentProjects.contains(path) {
            recentProjects.insert(path, at: 0)
            // Keep only the 10 most recent projects
            if recentProjects.count > 10 {
                recentProjects = Array(recentProjects.prefix(10))
            }
        }
        logger.info("Active project set to: \(path)")
    }
}
