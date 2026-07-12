// PermissionEngine.swift
// CodingPad
//
// ABAC (Attribute-Based Access Control) permission engine.
// Three-valued decision model: allow, ask, deny.
// Five resource scopes: tool, fs, net, secret, shell.

import Foundation
import os

// MARK: - Shell Command Classification

/// Classification of shell commands by risk level.
enum ShellCommandCategory: Sendable {
    case read
    case write
    case dangerous
    case unknown
}

// MARK: - Shell Classifier

/// Classifies shell commands into risk categories.
struct ShellClassifier: Sendable {

    /// Read-only commands that do not modify system state.
    static let readCommands: Set<String> = [
        "ls", "cat", "grep", "find", "head", "tail",
        "wc", "file", "which", "pwd", "echo", "env",
        "git status", "git log", "git diff", "git branch",
    ]

    /// Commands that modify state but are generally safe.
    static let writeCommands: Set<String> = [
        "mkdir", "cp", "mv", "touch", "chmod",
        "git add", "git commit", "git push",
        "npm install", "pip install", "apk add",
    ]

    /// Commands that can cause irreversible damage.
    static let dangerousCommands: Set<String> = [
        "rm -rf", "dd", "mkfs", "fdisk", ":(){:|:&};:",
    ]

    /// Classify a full command string.
    ///
    /// - Parameter command: The full command string to classify.
    /// - Returns: The risk category for the command.
    static func classify(_ command: String) -> ShellCommandCategory {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check dangerous commands first (highest priority)
        for dangerous in dangerousCommands {
            if trimmed.hasPrefix(dangerous) {
                return .dangerous
            }
        }

        // Check read commands (match base command or multi-word command)
        if matchesCommandSet(trimmed, commands: readCommands) {
            return .read
        }

        // Check write commands
        if matchesCommandSet(trimmed, commands: writeCommands) {
            return .write
        }

        return .unknown
    }

    /// Checks if a command matches any entry in a command set.
    /// Supports both single-word ("ls") and multi-word ("git status") commands.
    private static func matchesCommandSet(_ command: String, commands: Set<String>) -> Bool {
        for cmd in commands {
            if command == cmd || command.hasPrefix(cmd + " ") || command.hasPrefix(cmd + "\t") {
                return true
            }
        }
        return false
    }
}

// MARK: - Temporary Allow Entry

/// A temporary permission grant for a specific tool + pattern combination.
struct TemporaryAllow: Sendable, Equatable {
    let tool: String
    let pattern: String
    let createdAt: Date

    init(tool: String, pattern: String, createdAt: Date = Date()) {
        self.tool = tool
        self.pattern = pattern
        self.createdAt = createdAt
    }
}

// MARK: - Permission Engine

