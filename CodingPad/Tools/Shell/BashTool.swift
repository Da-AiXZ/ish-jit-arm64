// BashTool.swift
// CodingPad
//
// Executes shell commands inside the embedded iSH Alpine Linux environment.
// This is the primary way the Agent interacts with the operating system.

import Foundation

struct BashTool: AgentTool {

    // MARK: - AgentTool Conformance

    let name = "BashTool"

    let description = """
        Execute a shell command in the embedded Alpine Linux environment. \
        Commands run via /bin/sh -c inside an iSH x86-to-ARM64 JIT emulator. \
        Available tools include git, grep, find, curl, and any package installable via apk.
        """

    let isReadOnly = false
    let isConcurrencySafe = false // Only one command at a time

    var inputSchema: ToolInputSchema {
        ToolInputSchema(
            type: "object",
            properties: [
                "command": .init(
                    type: "string",
                    description: "The shell command to execute. Passed to /bin/sh -c.",
                    enumValues: nil
                ),
                "description": .init(
                    type: "string",
                    description: "Clear, concise description of what this command does.",
                    enumValues: nil
                ),
                "timeout": .init(
                    type: "number",
                    description: "Maximum execution time in seconds. Default: 30. Max: 600.",
                    enumValues: nil
                ),
                "cwd": .init(
                    type: "string",
                    description: "Working directory for the command. Default: project root.",
                    enumValues: nil
                )
            ],
            required: ["command"]
        )
    }

    var usagePrompt: String {
        """
        Executes a bash command in the embedded Alpine Linux (iSH) environment.

        - The environment is a real Linux shell (Alpine Linux with ash/bash).
        - Commands are executed via /bin/sh -c.
        - Available by default: coreutils, findutils, grep, sed, git, curl, wget, make, ssh.
        - Install additional packages with: apk add <package>
        - Working directory defaults to the active project root.
        - Default timeout is 30 seconds, max 600 seconds.
        - Prefer dedicated file tools (FileRead, FileWrite, GrepTool, GlobTool) over shell \
        commands for file operations — they are faster because they use Swift native I/O \
        instead of the x86 emulator.
        - For git operations, use this tool directly (e.g., `git status`, `git diff`).
        - IMPORTANT: Avoid interactive commands (vim, nano, less). Use non-interactive \
        alternatives (cat, head, tail, sed).

        Examples:
        - List files: command="ls -la src/"
        - Git status: command="git status"
        - Search code: command="grep -rn 'TODO' src/" (but prefer GrepTool)
        - Install package: command="apk add python3"
        - Run tests: command="npm test"
        """
    }

    // MARK: - Permission Check

    /// Classifies shell commands into safety tiers.
    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let command = input.string(for: "command") else {
            return .deny(reason: "No command provided.")
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Dangerous commands — always deny.
        for pattern in Self.dangerousPatterns {
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .deny(reason: "Dangerous command blocked: matches '\(pattern)'")
            }
        }

        // Read-only commands — auto-allow.
        let firstToken = trimmed.components(separatedBy: .whitespaces).first ?? ""
        if Self.readOnlyCommands.contains(firstToken) {
            return .allow
        }

        // Git read commands — auto-allow.
        if firstToken == "git" {
            let gitSubcommand = trimmed.components(separatedBy: .whitespaces).dropFirst().first ?? ""
            if Self.gitReadSubcommands.contains(String(gitSubcommand)) {
                return .allow
            }
        }

        // Everything else — ask the user.
        return .ask(reason: "Shell command requires confirmation: \(trimmed)")
    }

    // MARK: - Execution

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let command = input.string(for: "command") else {
            return .error("Missing required parameter: command")
        }

        let timeout = input.int(for: "timeout").map { Double($0) } ?? 30.0
        let clampedTimeout = min(max(timeout, 1.0), 600.0)
        let cwd = input.string(for: "cwd")

        let engine = ISHEngine.shared

        do {
            let result = try await engine.execute(
                command: command,
                cwd: cwd,
                timeout: clampedTimeout
            )

            if result.timedOut {
                return .error("Command timed out after \(Int(clampedTimeout))s: \(command)")
            }

            // Format output similar to Claude Code's BashTool.
            var output = result.stdout
            if !result.stderr.isEmpty {
                output += "\nSTDERR:\n\(result.stderr)"
            }

            if result.exitCode != 0 {
                output = "Exit code: \(result.exitCode)\n\(output)"
            }

            // Truncate very long output.
            let maxLength = 100_000
            if output.count > maxLength {
                let truncated = String(output.prefix(maxLength))
                output = truncated + "\n\n... (output truncated at \(maxLength) characters)"
            }

            return ToolResult(
                content: output.isEmpty ? "(no output)" : output,
                isError: result.exitCode != 0,
                metadata: [
                    "exit_code": "\(result.exitCode)",
                    "elapsed": String(format: "%.2fs", result.elapsedSeconds)
                ]
            )
        } catch let error as ISHEngineError {
            return .error(error.localizedDescription)
        } catch {
            return .error("Shell execution error: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Classification

    private static let readOnlyCommands: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "file", "which", "whoami",
        "pwd", "echo", "env", "printenv", "date", "uname", "hostname",
        "find", "grep", "egrep", "fgrep", "sort", "uniq", "diff",
        "du", "df", "free", "uptime", "id", "groups", "test", "true", "false"
    ]

    private static let gitReadSubcommands: Set<String> = [
        "status", "log", "diff", "show", "branch", "tag", "remote",
        "stash", "describe", "rev-parse", "shortlog", "blame", "ls-files",
        "ls-tree", "cat-file", "config"
    ]

    private static let dangerousPatterns: [String] = [
        #"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/"#,        // rm -rf /
        #"rm\s+-[a-zA-Z]*f[a-zA-Z]*\s+\*"#,           // rm -rf *
        #"\bdd\b.*\bof=/"#,                             // dd of=/dev/...
        #"\bmkfs\b"#,                                    // mkfs
        #"\bfdisk\b"#,                                   // fdisk
        #":\(\)\{.*\|.*&.*\};"#,                        // fork bomb
        #"\bchmod\s+(-R\s+)?777\s+/"#,                  // chmod 777 /
        #"\bwget\b.*-O\s*-\s*\|"#,                      // wget -O- | sh
        #"\bcurl\b.*\|\s*(ba)?sh"#,                     // curl ... | sh
        #">\s*/dev/[sh]d"#,                              // redirect to disk
        #"\bshutdown\b"#,                                // shutdown
        #"\breboot\b"#,                                  // reboot
    ]
}
