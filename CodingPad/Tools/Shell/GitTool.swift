// GitTool.swift
// CodingPad
//
// High-level git operations tool that wraps common git commands.
// Uses BashTool (iSH engine) under the hood for execution.

import Foundation

struct GitTool: AgentTool {

    // MARK: - AgentTool Conformance

    let name = "GitTool"

    let description = """
        Execute git operations in the current project. \
        Provides structured access to common git commands with appropriate permissions.
        """

    let isReadOnly = false
    let isConcurrencySafe = false

    var inputSchema: ToolInputSchema {
        ToolInputSchema(
            type: "object",
            properties: [
                "operation": .init(
                    type: "string",
                    description: "The git operation to perform.",
                    enumValues: [
                        "status", "diff", "log", "branch", "show",
                        "add", "commit", "push", "pull", "clone",
                        "checkout", "merge", "stash", "remote", "init"
                    ]
                ),
                "args": .init(
                    type: "string",
                    description: "Additional arguments for the git command.",
                    enumValues: nil
                ),
                "cwd": .init(
                    type: "string",
                    description: "Working directory. Default: active project root.",
                    enumValues: nil
                )
            ],
            required: ["operation"]
        )
    }

    var usagePrompt: String {
        """
        Execute git operations in the current project.

        Supported operations:
        - status: Show working tree status
        - diff: Show changes (supports args like --staged, HEAD~1)
        - log: Show commit history (default: last 20, oneline format)
        - branch: List or manage branches (args: -a, -d <name>, <new-branch>)
        - show: Show commit details (args: <commit-hash>)
        - add: Stage files (args: file paths or . for all)
        - commit: Create a commit (args: -m "message")
        - push: Push to remote (args: origin <branch>, --force)
        - pull: Pull from remote (args: origin <branch>)
        - clone: Clone a repository (args: <url> [<dir>], recommend --depth 1)
        - checkout: Switch branches or restore files (args: <branch> or -- <file>)
        - merge: Merge branches (args: <branch>)
        - stash: Stash changes (args: push, pop, list, drop)
        - remote: Manage remotes (args: -v, add <name> <url>)
        - init: Initialize a new git repository

        Read operations (status, diff, log, branch, show) are auto-allowed.
        Write operations (add, commit, push, etc.) require confirmation.
        Clone with --depth 1 is recommended for performance in the iSH environment.
        """
    }

    // MARK: - Permission Check

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let operation = input.string(for: "operation") else {
            return .deny(reason: "No git operation specified.")
        }

        let readOps: Set<String> = ["status", "diff", "log", "branch", "show", "remote", "stash"]
        if readOps.contains(operation) {
            // Read operations with read-only subcommands.
            let args = input.string(for: "args") ?? ""
            if operation == "stash" && !["list", "show"].contains(where: { args.hasPrefix($0) }) {
                return .ask(reason: "git stash \(args) modifies state.")
            }
            if operation == "branch" && !args.isEmpty && !args.hasPrefix("-a") && !args.hasPrefix("-r") {
                return .ask(reason: "git branch \(args) may modify branches.")
            }
            if operation == "remote" && !args.isEmpty && !args.hasPrefix("-v") {
                return .ask(reason: "git remote \(args) may modify remotes.")
            }
            return .allow
        }

        // Write operations — ask.
        return .ask(reason: "git \(operation) modifies the repository.")
    }

    // MARK: - Execution

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let operation = input.string(for: "operation") else {
            return .error("Missing required parameter: operation")
        }

        let args = input.string(for: "args") ?? ""
        let cwd = input.string(for: "cwd")

        // Build the full git command.
        let command = buildCommand(operation: operation, args: args)

        // Execute through ISHEngine.
        let engine = ISHEngine.shared

        do {
            let result = try await engine.execute(
                command: command,
                cwd: cwd,
                timeout: timeoutForOperation(operation)
            )

            if result.timedOut {
                return .error("Git operation timed out: git \(operation) \(args)")
            }

            var output = result.stdout
            if !result.stderr.isEmpty {
                // Git often writes progress to stderr (not necessarily errors).
                if result.exitCode == 0 {
                    output += "\n\(result.stderr)"
                } else {
                    output += "\nERROR:\n\(result.stderr)"
                }
            }

            return ToolResult(
                content: output.isEmpty ? "(no output)" : output,
                isError: result.exitCode != 0,
                metadata: [
                    "operation": operation,
                    "exit_code": "\(result.exitCode)",
                    "elapsed": String(format: "%.2fs", result.elapsedSeconds)
                ]
            )
        } catch {
            return .error("Git execution error: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Building

    private func buildCommand(operation: String, args: String) -> String {
        switch operation {
        case "log":
            if args.isEmpty {
                return "git log --oneline -20"
            }
            return "git log \(args)"

        case "diff":
            if args.isEmpty {
                return "git diff"
            }
            return "git diff \(args)"

        case "clone":
            // Always recommend --depth 1 for performance in iSH.
            if !args.contains("--depth") {
                return "git clone --depth 1 \(args)"
            }
            return "git clone \(args)"

        case "init":
            return "git init \(args)"

        default:
            if args.isEmpty {
                return "git \(operation)"
            }
            return "git \(operation) \(args)"
        }
    }

    /// Returns appropriate timeout for different git operations.
    private func timeoutForOperation(_ operation: String) -> Double {
        switch operation {
        case "clone": return 300.0  // 5 min for cloning
        case "push", "pull": return 120.0  // 2 min for network ops
        case "commit", "merge": return 60.0  // 1 min for complex local ops
        default: return 30.0  // 30s for everything else
        }
    }
}
