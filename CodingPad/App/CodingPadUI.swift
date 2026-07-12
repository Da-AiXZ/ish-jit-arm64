// CodingPadUI.swift
// CodingPad
//
// Provides a UIHostingController wrapping CodingPad's SwiftUI interface.
// Called from iSH's SceneDelegate (Obj-C) to set the root view controller.
//
// This is the bridge between iSH's UIKit lifecycle and CodingPad's SwiftUI UI.

import SwiftUI
import UIKit

/// Obj-C visible class that creates the CodingPad SwiftUI root view controller.
///
/// Usage from Obj-C:
///   UIViewController *vc = [CodingPadUI createRootViewController];
///   self.window.rootViewController = vc;
@MainActor
@objc
public final class CodingPadUI: NSObject {

    /// Shared AppState instance (lives for the app lifetime).
    private static var appStateStorage: AppState?
    private static var appState: AppState {
        if let existing = appStateStorage { return existing }
        let new = AppState()
        appStateStorage = new
        return new
    }

    /// Creates the root UIHostingController with the CodingPad MainLayout.
    ///
    /// - Returns: A UIHostingController ready to be set as window.rootViewController.
    @objc
    public static func createRootViewController() -> UIViewController {
        let mainView = MainLayout()
            .environmentObject(appState)

        let hostingController = UIHostingController(rootView: mainView)
        hostingController.view.backgroundColor = UIColor.systemBackground

        // Initialize services in the background
        Task {
            await initializeServices()
        }

        return hostingController
    }

    /// Notify CodingPad that iSH engine has finished booting.
    /// Called from AppDelegate after the kernel is ready.
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

        // 3. Start a default session
        await MainActor.run {
            appState.startNewSession()
        }
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
