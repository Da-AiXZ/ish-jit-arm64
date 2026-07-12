// CodingPadApp.swift
// CodingPad
//
// SwiftUI App entry point.
// Initializes core services and sets up the main UI.

import SwiftUI
import os

// MARK: - App Entry Point

@main
struct CodingPadApp: App {
    @State private var appState = AppState()

    private let logger = Logger(subsystem: "com.codingpad", category: "App")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await initializeServices()
                }
        }
    }

    // MARK: - Service Initialization

    /// Initialize all core services on app launch.
    private func initializeServices() async {
        logger.info("CodingPad launching — initializing services")

        // 1. Set up file system directories
        FileSystemService.shared.ensureAppDirectories()

        // 2. Register default tools
        await ToolRegistry.shared.registerDefaults()

        // 3. Load saved configuration (if any)
        loadSavedConfig()

        // 4. Check for API key
        let hasKey = KeychainService.shared.get(key: KeychainService.apiKeyIdentifier) != nil
        if !hasKey {
            await MainActor.run {
                appState.setError(.missingAPIKey)
            }
            logger.warning("No API key found — user needs to configure one")
        }

        // 5. Start a default session
        await MainActor.run {
            appState.startNewSession()
        }

        logger.info("CodingPad initialization complete")
    }

    /// Load configuration from UserDefaults or file.
    private func loadSavedConfig() {
        // Load recent projects
        if let savedProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") {
            Task { @MainActor in
                appState.recentProjects = savedProjects
            }
        }

        // Load last active project
        if let lastProject = UserDefaults.standard.string(forKey: "activeProjectPath") {
            Task { @MainActor in
                appState.activeProjectPath = lastProject
            }
        }
    }
}

// MARK: - Content View (Placeholder)

/// Placeholder main content view.
/// Will be replaced with the actual split-view layout.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if appState.isProcessing {
                    ProgressView("Processing...")
                        .padding()
                }

                if appState.messages.isEmpty {
                    ContentUnavailableView(
                        "CodingPad",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        description: Text("Start a conversation to begin coding.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.messages) { message in
                                MessageBubbleView(message: message)
                            }

                            if !appState.streamingText.isEmpty {
                                Text(appState.streamingText)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding()
                    }
                }

                Spacer()
            }
            .navigationTitle("CodingPad")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Session", systemImage: "plus") {
                        appState.startNewSession()
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { appState.showError },
                    set: { appState.showError = $0 }
                ),
                presenting: appState.currentError
            ) { _ in
                Button("OK") {
                    appState.clearError()
                }
            } message: { error in
                Text(error.localizedDescription ?? "An unknown error occurred.")
            }
        }
    }
}

// MARK: - Message Bubble View (Minimal)

/// A minimal message bubble for the placeholder UI.
struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(roleLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                contentView(for: block)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: alignment)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        }
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.1)
        case .assistant: return Color(.systemGray6)
        case .system: return Color.orange.opacity(0.1)
        }
    }

    @ViewBuilder
    private func contentView(for block: ContentBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .textSelection(.enabled)

        case .toolUse(let toolBlock):
            Label(toolBlock.name, systemImage: "wrench")
                .font(.caption)
                .padding(6)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

        case .toolResult(let resultBlock):
            Text(resultBlock.content)
                .font(.caption)
                .foregroundStyle(resultBlock.isError ? .red : .secondary)
                .padding(6)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
