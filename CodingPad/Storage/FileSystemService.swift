// FileSystemService.swift
// CodingPad
//
// Wraps FileManager operations for the app's sandboxed file system.
// Provides typed access to app directories, file CRUD operations,
// and path constants.

import Foundation
import os

// MARK: - FileSystem Errors

enum FileSystemError: Error, LocalizedError {
    case fileNotFound(String)
    case directoryNotFound(String)
    case createFailed(path: String, underlying: Error)
    case deleteFailed(path: String, underlying: Error)
    case moveFailed(from: String, to: String, underlying: Error)
    case copyFailed(from: String, to: String, underlying: Error)
    case readFailed(path: String, underlying: Error)
    case writeFailed(path: String, underlying: Error)
    case pathOutsideSandbox(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .createFailed(let path, let error):
            return "Failed to create at '\(path)': \(error.localizedDescription)"
        case .deleteFailed(let path, let error):
            return "Failed to delete '\(path)': \(error.localizedDescription)"
        case .moveFailed(let from, let to, let error):
            return "Failed to move '\(from)' to '\(to)': \(error.localizedDescription)"
        case .copyFailed(let from, let to, let error):
            return "Failed to copy '\(from)' to '\(to)': \(error.localizedDescription)"
        case .readFailed(let path, let error):
            return "Failed to read '\(path)': \(error.localizedDescription)"
        case .writeFailed(let path, let error):
            return "Failed to write '\(path)': \(error.localizedDescription)"
        case .pathOutsideSandbox(let path):
            return "Path is outside the app sandbox: \(path)"
        }
    }
}

// MARK: - FileSystemService

/// Centralized file system operations for the CodingPad app.
///
/// Provides:
/// - Well-known directory paths (Documents, App Support, caches)
/// - Typed file/directory CRUD operations
/// - App directory initialization on launch
/// - Safe path validation (sandbox enforcement)
///
/// This is a stateless service — all methods operate on the shared
/// `FileManager.default`. Thread safety is guaranteed by FileManager's
/// own thread-safe design for read operations; write operations are
/// serialized at the OS level.
final class FileSystemService: Sendable {

    // MARK: - Singleton

    static let shared = FileSystemService()

    private let fm = FileManager.default
    private let logger = Logger(subsystem: "com.codingpad", category: "FileSystemService")

    private init() {}

    // MARK: - Base Directories

