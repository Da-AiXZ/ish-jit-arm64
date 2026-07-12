// MainLayout.swift
// CodingPad
//
// Three-column adaptive layout for iPad: FileTree / Chat / Editor
// with a collapsible bottom terminal panel.

import SwiftUI

struct MainLayout: View {
    @Environment(AppState.self) private var appState

    @State private var fileTreeWidth: CGFloat = 220
    @State private var editorWidth: CGFloat = 350
    @State private var isTerminalVisible = false
    @State private var terminalHeight: CGFloat = 200
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            toolbar

            Divider()

            // Main three-column area
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Three-column content
                    HStack(spacing: 0) {
                        // Column 1: File Tree
                        FileTreeView()
                            .frame(width: fileTreeWidth)

                        Divider()

                        // Column 2: Chat (flexible, takes remaining space)
                        ChatView()
                            .frame(maxWidth: .infinity)

                        Divider()

                        // Column 3: Editor
                        EditorView()
                            .frame(width: editorWidth)
                    }

                    // Bottom: Collapsible terminal
                    if isTerminalVisible {
                        Divider()
                        TerminalView()
                            .frame(height: terminalHeight)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // App icon and name
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(Color.accentColor)
                Text("CodingPad")
                    .font(.headline)
            }

            Divider()
                .frame(height: 20)

            // Project name
            if let path = appState.activeProjectPath {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No Project")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Model indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(appState.config.modelId.replacingOccurrences(of: "claude-", with: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Token usage
            if let session = appState.currentSession {
                Text("\(session.totalInputTokens + session.totalOutputTokens) tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Toggle terminal
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTerminalVisible.toggle()
                }
            } label: {
                Image(systemName: isTerminalVisible ? "terminal.fill" : "terminal")
                    .font(.body)
            }
            .keyboardShortcut("`", modifiers: .command)

            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    MainLayout()
        .environment(AppState())
}
