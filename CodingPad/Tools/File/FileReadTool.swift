// FileReadTool.swift
// CodingPad
//
// Reads file contents with optional line offset/limit, outputting cat -n format.

import Foundation

// MARK: - FileReadTool

/// Reads the contents of a file, returning numbered lines in `cat -n` format.
///
/// Supports optional line offset and limit for reading portions of large files.
/// Detects and rejects binary files. Read-only and concurrency-safe.
struct FileReadTool: AgentTool {
    let name = "file_read"

    let description = "Reads a file from the filesystem and returns its contents with line numbers."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "file_path": .init(
                type: "string",
                description: "The absolute path to the file to read.",
                enumValues: nil
            ),
            "offset": .init(
                type: "integer",
                description: "The line number to start reading from (1-based). Only provide if the file is too large to read at once.",
                enumValues: nil
            ),
            "limit": .init(
                type: "integer",
                description: "The number of lines to read. Only provide if the file is too large to read at once.",
                enumValues: nil
            )
        ],
        required: ["file_path"]
    )

    let usagePrompt = """
    Reads a file from the local filesystem.

    - `file_path` must be an absolute path.
    - Reads up to 2000 lines by default.
    - You can optionally specify a line offset and limit (especially handy for long files), \
    but it's recommended to read the whole file by not providing these parameters.
    - Results are returned using cat -n format, with line numbers starting at 1.
    - Reading a directory, a missing file, or an empty file returns an error.
    - Do NOT re-read a file you just edited to verify — Edit would have errored if the change failed.
    - Binary files (images, compiled objects, etc.) are rejected.
    """

    let isReadOnly = true
    let isConcurrencySafe = true

    // MARK: - Constants

    private enum Constants {
        static let defaultLineLimit = 2000
        static let maxFileSize = 10 * 1024 * 1024 // 10 MB
        static let binaryCheckLength = 8192
    }

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let filePath = input.string(for: "file_path") else {
            return .deny(reason: "Missing required parameter: file_path")
        }
        guard filePath.hasPrefix("/") || filePath.contains(":\\") || filePath.contains(":/") else {
            return .deny(reason: "file_path must be an absolute path. Got: \(filePath)")
        }
        return .allow
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let filePath = input.string(for: "file_path") else {
            return .error("Missing required parameter: file_path")
        }

        let fileManager = FileManager.default
        let normalizedPath = (filePath as NSString).standardizingPath

        // Check existence
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
            return .error("File not found: \(normalizedPath)")
        }

        // Reject directories
        if isDirectory.boolValue {
            return .error("Path is a directory, not a file: \(normalizedPath)")
        }

        // Check file size
        guard let attributes = try? fileManager.attributesOfItem(atPath: normalizedPath),
              let fileSize = attributes[.size] as? Int else {
            return .error("Cannot read file attributes: \(normalizedPath)")
        }

        if fileSize == 0 {
            return .error("File is empty: \(normalizedPath)")
        }

        if fileSize > Constants.maxFileSize {
            return .error("File too large (\(fileSize) bytes, max \(Constants.maxFileSize)). Use offset and limit to read portions.")
        }

        // Read data
        guard let data = fileManager.contents(atPath: normalizedPath) else {
            return .error("Cannot read file: \(normalizedPath)")
        }

        // Binary detection
        if isBinaryData(data) {
            return .error("Cannot read binary file: \(normalizedPath). This tool only supports text files.")
        }

        // Decode as UTF-8
        guard let content = String(data: data, encoding: .utf8) else {
            return .error("File is not valid UTF-8 text: \(normalizedPath)")
        }

        // Split into lines
        let allLines = content.components(separatedBy: .newlines)
        let offset = max((input.int(for: "offset") ?? 1), 1)
        let limit = input.int(for: "limit") ?? Constants.defaultLineLimit

        // Apply offset and limit (1-based offset)
        let startIndex = offset - 1
        guard startIndex < allLines.count else {
            return .error("Offset \(offset) exceeds file line count (\(allLines.count)).")
        }

        let endIndex = min(startIndex + limit, allLines.count)
        let selectedLines = allLines[startIndex..<endIndex]

        // Format as cat -n output
        let formatted = selectedLines.enumerated().map { index, line in
            let lineNumber = startIndex + index + 1
            return "\(lineNumber)\t\(line)"
        }.joined(separator: "\n")

        let totalLines = allLines.count
        var metadata: [String: String] = [
            "file_path": normalizedPath,
            "total_lines": "\(totalLines)"
        ]

        if startIndex > 0 || endIndex < totalLines {
            metadata["showing"] = "lines \(offset)-\(endIndex) of \(totalLines)"
        }

        return ToolResult(content: formatted, metadata: metadata)
    }

    // MARK: - Binary Detection

    /// Checks if data appears to be binary by looking for null bytes in the first chunk.
    private func isBinaryData(_ data: Data) -> Bool {
        let checkLength = min(data.count, Constants.binaryCheckLength)
        let prefix = data.prefix(checkLength)
        return prefix.contains(0x00)
    }
}
