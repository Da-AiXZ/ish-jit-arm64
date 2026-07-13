// SettingsView.swift
// CodingPad
//
// Settings page for API keys, model selection, permission mode, etc.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var deepseekKey = ""
    @State private var showApiKey = false
    @State private var selectedModel = "deepseek-chat"
    @State private var permissionMode = PermissionMode.default
    @State private var maxTurns = 50
    @State private var language = "zh-CN"
    @State private var showSaved = false

    private let models = [
        ("deepseek-chat", "DeepSeek Chat (V3, 推荐)"),
        ("deepseek-reasoner", "DeepSeek Reasoner (R1, 深度推理)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                // DeepSeek API Key
                Section("DeepSeek API Key") {
                    HStack {
                        if showApiKey {
                            TextField("sk-...", text: $deepseekKey)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $deepseekKey)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                    }

                    Link("获取 DeepSeek API Key →", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.caption)
                }

                // Model Selection
                Section("模型") {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.0) { id, name in
                            Text(name).tag(id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Permission Mode
                Section("Permission Mode") {
                    Picker("Mode", selection: $permissionMode) {
                        Text("Default — Sensitive ops need confirmation")
                            .tag(PermissionMode.default)
                        Text("Auto — Most ops auto-allowed")
                            .tag(PermissionMode.auto)
                        Text("Plan — All writes need confirmation")
                            .tag(PermissionMode.plan)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Agent Settings
                Section("Agent") {
                    Stepper("Max turns per request: \(maxTurns)", value: $maxTurns, in: 5...200, step: 5)

                    Picker("Language", selection: $language) {
                        Text("中文").tag("zh-CN")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: "0.1.0 (MVP)")
                    LabeledContent("iSH Engine", value: ISHEngine.shared.version)
                    LabeledContent("Device", value: deviceInfo)
                }

                // Danger Zone
                Section {
                    Button("Clear All Sessions", role: .destructive) {
                        // TODO: Clear sessions
                    }
                    Button("Reset Settings", role: .destructive) {
                        // TODO: Reset to defaults
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private var deviceInfo: String {
        let device = UIDevice.current
        return "\(device.name) • iOS \(device.systemVersion)"
    }

    private func loadSettings() {
        let keychain = KeychainService()
        deepseekKey = keychain.get(key: "deepseek_api_key") ?? ""
        selectedModel = appState.config.modelId
        permissionMode = appState.config.permissionMode
        maxTurns = appState.config.maxTurns
        language = appState.config.language
    }

    private func saveSettings() {
        let keychain = KeychainService()
        if !deepseekKey.isEmpty {
            try? keychain.set(key: "deepseek_api_key", value: deepseekKey)
        }

        // Update config
        appState.config = AgentConfig(
            modelId: selectedModel,
            maxTokens: appState.config.maxTokens,
            maxTurns: maxTurns,
            permissionMode: permissionMode,
            autoCompactThreshold: appState.config.autoCompactThreshold,
            language: language,
            outputStyle: appState.config.outputStyle
        )
    }
}

