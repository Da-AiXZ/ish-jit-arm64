// GrepTool.swift
// CodingPad
//
// Content search using regular expressions across files.

import Foundation

// MARK: - GrepTool

/// Searches file contents using regular expressions.
///
/// Returns matching lines with file path, line number, and optional context lines.
/// Read-only and concurrency-safe.
struct GrepTool: AgentTool {
    let name = "grep"

    let description = "Content search using regular expressions. Searches file contents and returns matching lines with file paths and line numbers."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "pattern": .init(
                type: "string",
                description: "The regular expression pattern to search for in file contents.",
                enumValues: nil
            ),
            "path": .init(
                type: "string",
                description: "File or directory to search in. Defaults to current working directory.",
                enumValues: nil
            ),
            "glob": .init(
                type: "string",
                description: "Glob pattern to filter files (e.g. \"*.swift\", \"*.{ts,tsx}\").",
                enumValues: nil
            ),
            "context": .init(
                type: "integer",
                description: "Number of lines to show before and after each match. Default is 0.",
                enumValues: nil
            )
        ],
        required: ["pattern"]
    )

    let usagePrompt = """
    Content search built on regular expressions. Prefer this for searching file contents.

    - Full regex syntax supported (e.g. "log.*Error", "func\\s+\\w+").
    - Filter files with `glob` (e.g. "*.swift") to narrow the search scope.
    - `context` adds surrounding lines before and after each match.
    - Returns matching lines with file paths and line numbers.
    - Read-only operation — does not modify any files.
    - Use this instead of searching manually through files.
    """

    let isReadOnly = true
    let isConcurrencySafe = true

    // MARK: - Constants

    private enum Constants {
        static let maxResults = 500
        static let maxFileSize = 5 * 1024 * 1024 // 5 MB
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

        // Validate regex
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return .error("Invalid regular expression '\(pattern)': \(error.localizedDescription)")
        }

        let basePath: String
        if let path = input.string(for: "path") {
            basePath = (path as NSString).standardizingPath
        } else {
            basePath = FileManager.default.currentDirectoryPath
        }

        let globFilter = input.string(for: "glob")
        let contextLines = input.int(for: "context") ?? 0

        // Determine if basePath is a file or directory
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: basePath, isDirectory: &isDirectory) else {
            return .error("Path not found: \(basePath)")
        }

        let filesToSearch: [String]
        if isDirectory.boolValue {
            filesToSearch = collectFiles(in: basePath, globFilter: globFilter)
        } else {
            filesToSearch = [basePath]
        }

        // Search files
        var allMatches: [MatchResult] = []
        var filesSearched = 0

        for filePath in filesToSearch {
            guard allMatches.count < Constants.maxResults else { break }

            guard let fileData = fileManager.contents(atPath: filePath),
                  fileData.count <= Constants.maxFileSize,
                  !isBinaryData(fileData),
                  let content = String(data: fileData, encoding: .utf8) else {
                continue
            }

            filesSearched += 1
            let lines = content.components(separatedBy: .newlines)
            let fileMatches = searchLines(
                lines: lines,
                regex: regex,
                filePath: filePath,
                contextLines: contextLines
            )
            allMatches.append(contentsOf: fileMatches)
        }

        if allMatches.isEmpty {
            return .success("No matches found for pattern '\(pattern)' (\(filesSearched) files searched)")
        }

        // Format output
        let limited = Array(allMatches.prefix(Constants.maxResults))
        let output = limited.map(\.formatted).joined(separator: "\n")

        var resultText = output
        if allMatches.count > Constants.maxResults {
            resultText += "\n\n... \(allMatches.count - Constants.maxResults) more matches truncated"
        }

        return ToolResult(
            content: resultText,
            metadata: [
                "match_count": "\(allMatches.count)",
                "files_searched": "\(filesSearched)"
            ]
        )
    }

    // MARK: - Search Helpers

    /// A single match result with file path, line number, and formatted output.
    private struct MatchResult {
        let filePath: String
        let lineNumber: Int
        let formatted: String
    }

    /// Search lines in a file for regex matches, including context lines.
    private func searchLines(
        lines: [String],
        regex: NSRegularExpression,
        filePath: String,
        contextLines: Int
    ) -> [MatchResult] {
        var results: [MatchResult] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard regex.firstMatch(in: line, options: [], range: range) != nil else {
                continue
            }

            if contextLines > 0 {
                let startLine = max(0, index - contextLines)
                let endLine = min(lines.count - 1, index + contextLines)

                var contextOutput = "\(filePath):\(index + 1): (with context)\n"
                for ctxIndex in startLine...endLine {
                    let marker = ctxIndex == index ? ">" : " "
                    contextOutput += "  \(marker) \(ctxIndex + 1)\t\(lines[ctxIndex])\n"
                }

                results.append(MatchResult(
                    filePath: filePath,
                    lineNumber: index + 1,
                    formatted: contextOutput.trimmingCharacters(in: .newlines)
                ))
            } else {
                let formatted = "\(filePath):\(index + 1):\(line)"
                results.append(MatchResult(
                    filePath: filePath,
                    lineNumber: index + 1,
                    formatted: formatted
                ))
            }
        }

        return results
    }

    /// Collects files from a directory, optionally filtering by glob pattern.
    private func collectFiles(in directoryPath: String, globFilter: String?) -> [String] {
        let fileManager = FileManager.default
        var files: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directoryPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            if let globFilter = globFilter {
                let fileName = fileURL.lastPathComponent
                if matchesSimpleGlob(fileName: fileName, pattern: globFilter) {
                    files.append(fileURL.path)
                }
            } else {
                files.append(fileURL.path)
            }
        }

        return files
    }

    /// Simple glob matching for file name filtering.
    /// Supports *, ?, and {a,b} patterns against file names.
    private func matchesSimpleGlob(fileName: String, pattern: String) -> Bool {
        // Handle {a,b,c} expansion
        if pattern.contains("{") && pattern.contains("}") {
            guard let braceStart = pattern.firstIndex(of: "{"),
                  let braceEnd = pattern.firstIndex(of: "}") else {
                return false
            }
            let prefix = String(pattern[pattern.startIndex..<braceStart])
            let suffix = String(pattern[pattern.index(after: braceEnd)...])
            let alternatives = String(pattern[pattern.index(after: braceStart)..<braceEnd])
                .components(separatedBy: ",")

            return alternatives.contains { alt in
                matchesSimpleGlob(fileName: fileName, pattern: prefix + alt + suffix)
            }
        }

        // Convert simple glob to regex
        var regex = "^"
        for char in pattern {
            switch char {
            case "*": regex += ".*"
            case "?": regex += "."
            case ".": regex += "\\."
            default: regex += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        regex += "$"

        guard let regexObj = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        return regexObj.firstMatch(in: fileName, options: [], range: range) != nil
    }

    /// Checks if data appears to be binary by looking for null bytes.
    private func isBinaryData(_ data: Data) -> Bool {
        let checkLength = min(data.count, 8192)
        return data.prefix(checkLength).contains(0x00)
    }
}
