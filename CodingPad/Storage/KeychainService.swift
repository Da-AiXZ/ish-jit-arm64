// KeychainService.swift
// CodingPad
//
// Secure storage for API keys and sensitive credentials using iOS Keychain.
// Thread-safe via serial dispatch queue. All operations are synchronous
// to simplify Keychain API usage.

import Foundation
import Security
import os

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain storage."
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        case .unexpectedData:
            return "Keychain returned unexpected data format."
        case .notFound:
            return "Item not found in Keychain."
        }
    }
}

// MARK: - KeychainService

/// Thread-safe wrapper around iOS Keychain Services.
///
/// Stores and retrieves string values (API keys, tokens) securely.
/// Uses `kSecClassGenericPassword` with a fixed service identifier.
///
/// Thread safety: all Keychain operations are serialized on a private
/// serial queue to prevent data races. The Keychain API itself is
/// thread-safe, but serialization avoids read-modify-write races
/// (e.g., check-then-add).
final class KeychainService: Sendable {

    // MARK: - Constants

    /// The Keychain service identifier for this app.
    static let serviceIdentifier = "com.codingpad.keychain"

    /// Well-known key for the primary API key.
    static let apiKeyIdentifier = "anthropic_api_key"

    // MARK: - Singleton

    /// Shared instance for the app.
    static let shared = KeychainService()

    // MARK: - Serial Queue

    /// Serial queue for thread-safe Keychain access.
    private let queue = DispatchQueue(label: "com.codingpad.keychain.queue")

    private let logger = Logger(subsystem: "com.codingpad", category: "KeychainService")

    init() {}

    // MARK: - Public API

    /// Store a string value in the Keychain.
    ///
    /// If an item with the same key already exists, it is updated.
    ///
    /// - Parameters:
    ///   - key: The identifier for the item.
    ///   - value: The string value to store.
    /// - Throws: `KeychainError` if the operation fails.
    func set(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try queue.sync {
            // Try to delete existing item first (ignore not-found)
            let deleteQuery = self.baseQuery(for: key)
            SecItemDelete(deleteQuery as CFDictionary)

            // Add the new item
            var addQuery = self.baseQuery(for: key)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                self.logger.error("Keychain set failed for key '\(key)': status \(status)")
                throw KeychainError.saveFailed(status)
            }

            self.logger.debug("Keychain value stored for key '\(key)'")
        }
    }

    /// Retrieve a string value from the Keychain.
    ///
    /// - Parameter key: The identifier for the item.
    /// - Returns: The stored string value, or `nil` if not found.
    func get(key: String) -> String? {
        queue.sync {
            var query = self.baseQuery(for: key)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                if status != errSecItemNotFound {
                    self.logger.warning("Keychain get failed for key '\(key)': status \(status)")
                }
                return nil
            }

            return value
        }
    }

    /// Delete an item from the Keychain.
    ///
    /// - Parameter key: The identifier for the item to delete.
    /// - Throws: `KeychainError` if the delete fails (not-found is not an error).
    func delete(key: String) throws {
        try queue.sync {
            let query = self.baseQuery(for: key)
            let status = SecItemDelete(query as CFDictionary)

            guard status == errSecSuccess || status == errSecItemNotFound else {
                self.logger.error("Keychain delete failed for key '\(key)': status \(status)")
                throw KeychainError.deleteFailed(status)
            }

            self.logger.debug("Keychain value deleted for key '\(key)'")
        }
    }

    /// Check whether an item exists in the Keychain.
    ///
    /// - Parameter key: The identifier to check.
    /// - Returns: `true` if the item exists.
    func exists(key: String) -> Bool {
        get(key: key) != nil
    }

    /// Delete all items for this service from the Keychain.
    func deleteAll() throws {
        try queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.serviceIdentifier,
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                self.logger.error("Keychain deleteAll failed: status \(status)")
                throw KeychainError.deleteFailed(status)
            }

            self.logger.debug("All Keychain items deleted for service '\(Self.serviceIdentifier)'")
        }
    }

    // MARK: - Private Helpers

    /// Build the base Keychain query dictionary for a given key.
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: key,
        ]
    }
}
