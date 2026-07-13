// CodingPadUI.swift
// CodingPad
//
// Provides a UIHostingController wrapping CodingPad's SwiftUI interface.
// Called from iSH's SceneDelegate (Obj-C) to set the root view controller.

import SwiftUI
import UIKit

@MainActor
@objc
public final class CodingPadUI: NSObject {

    private static var appStateStorage: AppState?
    private static var appState: AppState {
        if let existing = appStateStorage { return existing }
        let new = AppState()
        appStateStorage = new
        return new
    }

    @objc
    public static func createRootViewController() -> UIViewController {
        let mainView = MainLayout()
            .environmentObject(appState)

        let hostingController = UIHostingController(rootView: mainView)
        hostingController.view.backgroundColor = UIColor.systemBackground

        Task {
            await initializeServices()
        }

        return hostingController
    }

    @objc
    public static func notifyEngineReady() {
        Task {
            await ISHSwiftBridge.shared.markReady()
        }
    }

    // MARK: - Service Initialization

    private static func initializeServices() async {
        // 1. Set up file system directories
        FileSystemService.shared.ensureAppDirectories()

        // 2. Register default tools
        await registerTools()

        // 3. Create LLM provider (DeepSeek as default)
        let provider = createLLMProvider()

        // 4. Create and configure AgentLoop
        let toolRouter = ToolRouter()
        let registeredTools = await ToolRegistry.shared.allTools()
        for tool in registeredTools {
            await toolRouter.register(tool)
        }

        let agentLoop = AgentLoop(
            llmProvider: provider,
            toolRouter: toolRouter,
            permissionEngine: PermissionEngine()
        )

        // 5. Attach to AppState so ChatView can use it
        appState.agentLoop = agentLoop

        // 6. Start a default session
        appState.startNewSession()
    }

    /// Create the LLM provider based on saved settings.
    private static func createLLMProvider() -> any LLMProvider {
        let keychain = KeychainService()

        // Check for DeepSeek key first (user's primary)
        if let deepseekKey = keychain.get(key: "deepseek_api_key"), !deepseekKey.isEmpty {
            return OpenAICompatProvider(
                preset: .deepseek,
                modelId: "deepseek-chat",
                apiKeyProvider: { deepseekKey }
            )
        }

        // Check for Anthropic key
        if let anthropicKey = keychain.get(key: "anthropic_api_key"), !anthropicKey.isEmpty {
            return AnthropicProvider(apiKeyProvider: { anthropicKey })
        }

        // Default to DeepSeek with empty key (will prompt user in Settings)
        return OpenAICompatProvider(
            preset: .deepseek,
            modelId: "deepseek-chat",
            apiKeyProvider: {
                KeychainService().get(key: "deepseek_api_key")
            }
        )
    }

    private static func registerTools() async {
        let registry = ToolRegistry.shared
        await registry.register(FileReadTool())
        await registry.register(FileWriteTool())
        await registry.register(FileEditTool())
        await registry.register(GlobTool())
        await registry.register(GrepTool())
        await registry.register(BashTool())
        await registry.register(GitTool())
        await registry.register(PackageTool())
        await registry.register(WebFetchTool())
        await registry.register(TodoWriteTool())
        await registry.register(CompactTool())
        await registry.register(HelpTool())
    }
}
