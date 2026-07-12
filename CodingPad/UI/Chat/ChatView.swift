// ChatView.swift
// CodingPad
//
// Main conversation view showing messages, tool calls, and the input bar.
// Consumes AgentLoop events to drive real-time UI updates.

import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var isComposing = false
    @FocusState private var isInputFocused: Bool

    /// Continuation used to deliver the user's permission decision
    /// back to the AgentLoop's `permissionResolver` callback.
    @State private var permissionContinuation: CheckedContinuation<Bool, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming text (assistant is typing)
                        if !appState.streamingText.isEmpty {
                            StreamingBubble(text: appState.streamingText)
                                .id("streaming")
                        }

                        // Active tool calls
                        if !appState.activeToolCalls.isEmpty {
                            ActiveToolCallsView(toolCalls: appState.activeToolCalls)
                                .id("active-tools")
                        }

                        // Processing indicator
                        if appState.isProcessing && appState.streamingText.isEmpty && appState.activeToolCalls.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: appState.messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(appState.messages.last?.id ?? "streaming", anchor: .bottom)
                    }
                }
                .onChange(of: appState.streamingText) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            Divider()

            // Todo list (above input bar, collapsible)
            if !appState.todos.isEmpty {
                TodoListView(todos: appState.todos)
            }

            Divider()

            // Input bar
            InputBar(
                text: $inputText,
                isProcessing: appState.isProcessing,
                isFocused: $isInputFocused,
                onSend: sendMessage
            )
        }
        .background(Color(.systemBackground))
        .permissionAlert(
            request: appState.pendingPermission,
            onAllow: { resolvePermission(granted: true) },
            onAlwaysAllow: { resolvePermissionAlways() },
            onDeny: { resolvePermission(granted: false) }
        )
    }

    // MARK: - Send Message (AgentLoop Integration)

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // Add user message to state
        let userMessage = Message(role: .user, text: text)
        appState.appendMessage(userMessage)
        appState.beginProcessing()

        guard let agentLoop = appState.agentLoop else {
            // Fallback: no agent loop configured
            let response = Message(
                role: .assistant,
                text: "Agent loop not configured. Please set up an LLM provider."
            )
            appState.appendMessage(response)
            appState.endProcessing()
            return
        }

        Task { @MainActor in
            await consumeAgentStream(
                agentLoop: agentLoop,
                userText: text
            )
        }
    }

    /// Consume the AgentLoop's event stream and apply each event to AppState.
    @MainActor
    private func consumeAgentStream(
        agentLoop: AgentLoop,
        userText: String
    ) async {
        // Build the permission resolver that bridges to the UI
        let permissionResolver: PermissionResolver = { [weak appState] toolName, input, reason in
            guard let appState else { return false }

            // Present the permission alert and wait for the user's response
            return await withCheckedContinuation { continuation in
                Task { @MainActor in
                    self.permissionContinuation = continuation
                    appState.requestPermission(PermissionRequest(
                        id: UUID().uuidString,
                        toolName: toolName,
                        input: input,
                        reason: reason
                    ))
                }
            }
        }

        // Get the registered tools
        let tools = await ToolRegistry.shared.allTools()

        // Start the agent loop
        var messages = appState.messages
        let stream = agentLoop.run(
            userMessage: userText,
            messages: &messages,
            tools: tools,
            config: appState.config,
            permissionResolver: permissionResolver
        )

        do {
            for try await event in stream {
                handleAgentEvent(event)
            }
        } catch {
            appState.setError(.agentLoopFailed(error))
        }

        appState.endProcessing()
    }

    /// Apply a single AgentEvent to the UI state.
    @MainActor
    private func handleAgentEvent(_ event: AgentEvent) {
        switch event {
        case .textDelta(let delta):
            appState.appendStreamingText(delta)

        case .toolCallStart(let name, let id):
            appState.registerActiveToolCall(id: id, name: name)

        case .toolCallInput:
            // Incremental JSON — no UI update needed
            break

        case .toolCallComplete(let name, _):
            // Remove from active; the tool result appears as a message from the loop
            let matchingId = appState.activeToolCalls.first { $0.value == name }?.key
            if let id = matchingId {
                appState.unregisterActiveToolCall(id: id)
            }

        case .permissionRequired:
            // Handled by the permissionResolver callback (sets pendingPermission)
            break

        case .turnComplete(let usage):
            appState.updateSessionAfterTurn(usage: usage)

        case .error(let error):
            appState.setError(.agentLoopFailed(error))

        case .done:
            appState.finalizeStreamingText()
        }
    }

    // MARK: - Permission Resolution

    /// Resume the permission continuation with the user's decision.
    private func resolvePermission(granted: Bool) {
        appState.clearPendingPermission()
        permissionContinuation?.resume(returning: granted)
        permissionContinuation = nil
    }

    /// "Always allow" adds a temporary allow and resumes with `true`.
    private func resolvePermissionAlways() {
        if let request = appState.pendingPermission {
            Task {
                await appState.agentLoop?.permissionEngine.addTemporaryAllow(
                    tool: request.toolName,
                    pattern: "*"
                )
            }
        }
        resolvePermission(granted: true)
    }
}

