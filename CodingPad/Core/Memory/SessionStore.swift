// SessionStore.swift
// CodingPad
//
// JSON file-based session persistence.
// Stores complete conversation sessions (messages + metadata) as JSON files.
// Storage path: ~/Documents/CodingPad/sessions/

import Foundation
import os

// MARK: - SessionStore Errors

enum SessionStoreError: Error, LocalizedError {
    case sessionNotFound(String)
    case saveFailed(String)
    case loadFailed(String)
    case decodingFailed(String)
    case directoryAccessFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .saveFailed(let detail):
            return "Failed to save session: \(detail)"
        case .loadFailed(let detail):
            return "Failed to load session: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode session data: \(detail)"
        case .directoryAccessFailed(let path):
            return "Cannot access sessions directory: \(path)"
        }
    }
}

// MARK: - Persisted Session Data

/// The complete data model for a persisted session, combining
/// Session metadata with the full message history.
struct PersistedSession: Codable, Sendable {
    let session: Session
    let messages: [Message]
    let compactSummary: String?

    init(
        session: Session,
        messages: [Message],
        compactSummary: String? = nil
    ) {
        self.session = session
        self.messages = messages
        self.compactSummary = compactSummary
    }
}

// MARK: - Session Summary

/// A lightweight summary of a session for listing purposes.
/// Avoids loading the full message history.
struct SessionSummary: Identifiable, Sendable {
    let id: String
    let title: String?
    let projectPath: String?
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
}

// MARK: - SessionStore

/// Persists and manages conversation sessions as JSON files on disk.
///
/// Each session is stored as `{session_id}.json` in the sessions directory.
/// The store supports CRUD operations, listing, and cleanup of old sessions.
actor SessionStore {

    /// Base directory for session storage.
    private let baseDirectory: String

    /// Maximum number of sessions to retain.
    private static let maxSessions = 100

    /// JSON encoder configured for readable output.
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    /// JSON decoder matching the encoder configuration.
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.codingpad", category: "SessionStore")

    init(
        baseDirectory: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        if let dir = baseDirectory {
            self.baseDirectory = dir
        } else {
            let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
                ?? NSTemporaryDirectory()
            self.baseDirectory = (docs as NSString).appendingPathComponent("CodingPad/sessions")
        }
    }

    // MARK: - Save

    /// Saves a complete session (metadata + messages) to disk.
    func save(_ persisted: PersistedSession) async throws {
        ensureDirectoryExists()

        let filePath = sessionFilePath(for: persisted.session.id)

        do {
            let data = try encoder.encode(persisted)
            try data.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
            logger.info("Saved session \(persisted.session.id) (\(persisted.messages.count) messages)")
        } catch let error as EncodingError {
            throw SessionStoreError.saveFailed("Encoding error: \(error.localizedDescription)")
        } catch {
            throw SessionStoreError.saveFailed(error.localizedDescription)
        }

        // Enforce session limit
        try await enforceSessionLimit()
    }

    /// Quick save: creates a PersistedSession from components and saves it.
    func save(
        session: Session,
        messages: [Message],
        compactSummary: String? = nil
    ) async throws {
        let persisted = PersistedSession(
            session: session,
            messages: messages,
            compactSummary: compactSummary
        )
        try await save(persisted)
    }

    // MARK: - Load

    /// Loads a complete session by ID.
    func load(sessionId: String) async throws -> PersistedSession {
        let filePath = sessionFilePath(for: sessionId)

        guard fileManager.fileExists(atPath: filePath) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let persisted = try decoder.decode(PersistedSession.self, from: data)
            logger.debug("Loaded session \(sessionId)")
            return persisted
        } catch let error as DecodingError {
            throw SessionStoreError.decodingFailed("Session \(sessionId): \(error.localizedDescription)")
        } catch {
            throw SessionStoreError.loadFailed(error.localizedDescription)
        }
    }

    // MARK: - List

    /// Returns summaries of all stored sessions, sorted by most recent first.
    func listSessions() async -> [SessionSummary] {
        ensureDirectoryExists()

        guard let files = try? fileManager.contentsOfDirectory(atPath: baseDirectory) else {
            return []
        }

        var summaries: [SessionSummary] = []

        for filename in files where filename.hasSuffix(".json") {
            let sessionId = String(filename.dropLast(5)) // Remove .json
            if let summary = loadSessionSummary(sessionId: sessionId) {
                summaries.append(summary)
            }
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns the number of stored sessions.
    func sessionCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(atPath: baseDirectory) else {
            return 0
        }
        return files.filter { $0.hasSuffix(".json") }.count
    }

    // MARK: - Delete

    /// Deletes a single session by ID.
    func delete(sessionId: String) async throws {
        let filePath = sessionFilePath(for: sessionId)

        guard fileManager.fileExists(atPath: filePath) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }

        do {
            try fileManager.removeItem(atPath: filePath)
            logger.info("Deleted session \(sessionId)")
        } catch {
            throw SessionStoreError.saveFailed("Delete failed: \(error.localizedDescription)")
        }
    }

    /// Deletes all sessions.
    func deleteAll() async throws {
        guard let files = try? fileManager.contentsOfDirectory(atPath: baseDirectory) else {
            return
        }

        for filename in files where filename.hasSuffix(".json") {
            let filePath = (baseDirectory as NSString).appendingPathComponent(filename)
            try? fileManager.removeItem(atPath: filePath)
        }

        logger.info("Deleted all sessions")
    }

    // MARK: - Session Existence

    /// Checks whether a session with the given ID exists on disk.
    func exists(sessionId: String) -> Bool {
        fileManager.fileExists(atPath: sessionFilePath(for: sessionId))
    }

    // MARK: - Private Helpers

    /// Returns the full file path for a session ID.
    private func sessionFilePath(for sessionId: String) -> String {
        (baseDirectory as NSString).appendingPathComponent("\(sessionId).json")
    }

    /// Ensures the sessions directory exists.
    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: baseDirectory) {
            try? fileManager.createDirectory(
                atPath: baseDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    /// Loads just the metadata of a session (without full message history parsing).
    private func loadSessionSummary(sessionId: String) -> SessionSummary? {
        let filePath = sessionFilePath(for: sessionId)

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let persisted = try? decoder.decode(PersistedSession.self, from: data) else {
            return nil
        }

        return SessionSummary(
            id: persisted.session.id,
            title: persisted.session.title,
            projectPath: persisted.session.projectPath,
            createdAt: persisted.session.createdAt,
            updatedAt: persisted.session.updatedAt,
            messageCount: persisted.session.messageCount
        )
    }

    /// Enforces the maximum number of stored sessions by deleting the oldest.
    private func enforceSessionLimit() async throws {
        let sessions = await listSessions()

        guard sessions.count > Self.maxSessions else { return }

        // Sort by updatedAt ascending (oldest first), delete excess
        let toDelete = sessions
            .sorted { $0.updatedAt < $1.updatedAt }
            .prefix(sessions.count - Self.maxSessions)

        for session in toDelete {
            try? await delete(sessionId: session.id)
            logger.info("Auto-deleted old session \(session.id)")
        }
    }
}
