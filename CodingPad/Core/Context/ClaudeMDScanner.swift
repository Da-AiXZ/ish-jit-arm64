// ClaudeMDScanner.swift
// CodingPad
//
// Discovers and loads CLAUDE.md files recursively from project directories.
// Results are cached based on file modification times for efficient reuse.

import Foundation
import os

// MARK: - Scan Result Types

/// Represents a single discovered CLAUDE.md file.
struct ClaudeMDFile: Sendable {
    let path: String
    let relativePath: String
    let modificationDate: Date
    let content: String
}

/// The merged result of scanning all CLAUDE.md files in a project.
struct ClaudeMDScanResult: Sendable {
    let mergedContent: String
    let files: [ClaudeMDFile]
    let totalSize: Int

    var fileCount: Int { files.count }
    var isEmpty: Bool { files.isEmpty }
}

// MARK: - ClaudeMDScanner Errors

enum ClaudeMDScannerError: Error, LocalizedError {
    case invalidPath(String)
    case directoryAccessFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid project path: \(path)"
        case .directoryAccessFailed(let path):
            return "Cannot access directory: \(path)"
        }
    }
}

// MARK: - ClaudeMDScanner

/// Recursively scans project directories for CLAUDE.md files,
/// merges their content, and caches results keyed by file fingerprints.
///
/// Cache invalidation is automatic: if any CLAUDE.md file's modification
/// date changes, the next scan re-reads all files.
actor ClaudeMDScanner {

    /// Filenames to look for (case-sensitive on most file systems).
    static let targetFilenames: Set<String> = [
        "CLAUDE.md",
        "claude.md",
    ]

    /// Maximum directory depth for recursive scanning.
    static let maxDepth: Int = 5

    /// Directories to skip during scanning.
    static let excludedDirectories: Set<String> = [
        ".git", ".svn", "node_modules", ".build", "build",
        "DerivedData", ".swiftpm", ".cache", "__pycache__",
        ".next", ".nuxt", "dist", "out", "vendor", "Pods",
    ]

    /// Maximum file size to read (1 MB).
    static let maxFileSize: Int = 1_048_576

    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.codingpad", category: "ClaudeMDScanner")

    /// Cached scan result with file fingerprints for change detection.
    private struct CachedScan: Sendable {
        let result: ClaudeMDScanResult
        let fingerprints: [String: Date]
    }
    private var cache: [String: CachedScan] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Scans the project directory for all CLAUDE.md files and returns merged content.
    /// Returns cached result if no files have changed since last scan.
    func scan(projectPath: String) async throws -> ClaudeMDScanResult {
        let resolvedPath = resolvePath(projectPath)

        guard fileManager.fileExists(atPath: resolvedPath) else {
            throw ClaudeMDScannerError.invalidPath(resolvedPath)
        }

        // 1. Discover all CLAUDE.md files
        let discoveredFiles = try discoverFiles(in: resolvedPath)

        // 2. Compute fingerprints for change detection
        let currentFingerprints = computeFingerprints(from: discoveredFiles)

        // 3. Return cached result if fingerprints match
        if let cached = cache[resolvedPath], cached.fingerprints == currentFingerprints {
            logger.debug("ClaudeMD cache hit for \(resolvedPath)")
            return cached.result
        }

        // 4. Merge content from all files
        let result = mergeContent(from: discoveredFiles, projectPath: resolvedPath)

        // 5. Update cache
        cache[resolvedPath] = CachedScan(
            result: result,
            fingerprints: currentFingerprints
        )

        logger.info("Scanned \(result.fileCount) CLAUDE.md file(s) in \(resolvedPath)")
        return result
    }

    /// Returns merged CLAUDE.md content as a plain string (empty if none found).
    func scanContent(projectPath: String) async -> String {
        guard let result = try? await scan(projectPath: projectPath) else {
            return ""
        }
        return result.mergedContent
    }

    /// Invalidates the cached scan result for a specific project.
    func invalidate(projectPath: String) {
        let resolvedPath = resolvePath(projectPath)
        cache.removeValue(forKey: resolvedPath)
    }

    /// Clears all cached scan results.
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private: File Discovery

    /// Resolves and normalizes a path.
    private func resolvePath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Recursively discovers all CLAUDE.md files within the given directory.
    private func discoverFiles(in directory: String) throws -> [ClaudeMDFile] {
        var results: [ClaudeMDFile] = []
        try scanDirectory(directory, depth: 0, results: &results)
        return results.sorted { $0.relativePath < $1.relativePath }
    }

    /// Recursively scans a single directory level.
    private func scanDirectory(
        _ directory: String,
        depth: Int,
        results: inout [ClaudeMDFile]
    ) throws {
        guard depth <= Self.maxDepth else { return }

        let url = URL(fileURLWithPath: directory)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for itemURL in contents {
            let name = itemURL.lastPathComponent

            // Skip excluded directories
            if Self.excludedDirectories.contains(name) {
                continue
            }

            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                try scanDirectory(itemURL.path, depth: depth + 1, results: &results)
            } else if Self.targetFilenames.contains(name) {
                if let file = try? readClaudeMDFile(at: itemURL, relativeTo: directory) {
                    results.append(file)
                }
            }
        }
    }

    /// Reads a single CLAUDE.md file from disk.
    private func readClaudeMDFile(
        at url: URL,
        relativeTo projectRoot: String
    ) throws -> ClaudeMDFile {
        let attrs = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = attrs.fileSize ?? 0

        let modDate = attrs.contentModificationDate ?? Date()

        // Skip oversized files
        guard fileSize <= Self.maxFileSize else {
            logger.warning("Skipping oversized CLAUDE.md: \(url.path) (\(fileSize) bytes)")
            return ClaudeMDFile(
                path: url.path,
                relativePath: relativePath(from: projectRoot, to: url.path),
                modificationDate: modDate,
                content: "[File too large: \(fileSize) bytes]"
            )
        }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        return ClaudeMDFile(
            path: url.path,
            relativePath: relativePath(from: projectRoot, to: url.path),
            modificationDate: modDate,
            content: content
        )
    }

    // MARK: - Private: Cache Helpers

    /// Computes a fingerprint dictionary (file path -> modification date) for change detection.
    private func computeFingerprints(from files: [ClaudeMDFile]) -> [String: Date] {
        var fingerprints: [String: Date] = [:]
        for file in files {
            fingerprints[file.path] = file.modificationDate
        }
        return fingerprints
    }

    /// Merges content from all discovered files into a single string.
    private func mergeContent(from files: [ClaudeMDFile], projectPath: String) -> ClaudeMDScanResult {
        guard !files.isEmpty else {
            return ClaudeMDScanResult(mergedContent: "", files: [], totalSize: 0)
        }

        let sections = files.map { file -> String in
            let header: String
            if file.relativePath == "CLAUDE.md" || file.relativePath == "claude.md" {
                header = "--- Project Root CLAUDE.md ---"
            } else {
                header = "--- \(file.relativePath) ---"
            }
            return "\(header)\n\n\(file.content)"
        }

        let merged = sections.joined(separator: "\n\n")

        return ClaudeMDScanResult(
            mergedContent: merged,
            files: files,
            totalSize: merged.utf8.count
        )
    }

    /// Computes a path relative to the project root.
    private func relativePath(from root: String, to fullPath: String) -> String {
        if fullPath.hasPrefix(root) {
            let relative = String(fullPath.dropFirst(root.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return fullPath
    }
}
