// FileEditTool.swift
// CodingPad
//
// Performs exact string replacement in a file.

import Foundation

// MARK: - FileEditTool

/// Performs exact string replacement within a file.
///
/// The `old_string` must match the file content exactly (including indentation).
/// By default, the match must be unique; set `replace_all` to replace every occurrence.
struct FileEditTool: AgentTool {
    let name = "file_edit"

    let description = "Performs exact string replacement in a file. The old_string must match the file exactly and be unique unless replace_all is set."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "file_path": .init(
                type: "string",
                description: "The absolute path to the file to modify.",
                enumValues: nil
            ),
            "old_string": .init(
                type: "string",
                description: "The exact text to find and replace. Must match the file content exactly, including indentation.",
                enumValues: nil
            ),
            "new_string": .init(
                type: "string",
                description: "The text to replace old_string with. Must be different from old_string.",
                enumValues: nil
            ),
            "replace_all": .init(
                type: "boolean",
                description: "If true, replaces every occurrence of old_string. Default is false (requires unique match).",
                enumValues: nil
            )
        ],
        required: ["file_path", "old_string", "new_string"]
    )

    let usagePrompt = """
    Performs exact string replacement in a file.

    - You must have read the file in this conversation before editing, or the call may produce unexpected results.
    - `old_string` must match the file exactly, including indentation, and be unique — the edit fails otherwise.
    - `new_string` must be different from `old_string`.
    - `replace_all: true` replaces every occurrence instead of requiring a unique match.
    - This tool requires write permission and will prompt the user for confirmation.
    """

    let isReadOnly = false
    let isConcurrencySafe = false

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let filePath = input.string(for: "file_path") else {
            return .deny(reason: "Missing required parameter: file_path")
        }
        guard filePath.hasPrefix("/") || filePath.contains(":\\") || filePath.contains(":/") else {
            return .deny(reason: "file_path must be an absolute path. Got: \(filePath)")
        }
        return .ask(reason: "Edit file: \(filePath)")
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let filePath = input.string(for: "file_path") else {
            return .error("Missing required parameter: file_path")
        }
        guard let oldString = input.string(for: "old_string") else {
            return .error("Missing required parameter: old_string")
        }
        guard let newString = input.string(for: "new_string") else {
            return .error("Missing required parameter: new_string")
        }

        // Validate old != new
        if oldString == newString {
            return .error("new_string must be different from old_string.")
        }

        let fileManager = FileManager.default
        let normalizedPath = (filePath as NSString).standardizingPath

        // Check file exists
        guard fileManager.fileExists(atPath: normalizedPath) else {
            return .error("File not found: \(normalizedPath)")
        }

        // Read current content
        guard let data = fileManager.contents(atPath: normalizedPath),
              let content = String(data: data, encoding: .utf8) else {
            return .error("Cannot read file as UTF-8: \(normalizedPath)")
        }

        let replaceAll = input.bool(for: "replace_all") ?? false

        // Count occurrences
        let occurrences = countOccurrences(of: oldString, in: content)

        if occurrences == 0 {
            return .error("old_string not found in file. Make sure it matches exactly, including whitespace and indentation.")
        }

        if !replaceAll && occurrences > 1 {
            return .error("old_string matches \(occurrences) locations. It must be unique (match exactly once). Add more context to make it unique, or use replace_all: true.")
        }

        // Perform replacement
        let updatedContent: String
        if replaceAll {
            updatedContent = content.replacingOccurrences(of: oldString, with: newString)
        } else {
            // Replace only the first (and only) occurrence
            guard let range = content.range(of: oldString) else {
                return .error("old_string not found (unexpected error).")
            }
            updatedContent = content.replacingCharacters(in: range, with: newString)
        }

        // Write back
        guard let updatedData = updatedContent.data(using: .utf8) else {
            return .error("Updated content cannot be encoded as UTF-8.")
        }

        do {
            try updatedData.write(to: URL(fileURLWithPath: normalizedPath), options: .atomic)
        } catch {
            return .error("Failed to write file '\(normalizedPath)': \(error.localizedDescription)")
        }

        let replacementCount = replaceAll ? occurrences : 1
        return .success("Replaced \(replacementCount) occurrence(s) in \(normalizedPath)")
    }

    // MARK: - Helpers

    /// Counts non-overlapping occurrences of a substring in a string.
    private func countOccurrences(of target: String, in source: String) -> Int {
        var count = 0
        var searchRange = source.startIndex..<source.endIndex

        while let range = source.range(of: target, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<source.endIndex
        }

        return count
    }
}