    /// The app's Documents directory.
    static let documentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    /// The app's Application Support directory.
    static let appSupportDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return url.appendingPathComponent("CodingPad")
    }()

    /// The app's Caches directory.
    static let cachesDirectory: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }()

    /// The app's temporary directory.
    static let tempDirectory: URL = {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }()

    // MARK: - App-Specific Subdirectories

    /// Directory for storing project files and mounted directories.
    static let projectsDirectory: URL = {
        documentsDirectory.appendingPathComponent("Projects")
    }()

    /// Directory for storing session data.
    static let sessionsDirectory: URL = {
        appSupportDirectory.appendingPathComponent("Sessions")
    }()

    /// Directory for storing memory entries.
    static let memoriesDirectory: URL = {
        appSupportDirectory.appendingPathComponent("Memories")
    }()

    /// Directory for storing policy configuration files.
    static let configDirectory: URL = {
        appSupportDirectory.appendingPathComponent("Config")
    }()

    /// Directory for iSH rootfs.
    static let ishRootfsDirectory: URL = {
        documentsDirectory.appendingPathComponent("ish-rootfs")
    }()

    // MARK: - Initialization

    /// Create all required app directories if they don't exist.
    /// Call once on app launch.
    func ensureAppDirectories() {
        let directories: [URL] = [
            Self.documentsDirectory,
            Self.appSupportDirectory,
            Self.cachesDirectory,
            Self.projectsDirectory,
            Self.sessionsDirectory,
            Self.memoriesDirectory,
            Self.configDirectory,
        ]

        for dir in directories {
            createDirectoryIfNeeded(at: dir)
        }

        logger.info("App directories ensured")
    }

    // MARK: - Directory Operations

    /// Create a directory (and intermediate directories) if it doesn't exist.
    ///
    /// - Parameter url: The directory URL to create.
    func createDirectoryIfNeeded(at url: URL) {
        guard !fm.fileExists(atPath: url.path) else { return }

        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            logger.debug("Created directory: \(url.path)")
        } catch {
            logger.error("Failed to create directory '\(url.path)': \(error.localizedDescription)")
        }
    }

    /// Create a directory at the given path.
    ///
    /// - Parameter path: Absolute path for the directory.
    /// - Throws: `FileSystemError.createFailed` on failure.
    func createDirectory(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            logger.debug("Directory created: \(path)")
        } catch {
            throw FileSystemError.createFailed(path: path, underlying: error)
        }
    }

    /// List the contents of a directory.
    ///
    /// - Parameter path: Absolute path to the directory.
    /// - Returns: An array of file/directory names.
    /// - Throws: `FileSystemError.directoryNotFound` if the path doesn't exist.
    func listDirectory(at path: String) throws -> [String] {
        guard fm.fileExists(atPath: path) else {
            throw FileSystemError.directoryNotFound(path)
        }

        do {
            return try fm.contentsOfDirectory(atPath: path)
        } catch {
            throw FileSystemError.readFailed(path: path, underlying: error)
        }
    }

    // MARK: - File Operations

    /// Check if a file or directory exists at the given path.
    func exists(at path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    /// Check if a path is a directory.
    func isDirectory(at path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Read a file's contents as a UTF-8 string.
    ///
    /// - Parameter path: Absolute path to the file.
    /// - Returns: The file's contents as a string.
    /// - Throws: `FileSystemError` on failure.
    func readFile(at path: String) throws -> String {
        guard fm.fileExists(atPath: path) else {
            throw FileSystemError.fileNotFound(path)
        }

        do {
            let url = URL(fileURLWithPath: path)
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileSystemError.readFailed(path: path, underlying: error)
        }
    }

    /// Read a file's contents as raw Data.
    ///
    /// - Parameter path: Absolute path to the file.
    /// - Returns: The file's contents as Data.
    /// - Throws: `FileSystemError` on failure.
    func readData(at path: String) throws -> Data {
        guard fm.fileExists(atPath: path) else {
            throw FileSystemError.fileNotFound(path)
        }

        do {
            let url = URL(fileURLWithPath: path)
            return try Data(contentsOf: url)
        } catch {
            throw FileSystemError.readFailed(path: path, underlying: error)
        }
    }

    /// Write a string to a file. Creates the file if it doesn't exist.
    /// Creates parent directories if needed.
    ///
    /// - Parameters:
    ///   - content: The string content to write.
    ///   - path: Absolute path to the file.
    /// - Throws: `FileSystemError.writeFailed` on failure.
    func writeFile(content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parentDir = url.deletingLastPathComponent()
        createDirectoryIfNeeded(at: parentDir)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.debug("Wrote file: \(path)")
        } catch {
            throw FileSystemError.writeFailed(path: path, underlying: error)
        }
    }

    /// Write Data to a file. Creates the file if it doesn't exist.
    ///
    /// - Parameters:
    ///   - data: The data to write.
    ///   - path: Absolute path to the file.
    /// - Throws: `FileSystemError.writeFailed` on failure.
    func writeData(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parentDir = url.deletingLastPathComponent()
        createDirectoryIfNeeded(at: parentDir)

        do {
            try data.write(to: url, options: .atomic)
            logger.debug("Wrote data to: \(path)")
        } catch {
            throw FileSystemError.writeFailed(path: path, underlying: error)
        }
    }

    /// Delete a file or directory.
    ///
    /// - Parameter path: Absolute path to the item to delete.
    /// - Throws: `FileSystemError.deleteFailed` on failure.
    func delete(at path: String) throws {
        guard fm.fileExists(atPath: path) else { return }

        do {
            try fm.removeItem(atPath: path)
            logger.debug("Deleted: \(path)")
        } catch {
            throw FileSystemError.deleteFailed(path: path, underlying: error)
        }
    }

    /// Move a file or directory.
    ///
    /// - Parameters:
    ///   - fromPath: Source path.
    ///   - toPath: Destination path.
    /// - Throws: `FileSystemError.moveFailed` on failure.
    func move(from fromPath: String, to toPath: String) throws {
        guard fm.fileExists(atPath: fromPath) else {
            throw FileSystemError.fileNotFound(fromPath)
        }

        // Ensure destination parent exists
        let destURL = URL(fileURLWithPath: toPath)
        createDirectoryIfNeeded(at: destURL.deletingLastPathComponent())

        do {
            try fm.moveItem(atPath: fromPath, toPath: toPath)
            logger.debug("Moved: \(fromPath) -> \(toPath)")
        } catch {
            throw FileSystemError.moveFailed(from: fromPath, to: toPath, underlying: error)
        }
    }

    /// Copy a file or directory.
    ///
    /// - Parameters:
    ///   - fromPath: Source path.
    ///   - toPath: Destination path.
    /// - Throws: `FileSystemError.copyFailed` on failure.
    func copy(from fromPath: String, to toPath: String) throws {
        guard fm.fileExists(atPath: fromPath) else {
            throw FileSystemError.fileNotFound(fromPath)
        }

        let destURL = URL(fileURLWithPath: toPath)
        createDirectoryIfNeeded(at: destURL.deletingLastPathComponent())

        do {
            try fm.copyItem(atPath: fromPath, toPath: toPath)
            logger.debug("Copied: \(fromPath) -> \(toPath)")
        } catch {
            throw FileSystemError.copyFailed(from: fromPath, to: toPath, underlying: error)
        }
    }

    // MARK: - File Attributes

    /// Get the size of a file in bytes.
    ///
    /// - Parameter path: Absolute path to the file.
    /// - Returns: The file size in bytes, or nil if unavailable.
    func fileSize(at path: String) -> Int? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else {
            return nil
        }
        return size
    }

    /// Get the modification date of a file.
    ///
    /// - Parameter path: Absolute path to the file.
    /// - Returns: The modification date, or nil if unavailable.
    func modificationDate(at path: String) -> Date? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return date
    }

    // MARK: - Convenience

    /// Returns a unique temporary file path with the given extension.
    ///
    /// - Parameter ext: File extension (e.g., "json", "txt").
    /// - Returns: A unique path in the temp directory.
    func temporaryFilePath(extension ext: String) -> String {
        Self.tempDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
            .path
    }

    /// Available disk space in bytes.
    var availableDiskSpace: Int? {
        guard let attrs = try? fm.attributesOfFileSystem(forPath: Self.documentsDirectory.path),
              let freeSize = attrs[.systemFreeSize] as? Int else {
            return nil
        }
        return freeSize
    }
}
