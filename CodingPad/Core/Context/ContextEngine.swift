// ContextEngine.swift
// CodingPad
//
// Three-layer context engine (L0/L1/L2) that assembles context segments
// on demand based on the current message, project state, and agent config.

import Foundation
import os

// MARK: - ContextEngine Errors

enum ContextEngineError: Error, LocalizedError {
    case projectPathRequired
    case contextAssemblyFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectPathRequired:
            return "A project path is required for L1/L2 context."
        case .contextAssemblyFailed(let detail):
            return "Context assembly failed: \(detail)"
        }
    }
}

// MARK: - ContextEngine

/// Assembles context segments in three layers of increasing detail:
///
/// - **L0** (always injected, <2K tokens): System role, user preferences,
///   active project name/type, available tools summary.
/// - **L1** (project-aware, <8K tokens): CLAUDE.md content, README summary,
///   recent relevant memories, project file structure summary.
/// - **L2** (request-aware, variable): File contents referenced in the
///   user message, git status/diff, search results.
actor ContextEngine {

    private let claudeMDScanner: ClaudeMDScanner
    private let cache: ContextCache<String, String>
    private let logger = Logger(subsystem: "com.codingpad", category: "ContextEngine")

    /// Token budget per context level.
    private static let l0TokenBudget = 2_000
    private static let l1TokenBudget = 8_000

    init(
        claudeMDScanner: ClaudeMDScanner = ClaudeMDScanner(),
        cache: ContextCache<String, String> = ContextCache(defaultTTL: 300)
    ) {
        self.claudeMDScanner = claudeMDScanner
        self.cache = cache
    }

    // MARK: - Public API

    /// Assembles all applicable context segments for the given message.
    ///
    /// - Parameters:
    ///   - message: The user's current message text.
    ///   - projectPath: Optional path to the active project directory.
    ///   - config: The current agent configuration.
    /// - Returns: An array of context segments ordered by level (L0 first).
    func assemble(
        for message: String,
        projectPath: String?,
        config: AgentConfig
    ) async -> [ContextSegment] {
        var segments: [ContextSegment] = []

        // L0: Always injected
        let l0Segments = assembleL0(config: config)
        segments.append(contentsOf: l0Segments)

        // L1: Project-aware (only when a project is active)
        if let path = projectPath {
            let l1Segments = await assembleL1(projectPath: path, config: config)
            segments.append(contentsOf: l1Segments)
        }

        // L2: Request-aware (driven by user message content)
        if let path = projectPath {
            let l2Segments = await assembleL2(
                message: message,
                projectPath: path,
                config: config
            )
            segments.append(contentsOf: l2Segments)
        }

        logger.info("Assembled \(segments.count) context segments (total ~\(segments.map(\.estimatedTokens).reduce(0, +)) tokens)")
        return segments
    }

    // MARK: - L0: Always Injected (<2K tokens)

    /// Assembles L0 context: system role, user prefs, project meta, tools summary.
    private func assembleL0(config: AgentConfig) -> [ContextSegment] {
        var segments: [ContextSegment] = []

        // System role identity
        let roleContent = """
            You are CodingPad, an AI coding assistant running on iPad/iOS. \
            You have direct access to the local filesystem via iSH (Alpine Linux) \
            and can read, write, search, and edit files. You think step-by-step, \
            use tools precisely, and always confirm destructive operations.
            """
        segments.append(ContextSegment(
            level: .l0,
            label: "system_role",
            content: roleContent,
            isCacheable: true,
            estimatedTokens: estimateTokens(roleContent)
        ))

        // User preferences
        let prefsContent = """
            Language: \(config.language)
            Output style: \(config.outputStyle)
            Permission mode: \(config.permissionMode.rawValue)
            """
        segments.append(ContextSegment(
            level: .l0,
            label: "user_preferences",
            content: prefsContent,
            isCacheable: false,
            estimatedTokens: estimateTokens(prefsContent)
        ))

        // Model info
        let modelContent = "Model: \(config.modelId), Max tokens: \(config.maxTokens)"
        segments.append(ContextSegment(
            level: .l0,
            label: "model_info",
            content: modelContent,
            isCacheable: true,
            estimatedTokens: estimateTokens(modelContent)
        ))

        return segments
    }

    // MARK: - L1: Project-Aware (<8K tokens)

    /// Assembles L1 context: CLAUDE.md, README summary, file structure.
    private func assembleL1(
        projectPath: String,
        config: AgentConfig
    ) async -> [ContextSegment] {
        var segments: [ContextSegment] = []

        // CLAUDE.md content
        let claudeMDContent = await claudeMDScanner.scanContent(projectPath: projectPath)
        if !claudeMDContent.isEmpty {
            let truncated = truncateToTokenBudget(claudeMDContent, budget: 4_000)
            segments.append(ContextSegment(
                level: .l1,
                label: "claude_md",
                content: truncated,
                isCacheable: true,
                estimatedTokens: estimateTokens(truncated)
            ))
        }

        // Project name and type detection
        let projectName = (projectPath as NSString).lastPathComponent
        let projectType = await detectProjectType(at: projectPath)
        let projectMeta = "Project: \(projectName) (\(projectType))\nPath: \(projectPath)"
        segments.append(ContextSegment(
            level: .l1,
            label: "project_meta",
            content: projectMeta,
            isCacheable: true,
            estimatedTokens: estimateTokens(projectMeta)
        ))

        // File structure summary (cached)
        let structureKey = "file_structure:\(projectPath)"
        let structure = await cache.value(forKey: structureKey, ttl: 120) {
            await self.scanFileStructure(at: projectPath)
        }
        if !structure.isEmpty {
            let truncated = truncateToTokenBudget(structure, budget: 2_000)
            segments.append(ContextSegment(
                level: .l1,
                label: "file_structure",
                content: truncated,
                isCacheable: true,
                estimatedTokens: estimateTokens(truncated)
            ))
        }

        return segments
    }

    // MARK: - L2: Request-Aware (Variable)

    /// Assembles L2 context driven by the user's message content.
    private func assembleL2(
        message: String,
        projectPath: String,
        config: AgentConfig
    ) async -> [ContextSegment] {
        var segments: [ContextSegment] = []

        // Extract file references from the message
        let referencedFiles = extractFileReferences(from: message)
        for filePath in referencedFiles.prefix(5) {
            let fullPath = resolveFilePath(filePath, relativeTo: projectPath)
            if let content = try? readFileContent(at: fullPath) {
                let truncated = truncateToTokenBudget(content, budget: 3_000)
                segments.append(ContextSegment(
                    level: .l2,
                    label: "file:\(filePath)",
                    content: truncated,
                    isCacheable: false,
                    estimatedTokens: estimateTokens(truncated)
                ))
            }
        }

        // Git status (if applicable)
        let gitStatus = await loadGitStatus(at: projectPath)
        if !gitStatus.isEmpty {
            segments.append(ContextSegment(
                level: .l2,
                label: "git_status",
                content: gitStatus,
                isCacheable: false,
                estimatedTokens: estimateTokens(gitStatus)
            ))
        }

        return segments
    }

    // MARK: - Private Helpers

    /// Rough token estimate: ~4 characters per token on average.
    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Truncates text to approximately fit a token budget.
    private func truncateToTokenBudget(_ text: String, budget: Int) -> String {
        let charBudget = budget * 4
        if text.count <= charBudget { return text }
        let truncated = String(text.prefix(charBudget))
        return truncated + "\n\n[... truncated to fit token budget ...]"
    }

    /// Detects the project type based on marker files.
    private func detectProjectType(at path: String) async -> String {
        let fm = FileManager.default
        let markers: [(file: String, type: String)] = [
            ("Package.swift", "Swift Package"),
            ("*.xcodeproj", "Xcode Project"),
            ("*.xcworkspace", "Xcode Workspace"),
            ("Cargo.toml", "Rust"),
            ("package.json", "Node.js"),
            ("pyproject.toml", "Python"),
            ("requirements.txt", "Python"),
            ("go.mod", "Go"),
            ("pom.xml", "Java/Maven"),
            ("build.gradle", "Java/Gradle"),
            ("Gemfile", "Ruby"),
            ("Makefile", "Make"),
        ]

        for marker in markers {
            if marker.file.contains("*") {
                // Glob-style check
                let ext = (marker.file as NSString).pathExtension
                if let contents = try? fm.contentsOfDirectory(atPath: path) {
                    if contents.contains(where: { ($0 as NSString).pathExtension == ext }) {
                        return marker.type
                    }
                }
            } else {
                let fullPath = (path as NSString).appendingPathComponent(marker.file)
                if fm.fileExists(atPath: fullPath) {
                    return marker.type
                }
            }
        }

        return "Unknown"
    }

    /// Scans the top-level file structure of a project directory.
    private func scanFileStructure(at path: String) async -> String {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return ""
        }

        let filtered = contents
            .filter { !$0.hasPrefix(".") }
            .sorted()

        var lines: [String] = ["Project structure:"]
        for item in filtered.prefix(50) {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            let icon = isDir.boolValue ? "📁" : "📄"
            lines.append("  \(icon) \(item)")
        }

        if contents.count > 50 {
            lines.append("  ... and \(contents.count - 50) more items")
        }

        return lines.joined(separator: "\n")
    }

    /// Extracts potential file paths from a user message.
    /// Looks for patterns like `path/to/file.ext` or quoted paths.
    private func extractFileReferences(from message: String) -> [String] {
        var paths: [String] = []

        // Match common file path patterns
        let patterns = [
            // Quoted paths: "some/file.swift" or 'some/file.swift'
            #"[\"']([A-Za-z0-9_./-]+\.[A-Za-z]{1,10})[\"']"#,
            // Backtick paths: `some/file.swift`
            #"`([A-Za-z0-9_./-]+\.[A-Za-z]{1,10})`"#,
            // Standalone paths with extensions
            #"\b([A-Za-z0-9_]+(?:/[A-Za-z0-9_.]+)+\.[A-Za-z]{1,10})\b"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(message.startIndex..., in: message)
            let matches = regex.matches(in: message, range: range)

            for match in matches {
                if match.numberOfRanges > 1,
                   let captureRange = Range(match.range(at: 1), in: message) {
                    let path = String(message[captureRange])
                    if !paths.contains(path) {
                        paths.append(path)
                    }
                }
            }
        }

        return paths
    }

    /// Resolves a potentially relative file path against the project root.
    private func resolveFilePath(_ path: String, relativeTo projectRoot: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (projectRoot as NSString).appendingPathComponent(path)
    }

    /// Reads the content of a file at the given path.
    private func readFileContent(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Loads git status from the project directory.
    private func loadGitStatus(at projectPath: String) async -> String {
        let gitDir = (projectPath as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else {
            return ""
        }

        // Read HEAD for current branch info
        let headFile = (gitDir as NSString).appendingPathComponent("HEAD")
        guard let headContent = try? String(contentsOfFile: headFile, encoding: .utf8) else {
            return ""
        }

        let branch: String
        if headContent.hasPrefix("ref: refs/heads/") {
            branch = String(headContent.dropFirst("ref: refs/heads/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            branch = "detached HEAD"
        }

        return "Git branch: \(branch)"
    }
}
