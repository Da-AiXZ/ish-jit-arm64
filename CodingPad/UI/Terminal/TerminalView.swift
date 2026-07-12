// TerminalView.swift
// CodingPad
//
// Collapsible terminal panel showing real-time shell output.

import SwiftUI

struct TerminalView: View {
    @State private var outputLines: [TerminalLine] = []
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isExecuting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.caption2)
                Text("Terminal")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    outputLines.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))

            Divider()

            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(outputLines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(.black.opacity(0.85))
                .onChange(of: outputLines.count) { _ in
                    if let last = outputLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 4) {
                Text("$")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("command...", text: $inputText)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
                    .onSubmit { executeCommand() }
                    .disabled(isExecuting)

                if isExecuting {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.85))
        }
    }

    private func executeCommand() {
        let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        // Show the command in output
        outputLines.append(TerminalLine(text: "$ \(command)", isError: false))
        inputText = ""
        isExecuting = true

        Task {
            do {
                let result = try await ISHEngine.shared.execute(command: command, timeout: 30)
                await MainActor.run {
                    if !result.stdout.isEmpty {
                        for line in result.stdout.components(separatedBy: "\n") {
                            outputLines.append(TerminalLine(text: line, isError: false))
                        }
                    }
                    if !result.stderr.isEmpty {
                        for line in result.stderr.components(separatedBy: "\n") {
                            outputLines.append(TerminalLine(text: line, isError: true))
                        }
                    }
                    if result.exitCode != 0 {
                        outputLines.append(TerminalLine(
                            text: "[exit code: \(result.exitCode)]",
                            isError: true
                        ))
                    }
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    outputLines.append(TerminalLine(
                        text: "Error: \(error.localizedDescription)",
                        isError: true
                    ))
                    isExecuting = false
                }
            }
        }
    }
}

// MARK: - Terminal Line

struct TerminalLine: Identifiable {
    let id = UUID().uuidString
    let text: String
    let isError: Bool
}

#Preview {
    TerminalView()
        .frame(height: 200)
}
