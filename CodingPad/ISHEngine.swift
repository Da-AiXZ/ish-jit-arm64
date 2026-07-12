// ISHEngine.swift
// CodingPad
//
// Swift wrapper for the embedded iSH engine.
//
// In the iSH-based build (方案A), this delegates to ISHSwiftBridge
// which calls the real ISHShellExecutor. The C stub (ISHBridge.c)
// is no longer used — the real iSH C core is linked via the Xcode project.

import Foundation

// MARK: - ISHEngineError

enum ISHEngineError: LocalizedError, Sendable {
    case notInitialized
    case initializationFailed(reason: String)
    case commandFailed(exitCode: Int, stderr: String)
    case timeout(command: String)
    case mountFailed(path: String)
    case alreadyRunning(command: String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "iSH engine is not initialized. Waiting for boot."
        case .initializationFailed(let reason):
            return "iSH engine initialization failed: \(reason)"
        case .commandFailed(let exitCode, let stderr):
            return "Command failed (exit \(exitCode)): \(stderr)"
        case .timeout(let command):
            return "Command timed out: \(command)"
        case .mountFailed(let path):
            return "Failed to mount iOS path: \(path)"
        case .alreadyRunning(let command):
            return "Another command is already running: \(command)"
        }
    }
}

// MARK: - ExecResult

struct ExecResult: Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let elapsedSeconds: Double

    var isSuccess: Bool { exitCode == 0 && !timedOut }

    var combinedOutput: String {
        var parts: [String] = []
        if !stdout.isEmpty { parts.append(stdout) }
        if !stderr.isEmpty { parts.append("STDERR:\n\(stderr)") }
        if parts.isEmpty { return "(no output)" }
        return parts.joined(separator: "\n")
    }
}

// MARK: - ISHEngine

/// Main entry point for shell execution used by BashTool, GitTool, PackageTool.
///
/// Delegates all calls to ISHSwiftBridge.shared which calls the real
/// ISHShellExecutor (Obj-C) → iSH C core (Asbestos interpreter).
actor ISHEngine {

    static let shared = ISHEngine()

    var isInitialized: Bool {
        get async { await ISHSwiftBridge.shared.isReady }
    }

    /// Execute a shell command through the real iSH engine.
    func execute(
        command: String,
        cwd: String? = nil,
        timeout: Double = 30.0
    ) async throws -> ExecResult {
        try await ISHSwiftBridge.shared.execute(
            command: command,
            cwd: cwd,
            timeout: timeout
        )
    }

    /// Cancel the currently running command.
    func cancel() async {
        await ISHSwiftBridge.shared.cancel()
    }

    /// Get the engine version string.
    nonisolated var version: String {
        "ish-jit-arm64 (Asbestos) — real engine"
    }
}