// MARK: - Active Tool Calls View

/// Shows tool calls currently being executed.
struct ActiveToolCallsView: View {
    let toolCalls: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(toolCalls.keys.sorted()), id: \.self) { id in
                if let name = toolCalls[id] {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("running...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Todo List View

/// Collapsible todo list shown above the input bar.
struct TodoListView: View {
    let todos: [TodoItem]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (tap to toggle)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.caption)
                    Text("Tasks (\(completedCount)/\(todos.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)

            // Items
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(todos) { todo in
                        TodoRowView(todo: todo)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .background(Color(.secondarySystemBackground).opacity(0.5))
            }
        }
    }

    private var completedCount: Int {
        todos.filter { $0.status == .completed }.count
    }
}

// MARK: - Todo Row View

struct TodoRowView: View {
    let todo: TodoItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption2)
                .foregroundStyle(statusColor)
            Text(todo.content)
                .font(.caption)
                .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                .strikethrough(todo.status == .completed)
            if todo.status == .inProgress, let activeForm = todo.activeForm {
                Text("— \(activeForm)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch todo.status {
        case .pending:    return "circle"
        case .inProgress: return "circle.dotted.circle"
        case .completed:  return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch todo.status {
        case .pending:    return .secondary
        case .inProgress: return .blue
        case .completed:  return .green
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Role label
            HStack(spacing: 4) {
                Image(systemName: message.role == .user ? "person.fill" : "cpu")
                    .font(.caption2)
                Text(message.role == .user ? "You" : "Agent")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(message.role == .user ? .blue : .green)

            // Content blocks
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                contentBlockView(block)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contentBlockView(_ block: ContentBlock) -> some View {
        switch block {
        case .text(let text):
            MarkdownView(text: text)

        case .toolUse(let toolUse):
            ToolCallCard(
                toolName: toolUse.name,
                toolId: toolUse.id,
                input: toolUse.input,
                result: nil
            )

        case .toolResult(let result):
            ToolResultCard(
                toolUseId: result.toolUseId,
                content: result.content,
                isError: result.isError
            )
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                Text("Agent")
                    .font(.caption)
                    .fontWeight(.medium)
                ProgressView()
                    .controlSize(.mini)
            }
            .foregroundStyle(.green)

            MarkdownView(text: text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Tool Call Card

struct ToolCallCard: View {
    let toolName: String
    let toolId: String
    let input: [String: JSONValue]
    let result: ToolResult?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                    Text(toolName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(input.keys.sorted()), id: \.self) { key in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(key):")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            Text(jsonValueDescription(input[key]))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
    }

    private func jsonValueDescription(_ value: JSONValue?) -> String {
        guard let value = value else { return "null" }
        switch value {
        case .string(let s): return s.count > 100 ? String(s.prefix(100)) + "..." : s
        case .number(let n): return String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let a): return "[\(a.count) items]"
        case .object(let o): return "{\(o.count) keys}"
        }
    }
}

// MARK: - Tool Result Card

struct ToolResultCard: View {
    let toolUseId: String
    let content: String
    let isError: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                        .font(.caption)
                    Text(isError ? "Error" : "Result")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(\(content.count) chars)")
                        .font(.caption2)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(isError ? .red : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((isError ? Color.red : Color.green).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(content)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var text: String
    let isProcessing: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attach button (future: file attachment)
            Button {
                // TODO: File picker
            } label: {
                Image(systemName: "paperclip")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .disabled(isProcessing)

            // Text editor
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused(isFocused)
                .onSubmit {
                    // Cmd+Enter to send (regular Enter adds newline)
                }
                .disabled(isProcessing)

            // Send button
            Button(action: onSend) {
                Image(systemName: isProcessing ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : .secondary)
            }
            .disabled(!canSend && !isProcessing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }
}

#Preview {
    ChatView()
        .environment(AppState())
}
