// PolicyConfig.swift
// CodingPad
//
// JSON-based policy configuration for the ABAC permission engine.
// Defines rule structures, parsing, and default policy generation.

import Foundation

// MARK: - Policy Effect

/// The effect a policy rule has when matched.
/// Three-valued: allow, ask (require user confirmation), deny.
enum PolicyEffect: String, Codable, Sendable {
    case allow
    case ask
    case deny
}

// MARK: - Policy Rule

/// A single policy rule mapping a resource pattern to an effect.
/// Immutable value type — modifications create new instances.
struct PolicyRule: Codable, Sendable, Equatable {
    /// The resource pattern to match (glob-style, e.g. "file:/Users/**").
    let resourcePattern: String
    /// The effect when this rule matches.
    let effect: PolicyEffect
    /// Optional human-readable reason shown to the user.
    let reason: String?

    init(resourcePattern: String, effect: PolicyEffect, reason: String? = nil) {
        self.resourcePattern = resourcePattern
        self.effect = effect
        self.reason = reason
    }
}

// MARK: - Policy Scope Rules

/// All rules for a single permission scope, keyed by scope name.
struct PolicyScopeRules: Codable, Sendable {
    /// Ordered list of rules for this scope. Earlier rules take precedence.
    let rules: [PolicyRule]

    init(rules: [PolicyRule]) {
        self.rules = rules
    }
}

// MARK: - Policy Document

/// A complete policy document containing rules for all scopes.
struct PolicyDocument: Codable, Sendable {
    let scopes: [String: PolicyScopeRules]

    init(scopes: [String: PolicyScopeRules]) {
        self.scopes = scopes
    }
}

// MARK: - Policy Parsing Error

enum PolicyParseError: Error, LocalizedError {
    case invalidJSON(String)
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Failed to parse policy JSON: \(detail)"
        case .missingKey(let key):
            return "Policy JSON is missing required key: \(key)"
        }
    }
}

// MARK: - Policy Config

/// Manages loading and storing policy documents.
/// Provides immutable access to the current policy.
struct PolicyConfig: Sendable {
    let document: PolicyDocument

    init(document: PolicyDocument) {
        self.document = document
    }

    /// Returns the rules for a given scope, or an empty list if not configured.
    func rules(for scope: PermissionScope) -> [PolicyRule] {
        document.scopes[scope.rawValue]?.rules ?? []
    }

    /// Load a policy from a JSON data blob.
    static func from(jsonData: Data) throws -> PolicyConfig {
        do {
            let document = try JSONDecoder().decode(PolicyDocument.self, from: jsonData)
            return PolicyConfig(document: document)
        } catch let error as DecodingError {
            throw PolicyParseError.invalidJSON(error.localizedDescription)
        } catch {
            throw PolicyParseError.invalidJSON(error.localizedDescription)
        }
    }

    /// Load a policy from a JSON string.
    static func from(jsonString: String) throws -> PolicyConfig {
        guard let data = jsonString.data(using: .utf8) else {
            throw PolicyParseError.invalidJSON("Invalid UTF-8 string")
        }
        return try from(jsonData: data)
    }
}

// MARK: - Default Policy

extension PolicyConfig {

    /// Builds a sensible default policy for each scope.
    /// Used when no external JSON policy is provided.
    static var defaultPolicy: PolicyConfig {
        let document = PolicyDocument(scopes: [
            PermissionScope.tool.rawValue: PolicyScopeRules(rules: [
                PolicyRule(resourcePattern: "*", effect: .ask,
                           reason: "Tool execution requires confirmation by default."),
            ]),

            PermissionScope.fs.rawValue: PolicyScopeRules(rules: [
                PolicyRule(resourcePattern: "read:**", effect: .allow,
                           reason: "File reads are allowed by default."),
                PolicyRule(resourcePattern: "write:**", effect: .ask,
                           reason: "File writes require confirmation."),
                PolicyRule(resourcePattern: "delete:**", effect: .deny,
                           reason: "File deletion is denied by default."),
            ]),

            PermissionScope.net.rawValue: PolicyScopeRules(rules: [
                PolicyRule(resourcePattern: "GET:**", effect: .allow,
                           reason: "GET requests are allowed."),
                PolicyRule(resourcePattern: "*:**", effect: .ask,
                           reason: "Non-GET network requests require confirmation."),
            ]),

            PermissionScope.secret.rawValue: PolicyScopeRules(rules: [
                PolicyRule(resourcePattern: "*", effect: .deny,
                           reason: "Secret access is denied by default."),
            ]),

            PermissionScope.shell.rawValue: PolicyScopeRules(rules: [
                // Read-only commands are allowed
                PolicyRule(resourcePattern: "shell:read:*", effect: .allow,
                           reason: "Read-only shell commands are allowed."),
                // Write commands require confirmation
                PolicyRule(resourcePattern: "shell:write:*", effect: .ask,
                           reason: "Write shell commands require confirmation."),
                // Dangerous commands are denied
                PolicyRule(resourcePattern: "shell:dangerous:*", effect: .deny,
                           reason: "Dangerous shell commands are denied."),
                // Fallback
                PolicyRule(resourcePattern: "*", effect: .ask,
                           reason: "Unknown shell command classification — requires confirmation."),
            ]),
        ])
        return PolicyConfig(document: document)
    }
}

// MARK: - JSON Serialization

extension PolicyConfig {

    /// Encodes the policy document to JSON data.
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Encodes the policy document to a JSON string.
    func toJSONString() throws -> String {
        let data = try toJSON()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