/// ABAC-based permission engine that evaluates tool execution requests.
///
/// Thread-safe via `actor` isolation. Uses:
/// - Policy rules from `PolicyConfig`
/// - Temporary allows for session-specific overrides
/// - Shell command classification for shell-scope decisions
/// - Permission mode for overall strictness control
actor PermissionEngine {
    private let policyConfig: PolicyConfig
    private var temporaryAllows: [TemporaryAllow] = []
    private let logger = Logger(subsystem: "com.codingpad", category: "PermissionEngine")

    init(policyConfig: PolicyConfig = .defaultPolicy) {
        self.policyConfig = policyConfig
    }

    // MARK: - Core Evaluation

    /// Evaluate whether a tool call should be allowed.
    ///
    /// The evaluation flow:
    /// 1. Check temporary allows (session overrides).
    /// 2. Build the resource string for the scope.
    /// 3. Resolve against policy rules.
    /// 4. Apply permission mode adjustments.
    /// 5. Return the final decision.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool being invoked.
    ///   - input: The tool's input parameters.
    ///   - scope: The permission scope to evaluate.
    ///   - mode: The current permission mode.
    /// - Returns: A three-valued permission decision.
    func evaluate(
        tool: String,
        input: ToolInput,
        scope: PermissionScope,
        mode: PermissionMode = .default
    ) -> PermissionDecision {
        // 1. Check temporary allows
        if matchesTemporaryAllow(tool: tool, input: input) {
            logger.debug("Tool '\(tool)' matched temporary allow.")
            return .allow
        }

        // 2. Build resource string
        let resource = buildResourceString(tool: tool, input: input, scope: scope)

        // 3. Resolve against policy
        let rules = policyConfig.rules(for: scope)
        let matchResult = RuleResolver.resolve(resource: resource, rules: rules)

        // 4. Determine base decision
        let baseDecision: PermissionDecision
        if let match = matchResult {
            baseDecision = decisionFromEffect(match.effect, reason: match.reason)
        } else {
            // No rule matched — scope default
            baseDecision = defaultDecision(for: scope)
        }

        // 5. Apply permission mode adjustments
        let finalDecision = applyMode(baseDecision, mode: mode, scope: scope)

        logger.info("Permission for '\(tool)' [\(scope.rawValue)] resource='\(resource)' -> \(String(describing: finalDecision))")

        return finalDecision
    }

    /// Evaluate a shell command specifically.
    ///
    /// Classifies the command and builds the resource string accordingly.
    ///
    /// - Parameters:
    ///   - command: The shell command string.
    ///   - mode: The current permission mode.
    /// - Returns: A three-valued permission decision.
    func evaluateShellCommand(
        command: String,
        mode: PermissionMode = .default
    ) -> PermissionDecision {
        let category = ShellClassifier.classify(command)
        let baseCommand = extractBaseCommand(command)

        switch category {
        case .dangerous:
            logger.warning("Dangerous command blocked: \(command)")
            return .deny(reason: "Command '\(baseCommand)' is classified as dangerous and cannot be executed.")

        case .read:
            // Read commands are typically allowed, but still check policy
            let resource = "shell:read:\(baseCommand)"
            return evaluateShellResource(resource, mode: mode)

        case .write:
            let resource = "shell:write:\(baseCommand)"
            return evaluateShellResource(resource, mode: mode)

        case .unknown:
            return .ask(reason: "Unknown command '\(baseCommand)' — requires confirmation.")
        }
    }

    // MARK: - Temporary Allows

    /// Add a temporary allow for a tool + pattern combination.
    /// These override policy rules within the current session.
    func addTemporaryAllow(tool: String, pattern: String) {
        let entry = TemporaryAllow(tool: tool, pattern: pattern)
        temporaryAllows.append(entry)
        logger.info("Added temporary allow: tool='\(tool)' pattern='\(pattern)'")
    }

    /// Remove all temporary allows for a given tool.
    func removeTemporaryAllows(for tool: String) {
        temporaryAllows = temporaryAllows.filter { $0.tool != tool }
    }

    /// Clear all temporary allows.
    func clearTemporaryAllows() {
        temporaryAllows.removeAll()
    }

    /// Returns the current count of temporary allows.
    var temporaryAllowCount: Int {
        temporaryAllows.count
    }

    // MARK: - Private Helpers

    /// Check if any temporary allow matches the tool call.
    private func matchesTemporaryAllow(tool: String, input: ToolInput) -> Bool {
        for entry in temporaryAllows {
            if entry.tool == tool {
                // A wildcard pattern matches everything for this tool
                if entry.pattern == "*" {
                    return true
                }
                // Check if any input parameter value matches the pattern
                if matchesInputPattern(input: input, pattern: entry.pattern) {
                    return true
                }
            }
        }
        return false
    }

    /// Check if any input parameter value matches a glob pattern.
    private func matchesInputPattern(input: ToolInput, pattern: String) -> Bool {
        for (_, value) in input.parameters {
            if case .string(let strValue) = value {
                if RuleResolver.globMatch(pattern: pattern, text: strValue) {
                    return true
                }
            }
        }
        return false
    }

    /// Build the resource string used for policy matching.
    private func buildResourceString(
        tool: String,
        input: ToolInput,
        scope: PermissionScope
    ) -> String {
        switch scope {
        case .tool:
            return tool

        case .fs:
            let path = input.string(for: "file_path")
                ?? input.string(for: "path")
                ?? "*"
            let operation = determineFileOperation(tool: tool)
            return "\(operation):\(path)"

        case .net:
            let url = input.string(for: "url") ?? "*"
            let method = input.string(for: "method")?.uppercased() ?? "GET"
            return "\(method):\(url)"

        case .secret:
            let key = input.string(for: "key")
                ?? input.string(for: "name")
                ?? "*"
            return key

        case .shell:
            let command = input.string(for: "command") ?? ""
            let category = ShellClassifier.classify(command)
            let categoryName = shellCategoryName(category)
            let baseCommand = extractBaseCommand(command)
            return "shell:\(categoryName):\(baseCommand)"
        }
    }

    /// Determine file operation type from tool name.
    private func determineFileOperation(tool: String) -> String {
        let readTools: Set<String> = ["file_read", "glob", "grep"]
        let writeTools: Set<String> = ["file_write", "file_edit"]

        if readTools.contains(tool) {
            return "read"
        } else if writeTools.contains(tool) {
            return "write"
        } else if tool.contains("delete") || tool.contains("remove") {
            return "delete"
        }
        return "read"
    }

    /// Convert a ShellCommandCategory to a name string for resource building.
    private func shellCategoryName(_ category: ShellCommandCategory) -> String {
        switch category {
        case .read:      return "read"
        case .write:     return "write"
        case .dangerous: return "dangerous"
        case .unknown:   return "unknown"
        }
    }

    /// Extract the base command (first word or first two words for git/npm/pip).
    private func extractBaseCommand(_ fullCommand: String) -> String {
        let parts = fullCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 2)
            .map(String.init)

        guard let first = parts.first else { return "" }

        // Multi-word commands: git, npm, pip, apk
        let multiWordPrefixes: Set<String> = ["git", "npm", "pip", "apk"]
        if multiWordPrefixes.contains(first), parts.count >= 2 {
            return "\(first) \(parts[1])"
        }

        return first
    }

    /// Evaluate a shell resource string against shell policy.
    private func evaluateShellResource(
        _ resource: String,
        mode: PermissionMode
    ) -> PermissionDecision {
        let rules = policyConfig.rules(for: .shell)
        let matchResult = RuleResolver.resolve(resource: resource, rules: rules)

        let baseDecision: PermissionDecision
        if let match = matchResult {
            baseDecision = decisionFromEffect(match.effect, reason: match.reason)
        } else {
            baseDecision = .ask(reason: "No matching shell policy rule found.")
        }

        return applyMode(baseDecision, mode: mode, scope: .shell)
    }

    /// Convert a PolicyEffect into a PermissionDecision.
    private func decisionFromEffect(
        _ effect: PolicyEffect,
        reason: String?
    ) -> PermissionDecision {
        let resolvedReason = reason ?? "Policy rule matched."
        switch effect {
        case .allow: return .allow
        case .ask:   return .ask(reason: resolvedReason)
        case .deny:  return .deny(reason: resolvedReason)
        }
    }

    /// Default decision when no rules match for a scope.
    private func defaultDecision(for scope: PermissionScope) -> PermissionDecision {
        switch scope {
        case .tool:   return .ask(reason: "No matching rule for tool — confirmation required.")
        case .fs:     return .ask(reason: "No matching rule for file operation — confirmation required.")
        case .net:    return .ask(reason: "No matching rule for network request — confirmation required.")
        case .secret: return .deny(reason: "Secret access is denied by default.")
        case .shell:  return .ask(reason: "No matching rule for shell command — confirmation required.")
        }
    }

    /// Adjust the base decision according to the permission mode.
    ///
    /// - `auto` mode: promote `ask` to `allow` (deny stays deny).
    /// - `plan` mode: demote `allow` to `ask` for write scopes.
    /// - `default` mode: use the base decision unchanged.
    private func applyMode(
        _ decision: PermissionDecision,
        mode: PermissionMode,
        scope: PermissionScope
    ) -> PermissionDecision {
        switch mode {
        case .auto:
            // In auto mode, only deny remains; ask is promoted to allow
            if case .ask = decision {
                return .allow
            }
            return decision

        case .plan:
            // In plan mode, all write operations require confirmation
            let writeScopes: Set<PermissionScope> = [.fs, .shell, .net]
            if writeScopes.contains(scope), case .allow = decision {
                return .ask(reason: "Plan mode: write operations require confirmation.")
            }
            return decision

        case .default:
            return decision
        }
    }
}
