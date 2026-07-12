// EditorView.swift
// CodingPad
//
// Code editor with basic syntax highlighting and line numbers.

import SwiftUI

struct EditorView: View {
    @State private var content = ""
    @State private var filePath: String?
    @State private var isModified = false
    @State private var lineCount = 0
    @State private var cursorPosition = (line: 1, column: 1)
    @State private var isEditMode = true

    var body: some View {
        VStack(spacing: 0) {
            // Header: file name and status
            editorHeader

            Divider()

            // Editor content
            if filePath != nil {
                editorContent
            } else {
                emptyState
            }

            Divider()

            // Status bar
            statusBar
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption2)

            if let path = filePath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if isModified {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            } else {
                Text("No file open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if filePath != nil {
                // View/Edit mode toggle
                Button {
                    isEditMode.toggle()
                } label: {
                    Image(systemName: isEditMode ? "eye" : "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .help(isEditMode ? "Switch to highlighted view" : "Switch to edit mode")

                // Close button
                Button {
                    closeFile()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(lineCount, 1), id: \.self) { line in
                        Text("\(line)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(height: 18)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .background(Color(.secondarySystemBackground))

                Divider()

                // Code content — edit mode vs highlighted view mode
                if isEditMode {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollDisabled(true)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .onChange(of: content) { _ in
                            isModified = true
                            lineCount = content.components(separatedBy: "\n").count
                        }
                } else {
                    Text(highlightedContent)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Produces a syntax-highlighted AttributedString based on the current file extension.
    private var highlightedContent: AttributedString {
        let language = detectLanguage()
        return SyntaxHighlighter.highlight(content, language: language)
    }

    /// Detects the language from the file extension.
    private func detectLanguage() -> String {
        guard let path = filePath else { return "plain" }
        let ext = (path as NSString).pathExtension
        return SyntaxHighlighter.languageFromExtension(ext)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Select a file from the file tree\nor ask the Agent to open one")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if filePath != nil {
                Text("Ln \(cursorPosition.line), Col \(cursorPosition.column)")
                    .font(.caption2)

                Spacer()

                Text("UTF-8")
                    .font(.caption2)

                Text("\(lineCount) lines")
                    .font(.caption2)
            } else {
                Spacer()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Actions

    func openFile(at path: String) {
        do {
            content = try String(contentsOfFile: path, encoding: .utf8)
            filePath = path
            isModified = false
            lineCount = content.components(separatedBy: "\n").count
        } catch {
            content = "Error reading file: \(error.localizedDescription)"
            filePath = path
        }
    }

    private func closeFile() {
        content = ""
        filePath = nil
        isModified = false
        lineCount = 0
    }
}

#Preview {
    EditorView()
        .frame(width: 400, height: 600)
}
