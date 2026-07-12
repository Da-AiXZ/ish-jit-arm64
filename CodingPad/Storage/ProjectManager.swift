// ProjectManager.swift
// CodingPad
//
// Manages project lifecycle: listing, scanning, switching active project,
// and persisting project metadata.

import Foundation
import os

// MARK: - Project Info

/// Immutable snapshot of a project's metadata.
struct ProjectInfo: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let path: String
    let createdAt: Date
    var lastOpenedAt: Date

    /// Whether this project's directory still exists on disk.
    var isValid: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }

    /// Create a new ProjectInfo with an updated lastOpenedAt (immutable pattern).
    func withLastOpened(_ date: Date = Date()) -> ProjectInfo {
        ProjectInfo(
            id: id,
            name: name,
            path: path,
            createdAt: createdAt,
            lastOpenedAt: date
        )
    }
}

// MARK: - Project Manager Errors

enum ProjectManagerError: Error, LocalizedError {
    case projectNotFound(String)
    case directoryNotFound(String)
    case duplicateProject(String)
    case persistenceFailed(Error)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "Project '\(id)' not found in the project list."
        case .directoryNotFound(let path):
            return "Directory does not exist: \(path)"
        case .duplicateProject(let path):
            return "A project at '\(path)' is already registered."
        case .persistenceFailed(let error):
            return "Failed to save project list: \(error.localizedDescription)"
        }
    }
}

// MARK: - Project Manager

/// Manages the list of known projects and the currently active project.
///
/// Thread-safe via `actor`. Projects are persisted as JSON
/// in the app's Documents directory.
actor ProjectManager {

    // MARK: - Singleton

    static let shared = ProjectManager()

    // MARK: - State

    private var projects: [ProjectInfo] = []
    private var activeProjectId: String?
    private let logger = Logger(subsystem: "com.codingpad", category: "ProjectManager")

    /// File path for persisting the project list.
    private var persistencePath: String {
        FileSystemService.appSupportDirectory
            .appendingPathComponent("projects.json").path
    }

    // MARK: - Initialization

    private init() {}

    /// Load the project list from disk. Call once on app startup.
    func load() {
        let url = URL(fileURLWithPath: persistencePath)

        guard FileManager.default.fileExists(atPath: persistencePath),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([ProjectInfo].self, from: data) else {
            logger.info("No saved project list found — starting fresh")
            return
        }

        projects = loaded
        logger.info("Loaded \(loaded.count) projects from disk")
    }

    // MARK: - Queries

    /// Returns all known projects, sorted by last opened date (most recent first).
    func allProjects() -> [ProjectInfo] {
        projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Find a project by its ID.
    func project(id: String) -> ProjectInfo? {
        projects.first { $0.id == id }
    }

    /// Find a project by its path.
    func project(at path: String) -> ProjectInfo? {
        projects.first { $0.path == path }
    }

    /// Returns the currently active project, if any.
    func activeProject() -> ProjectInfo? {
        guard let id = activeProjectId else { return nil }
        return project(id: id)
    }

    /// Returns only projects whose directories still exist on disk.
    func validProjects() -> [ProjectInfo] {
        allProjects().filter(\.isValid)
    }

    // MARK: - Mutations

    /// Add a new project by scanning a directory path.
    ///
    /// - Parameter path: The absolute path to the project directory.
    /// - Returns: The created ProjectInfo.
    @discardableResult
    func addProject(at path: String) throws -> ProjectInfo {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProjectManagerError.directoryNotFound(path)
        }

        if projects.contains(where: { $0.path == path }) {
            throw ProjectManagerError.duplicateProject(path)
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let project = ProjectInfo(name: name, path: path)
        projects.append(project)

        try persist()
        logger.info("Added project: \(name) at \(path)")

        return project
    }

    /// Switch the active project.
    ///
    /// - Parameter id: The project ID to activate.
    /// - Throws: If the project is not found.
    func setActiveProject(id: String) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectManagerError.projectNotFound(id)
        }

        activeProjectId = id
        projects[index] = projects[index].withLastOpened()

        try persist()
        logger.info("Active project set to: \(projects[index].name)")
    }

    /// Switch the active project by path. Adds it if not already known.
    ///
    /// - Parameter path: The project directory path.
    /// - Returns: The activated ProjectInfo.
    @discardableResult
    func setActiveProject(at path: String) throws -> ProjectInfo {
        let project: ProjectInfo
        if let existing = self.project(at: path) {
            project = existing
        } else {
            project = try addProject(at: path)
        }

        try setActiveProject(id: project.id)
        return project
    }

    /// Remove a project from the list. Does NOT delete the directory.
    ///
    /// - Parameter id: The project ID to remove.
    func removeProject(id: String) throws {
        projects = projects.filter { $0.id != id }

        if activeProjectId == id {
            activeProjectId = nil
        }

        try persist()
        logger.info("Removed project: \(id)")
    }

    /// Remove all projects whose directories no longer exist on disk.
    func pruneInvalidProjects() throws {
        let before = projects.count
        projects = projects.filter(\.isValid)
        let removed = before - projects.count

        if removed > 0 {
            try persist()
            logger.info("Pruned \(removed) invalid project(s)")
        }
    }

    // MARK: - Directory Scanning

    /// Scan a project directory to detect its type and contents.
    ///
    /// - Parameter path: The project directory path.
    /// - Returns: A list of notable files/directories found.
    nonisolated func scanDirectory(at path: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }

        // Well-known project markers
        let markers: Set<String> = [
            "Package.swift",       // Swift Package
            "CLAUDE.md",           // Claude Code project
            ".git",                // Git repository
            "package.json",        // Node.js
            "Cargo.toml",          // Rust
            "pyproject.toml",      // Python
            "go.mod",              // Go
            "build.gradle",        // Gradle
            "pom.xml",             // Maven
            "Makefile",            // Make
        ]

        return contents.filter { markers.contains($0) }
    }

    // MARK: - Persistence

    /// Save the current project list to disk.
    private func persist() throws {
        do {
            let data = try JSONEncoder().encode(projects)
            let url = URL(fileURLWithPath: persistencePath)

            // Ensure parent directory exists
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )

            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to persist projects: \(error.localizedDescription)")
            throw ProjectManagerError.persistenceFailed(error)
        }
    }
}
