// FileWriteTool.swift
// CodingPad
//
// Creates or overwrites a file, auto-creating intermediate directories.

import Foundation

// MARK: - FileWriteTool

/// Creates a new file or overwrites an existing one with the provided content.
///
/// Automatically creates intermediate directories if they don't exist.
/// Non-read-only: requires permission confirmation.
struct FileWriteTool: AgentTool {
    let name = "file_write"

    let description = "Creates or overwrites a file with the given content, creating intermediate directories as needed."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "file_path": .init(
                type: "string",
                description: "The absolute path to the file to write.",
                enumValues: nil
            ),
            "content": .init(
                type: "string",
                description: "The content to write to the file.",
                enumValues: nil
            )
        ],
        required: ["file_path", "content"]
    )

    let usagePrompt = """
    Writes a file to the local filesystem, overwriting if one exists.

    When to use: creating a new file, or fully replacing one you've already read.
    - `file_path` must be an absolute path.
    - Intermediate directories are created automatically.
    - For partial changes to an existing file, use file_edit instead.
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
        return .ask(reason: "Write to file: \(filePath)")
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let filePath = input.string(for: "file_path") else {
            return .error("Missing required parameter: file_path")
        }
        guard let content = input.string(for: "content") else {
            return .error("Missing required parameter: content")
        }

        let fileManager = FileManager.default
        let normalizedPath = (filePath as NSString).standardizingPath

        // Create intermediate directories
        let directoryPath = (normalizedPath as NSString).deletingLastPathComponent
        do {
            try fileManager.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return .error("Failed to create directory '\(directoryPath)': \(error.localizedDescription)")
        }

        // Determine if we are creating or overwriting
        let isOverwrite = fileManager.fileExists(atPath: normalizedPath)

        // Write content
        guard let data = content.data(using: .utf8) else {
            return .error("Content cannot be encoded as UTF-8.")
        }

        do {
            try data.write(to: URL(fileURLWithPath: normalizedPath), options: .atomic)
        } catch {
            return .error("Failed to write file '\(normalizedPath)': \(error.localizedDescription)")
        }

        let lineCount = content.components(separatedBy: .newlines).count
        let byteCount = data.count
        let action = isOverwrite ? "Updated" : "Created"

        return .success("\(action) file: \(normalizedPath) (\(lineCount) lines, \(byteCount) bytes)")
    }
}
