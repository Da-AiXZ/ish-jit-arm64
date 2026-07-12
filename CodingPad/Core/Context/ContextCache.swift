// ContextCache.swift
// CodingPad
//
// Generic memoize cache with TTL-based expiration.
// Thread-safe via actor isolation.

import Foundation

// MARK: - Cache Entry

/// An immutable entry stored in the cache with a creation timestamp and TTL.
private struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let createdAt: Date
    let ttl: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > ttl
    }
}

// MARK: - ContextCache

/// A thread-safe generic cache that stores values keyed by a hashable key.
///
/// Entries automatically expire after their specified TTL (time-to-live).
/// Designed for memoizing expensive context-loading operations such as
/// CLAUDE.md scanning and file structure analysis.
actor ContextCache<Key: Hashable & Sendable, Value: Sendable> {

    /// Internal storage mapping keys to cache entries.
    private var storage: [Key: CacheEntry<Value>] = [:]

    /// Default TTL applied when none is specified (5 minutes).
    private let defaultTTL: TimeInterval

    init(defaultTTL: TimeInterval = 300) {
        self.defaultTTL = defaultTTL
    }

    // MARK: - Read

    /// Retrieves a cached value if it exists and has not expired.
    /// Expired entries are evicted on access.
    func get(_ key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        if entry.isExpired {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    /// Returns the value for a key, or computes and stores it via the factory.
    /// Useful for memoize patterns where the factory is an async operation.
    func value(
        forKey key: Key,
        ttl: TimeInterval? = nil,
        using factory: () async -> Value
    ) async -> Value {
        if let cached = get(key) {
            return cached
        }
        let computed = await factory()
        set(key, value: computed, ttl: ttl)
        return computed
    }

    // MARK: - Write

    /// Stores a value with an optional custom TTL.
    func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? defaultTTL
        storage[key] = CacheEntry(
            value: value,
            createdAt: Date(),
            ttl: effectiveTTL
        )
    }

    // MARK: - Invalidation

    /// Removes a single entry from the cache.
    func invalidate(_ key: Key) {
        storage.removeValue(forKey: key)
    }

    /// Removes all expired entries, leaving only valid ones.
    func purgeExpired() {
        storage = storage.filter { !$0.value.isExpired }
    }

    /// Removes all entries from the cache.
    func clear() {
        storage.removeAll()
    }

    // MARK: - Inspection

    /// The current number of non-expired entries.
    func count() -> Int {
        purgeExpired()
        return storage.count
    }

    /// Returns all currently valid (non-expired) keys.
    func validKeys() -> [Key] {
        storage.compactMap { entry in
            entry.value.isExpired ? nil : entry.key
        }
    }
}
