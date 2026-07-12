// MemoryManager.swift
// CodingPad
//
// Three-layer memory management system:
// - Long-term: MEMORY.md index + individual .md files in ~/Documents/CodingPad/memory/
// - Project: CLAUDE.md files (managed by ClaudeMDScanner)
// - Session: Per-session JSON in ~/Documents/CodingPad/sessions/

import Foundation
import os

// MARK: - MemoryManager Errors

enum MemoryManagerError: Error, LocalizedError {
    case memoryNotFound(String)
    case saveFailed(String)
    case indexCorrupted(String)
    case storageFull
    case invalidMemoryName(String)

    var errorDescription: String? {
        switch self {
        case .memoryNotFound(let id):
            return "Memory entry not found: \(id)"
        case .saveFailed(let detail):
            return "Failed to save memory: \(detail)"
        case .indexCorrupted(let detail):
            return "Memory index corrupted: \(detail)"
        case .storageFull:
            return "Memory storage is full. Consider compacting old entries."
        case .invalidMemoryName(let name):
            return "Invalid memory name: \(name). Use kebab-case (e.g., 'user-preferences')."
        }
    }
}

// MARK: - MemoryManager

/// Manages three layers of persistent memory:
///
/// 1. **Long-term memory**: Indexed in `MEMORY.md`, each entry stored as
///    an individual `.md` file in the memory directory. Survives across
///    all sessions and projects.
/// 2. **Project memory**: CLAUDE.md files within project directories.
///    Managed separately by `ClaudeMDScanner`.
/// 3. **Session memory**: Per-session JSON files managed by `SessionStore`.
///
/// The `MEMORY.md` index format:
/// ```
/// - [title](filename.md) — one-line description
/// ```
actor MemoryManager {

    /// Base directory for all memory storage.
    private let baseDirectory: String

    /// Maximum number of memory entries allowed.
    private static let maxEntries = 200

    /// Maximum single entry file size (100 KB).
    private static let maxEntrySize = 102_400

    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.codingpad", category: "MemoryManager")

    /// In-memory index of all entries (loaded from MEMORY.md + individual files).
    private var entries: [String: MemoryEntry] = [:]

    /// Whether the index has been loaded from disk.
    private var isLoaded = false

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
            self.baseDirectory = (docs as NSString).appendingPathComponent("CodingPad/memory")
        }
    }

    // MARK: - Public API

    /// Loads all memory entries from disk into the in-memory index.
    func loadMemories() async -> [MemoryEntry] {
        ensureDirectoryExists()
        entries = loadEntriesFromDisk()
        isLoaded = true
        logger.info("Loaded \(self.entries.count) memory entries")
        return Array(entries.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Saves a new or updated memory entry to disk and updates the index.
    func saveMemory(_ entry: MemoryEntry) async throws {
        // Validate name format
        guard isValidName(entry.name) else {
            throw MemoryManagerError.invalidMemoryName(entry.name)
        }

        // Check storage limits
        if entries[entry.id] == nil && entries.count >= Self.maxEntries {
            throw MemoryManagerError.storageFull
        }

        ensureDirectoryExists()

        // Write the individual entry file
        let filename = "\(entry.name).md"
        let filePath = (baseDirectory as NSString).appendingPathComponent(filename)

        let fileContent = formatEntryContent(entry)
        guard fileContent.utf8.count <= Self.maxEntrySize else {
            throw MemoryManagerError.saveFailed("Entry content exceeds maximum size of \(Self.maxEntrySize) bytes")
        }

        do {
            try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            throw MemoryManagerError.saveFailed(error.localizedDescription)
        }

        // Update in-memory index
        entries[entry.id] = entry

        // Rebuild MEMORY.md index file
        try rebuildIndex()

        logger.info("Saved memory entry: \(entry.name)")
    }

    /// Searches memory entries by matching query against name, description, and content.
    func searchMemories(query: String, limit: Int = 5) async -> [MemoryEntry] {
        if !isLoaded {
            _ = await loadMemories()
        }

        let queryLowered = query.lowercased()
        let queryTerms = queryLowered.split(separator: " ").map(String.init)

        // Score each entry by relevance
        let scored: [(entry: MemoryEntry, score: Int)] = entries.values.map { entry in
            var score = 0

            let nameLowered = entry.name.lowercased()
            let descLowered = entry.description.lowercased()
            let contentLowered = entry.content.lowercased()

            for term in queryTerms {
                // Name matches are highest priority
                if nameLowered.contains(term) { score += 10 }
                // Description matches
                if descLowered.contains(term) { score += 5 }
                // Content matches
                if contentLowered.contains(term) { score += 2 }
            }

            // Exact phrase match bonus
            if nameLowered.contains(queryLowered) { score += 15 }
            if descLowered.contains(queryLowered) { score += 8 }

            // Recency bonus (entries updated in last 7 days)
            let daysSinceUpdate = Date().timeIntervalSince(entry.updatedAt) / 86_400
            if daysSinceUpdate < 7 { score += 3 }

            return (entry, score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.entry)
    }

    /// Rebuilds the MEMORY.md index from the current in-memory entries.
    func updateIndex() async throws {
        if !isLoaded {
            _ = await loadMemories()
        }
        try rebuildIndex()
    }

    /// Deletes a memory entry by ID.
    func deleteMemory(id: String) async throws {
        guard let entry = entries[id] else {
            throw MemoryManagerError.memoryNotFound(id)
        }

        // Delete the file
        let filename = "\(entry.name).md"
        let filePath = (baseDirectory as NSString).appendingPathComponent(filename)
        if fileManager.fileExists(atPath: filePath) {
            try fileManager.removeItem(atPath: filePath)
        }

        // Remove from index
        entries.removeValue(forKey: id)
        try rebuildIndex()

        logger.info("Deleted memory entry: \(entry.name)")
    }

    /// Returns memory entries filtered by type.
    func memoriesByType(_ type: MemoryType) async -> [MemoryEntry] {
        if !isLoaded {
            _ = await loadMemories()
        }
        return entries.values
            .filter { $0.type == type }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns the total number of memory entries.
    func count() -> Int {
        entries.count
    }

    // MARK: - Private: Disk I/O

    /// Ensures the memory directory exists.
    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: baseDirectory) {
            try? fileManager.createDirectory(
                atPath: baseDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    /// Loads all .md files (excluding MEMORY.md) from the memory directory.
    private func loadEntriesFromDisk() -> [String: MemoryEntry] {
        guard let files = try? fileManager.contentsOfDirectory(atPath: baseDirectory) else {
            return [:]
        }

        var loaded: [String: MemoryEntry] = [:]

        for filename in files {
            guard filename.hasSuffix(".md"), filename != "MEMORY.md" else { continue }

            let filePath = (baseDirectory as NSString).appendingPathComponent(filename)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }

            if let entry = parseEntryFile(filename: filename, content: content) {
                loaded[entry.id] = entry
            }
        }

        return loaded
    }

    /// Parses a memory entry file into a MemoryEntry.
    ///
    /// Expected format:
    /// ```
    /// ---
    /// id: <uuid>
    /// type: <user|feedback|project|reference>
    /// description: <one-line>
    /// created: <ISO8601>
    /// updated: <ISO8601>
    /// ---
    /// <content body>
    /// ```
    private func parseEntryFile(filename: String, content: String) -> MemoryEntry? {
        let name = String(filename.dropLast(3)) // Remove .md

        // Try to parse frontmatter
        let parts = content.components(separatedBy: "---")
        if parts.count >= 3 {
            let frontmatter = parts[1]
            let body = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
            let meta = parseFrontmatter(frontmatter)

            let id = meta["id"] ?? UUID().uuidString
            let typeStr = meta["type"] ?? "reference"
            let description = meta["description"] ?? name
            let created = parseISO8601(meta["created"]) ?? Date()
            let updated = parseISO8601(meta["updated"]) ?? Date()

            return MemoryEntry(
                id: id,
                name: name,
                description: description,
                type: MemoryType(rawValue: typeStr) ?? .reference,
                content: body,
                createdAt: created,
                updatedAt: updated
            )
        }

        // Fallback: treat entire content as body
        return MemoryEntry(
            id: UUID().uuidString,
            name: name,
            description: name,
            type: .reference,
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Formats a MemoryEntry into a markdown file with frontmatter.
    private func formatEntryContent(_ entry: MemoryEntry) -> String {
        let created = formatISO8601(entry.createdAt)
        let updated = formatISO8601(entry.updatedAt)

        return """
            ---
            id: \(entry.id)
            type: \(entry.type.rawValue)
            description: \(entry.description)
            created: \(created)
            updated: \(updated)
            ---
            \(entry.content)
            """
    }

    /// Rebuilds the MEMORY.md index file from in-memory entries.
    private func rebuildIndex() throws {
        let indexPath = (baseDirectory as NSString).appendingPathComponent("MEMORY.md")

        let sortedEntries = entries.values.sorted { $0.name < $1.name }

        var lines: [String] = [
            "# Memory Index",
            "",
            "Auto-generated index of all memory entries.",
            "",
        ]

        // Group by type
        let grouped = Dictionary(grouping: sortedEntries, by: \.type)

        for memType in [MemoryType.user, .feedback, .project, .reference] {
            guard let typeEntries = grouped[memType], !typeEntries.isEmpty else { continue }

            lines.append("## \(memType.rawValue.capitalized)")
            lines.append("")
            for entry in typeEntries {
                lines.append("- [\(entry.name)](\(entry.name).md) — \(entry.description)")
            }
            lines.append("")
        }

        let indexContent = lines.joined(separator: "\n")
        try indexContent.write(toFile: indexPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Private: Utilities

    /// Validates a memory entry name (kebab-case).
    private func isValidName(_ name: String) -> Bool {
        let pattern = #"^[a-z0-9]+(-[a-z0-9]+)*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// Parses key-value frontmatter from a string block.
    private func parseFrontmatter(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    /// Parses an ISO 8601 date string.
    private func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    /// Formats a date as ISO 8601.
    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
