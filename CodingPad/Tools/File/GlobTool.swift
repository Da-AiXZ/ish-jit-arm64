// GlobTool.swift
// CodingPad
//
// File pattern matching search using glob-style wildcards.

import Foundation

// MARK: - GlobTool

/// Searches for files matching a glob pattern (*, **, ?).
///
/// Returns matching file paths sorted by modification time (most recent first).
/// Read-only and concurrency-safe.
struct GlobTool: AgentTool {
    let name = "glob"

    let description = "Fast file pattern matching. Supports glob patterns like \"**/*.swift\" or \"Sources/**/*.swift\". Returns matching file paths sorted by modification time."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "pattern": .init(
                type: "string",
                description: "The glob pattern to match files against (e.g. \"**/*.swift\", \"Sources/**/*.ts\").",
                enumValues: nil
            ),
            "path": .init(
                type: "string",
                description: "The directory to search in. Defaults to the current working directory if not specified.",
                enumValues: nil
            )
        ],
        required: ["pattern"]
    )

    let usagePrompt = """
    Fast file pattern matching. Supports glob patterns like "**/*.swift" or "Sources/**/*.ts".

    - Returns matching file paths sorted by modification time (most recent first).
    - Use `**` to match any number of directories.
    - Use `*` to match any characters within a single path component.
    - Use `?` to match a single character.
    - If `path` is not specified, searches from the current working directory.
    - Read-only operation — does not modify any files.
    """

    let isReadOnly = true
    let isConcurrencySafe = true

    // MARK: - Constants

    private enum Constants {
        static let maxResults = 1000
    }

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        .allow
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let pattern = input.string(for: "pattern") else {
            return .error("Missing required parameter: pattern")
        }

        let basePath: String
        if let path = input.string(for: "path") {
            basePath = (path as NSString).standardizingPath
        } else {
            basePath = FileManager.default.currentDirectoryPath
        }

        // Verify base path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: basePath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .error("Directory not found: \(basePath)")
        }

        // Collect matching files
        let matches = findMatchingFiles(pattern: pattern, basePath: basePath)

        if matches.isEmpty {
            return .success("No files matched the pattern '\(pattern)' in \(basePath)")
        }

        // Sort by modification time (most recent first)
        let sorted = sortByModificationTime(matches)

        // Limit results
        let limited = Array(sorted.prefix(Constants.maxResults))
        let output = limited.joined(separator: "\n")

        var resultText = output
        if sorted.count > Constants.maxResults {
            resultText += "\n\n... and \(sorted.count - Constants.maxResults) more files (showing first \(Constants.maxResults))"
        }

        return ToolResult(
            content: resultText,
            metadata: ["match_count": "\(sorted.count)", "base_path": basePath]
        )
    }

    // MARK: - Glob Matching

    /// Recursively finds files matching the glob pattern under basePath.
    private func findMatchingFiles(pattern: String, basePath: String) -> [String] {
        let fileManager = FileManager.default
        var results: [String] = []

        // If pattern contains **, we need recursive enumeration
        let isRecursive = pattern.contains("**")

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: basePath),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: isRecursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
            if matchesGlob(path: relativePath, pattern: pattern) {
                results.append(fileURL.path)
            }
        }

        return results
    }

    /// Sorts file paths by modification time, most recent first.
    private func sortByModificationTime(_ paths: [String]) -> [String] {
        let fileManager = FileManager.default
        let pathsWithDates: [(path: String, date: Date)] = paths.compactMap { path in
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let modDate = attributes[.modificationDate] as? Date else {
                return (path, Date.distantPast)
            }
            return (path, modDate)
        }

        return pathsWithDates
            .sorted { $0.date > $1.date }
            .map(\.path)
    }

    /// Matches a relative path against a glob pattern.
    ///
    /// Supports `*` (any characters except /), `**` (any path segments), and `?` (single char).
    private func matchesGlob(path: String, pattern: String) -> Bool {
        let regexPattern = globToRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return false
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    /// Converts a glob pattern to a regular expression string.
    private func globToRegex(_ glob: String) -> String {
        var regex = "^"
        var i = glob.startIndex

        while i < glob.endIndex {
            let char = glob[i]

            if char == "*" {
                let next = glob.index(after: i)
                if next < glob.endIndex && glob[next] == "*" {
                    // ** — match any path segments
                    let afterStars = glob.index(after: next)
                    if afterStars < glob.endIndex && glob[afterStars] == "/" {
                        regex += "(.+/)?"
                        i = glob.index(after: afterStars)
                        continue
                    } else {
                        regex += ".*"
                        i = afterStars
                        continue
                    }
                } else {
                    // * — match any characters except /
                    regex += "[^/]*"
                }
            } else if char == "?" {
                regex += "[^/]"
            } else if char == "." {
                regex += "\\."
            } else if char == "/" {
                regex += "/"
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(char))
            }

            i = glob.index(after: i)
        }

        regex += "$"
        return regex
    }
}
