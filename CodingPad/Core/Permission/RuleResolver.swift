// RuleResolver.swift
// CodingPad
//
// Rule matching engine with glob patterns and priority resolution.
// Priority: explicit > wildcard > default.
// Tie-breaking: deny > ask > allow (most restrictive wins).

import Foundation

// MARK: - Rule Match Result

/// The result of resolving rules for a given resource.
/// Contains the matched effect and the specificity level.
struct RuleMatchResult: Sendable, Equatable {
    let effect: PolicyEffect
    let specificity: MatchSpecificity
    let reason: String?

    init(effect: PolicyEffect, specificity: MatchSpecificity, reason: String? = nil) {
        self.effect = effect
        self.specificity = specificity
        self.reason = reason
    }
}

// MARK: - Match Specificity

/// How specific a rule match is. Higher specificity wins.
/// Ordered: explicit > wildcard > default.
enum MatchSpecificity: Int, Comparable, Sendable {
    /// No rule matched — the default fallback.
    case `default` = 0
    /// A pattern with wildcards (e.g., "file:**").
    case wildcard = 1
    /// An explicit pattern with no wildcards (e.g., "file:/Users/test.txt").

    static func < (lhs: MatchSpecificity, rhs: MatchSpecificity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Rule Resolver

/// Resolves which rule applies to a given resource by matching glob patterns
/// and resolving conflicts via specificity and effect priority.
struct RuleResolver: Sendable {

    /// Resolves the best matching rule for a resource string among a list of rules.
    ///
    /// Algorithm:
    /// 1. Find all rules whose pattern matches the resource.
    /// 2. Among matched rules, find the highest specificity.
    /// 3. Among rules at that specificity, apply effect priority:
    ///    deny > ask > allow.
    ///
    /// - Parameters:
    ///   - resource: The resource string to match (e.g., "file:read:/path").
    ///   - rules: The list of policy rules to evaluate.
    /// - Returns: The resolved match result, or nil if no rules match.
    static func resolve(resource: String, rules: [PolicyRule]) -> RuleMatchResult? {
        // Collect all matching rules with their specificity
        var matchedRules: [(rule: PolicyRule, specificity: MatchSpecificity)] = []

        for rule in rules {
            if let specificity = matchSpecificity(pattern: rule.resourcePattern, resource: resource) {
                matchedRules.append((rule, specificity))
            }
        }

        guard !matchedRules.isEmpty else {
            return nil
        }

        // Find the highest specificity among matches
        let highestSpecificity = matchedRules.map(\.specificity).max()!

        // Filter to rules at the highest specificity
        let topRules = matchedRules.filter { $0.specificity == highestSpecificity }

        // Among top rules, apply effect priority: deny > ask > allow
        let bestRule = topRules.min { lhs, rhs in
            effectPriority(lhs.rule.effect) < effectPriority(rhs.rule.effect)
        }!

        return RuleMatchResult(
            effect: bestRule.rule.effect,
            specificity: bestRule.specificity,
            reason: bestRule.rule.reason
        )
    }

    /// Returns the priority of an effect for tie-breaking.
    /// Higher number = more restrictive = wins ties.
    /// deny (3) > ask (2) > allow (1).
    static func effectPriority(_ effect: PolicyEffect) -> Int {
        switch effect {
        case .deny:  return 3
        case .ask:   return 2
        case .allow: return 1
        }
    }

    // MARK: - Glob Matching

    /// Tests if a resource matches a glob pattern and returns the specificity.
    ///
    /// Glob syntax:
    /// - `*` matches any characters except `/`
    /// - `**` matches any characters including `/`
    /// - `?` matches a single character
    /// - All other characters match literally
    ///
    /// Returns nil if no match.
    /// Returns `.explicit` if the pattern contains no wildcards.
    /// Returns `.wildcard` if the pattern contains wildcards.
    static func matchSpecificity(pattern: String, resource: String) -> MatchSpecificity? {
        // If pattern is "*", it matches everything at wildcard level
        if pattern == "*" {
            return resource.isEmpty ? nil : .wildcard
        }

        let hasWildcards = pattern.contains("*") || pattern.contains("?")

        if globMatch(pattern: pattern, text: resource) {
            return hasWildcards ? .wildcard : .explicit
        }
        return nil
    }

    /// Performs glob pattern matching.
    /// `*` matches zero or more characters (not `/`).
    /// `**` matches zero or more characters including `/`.
    /// `?` matches a single character.
    static func globMatch(pattern: String, text: String) -> Bool {
        let patternChars = Array(pattern)
        let textChars = Array(text)
        return matchHelper(patternChars, 0, textChars, 0)
    }

    /// Recursive matching helper.
    private static func matchHelper(
        _ pattern: [Character],
        _ pIdx: Int,
        _ text: [Character],
        _ tIdx: Int
    ) -> Bool {
        let pLen = pattern.count
        let tLen = text.count

        // Base case: pattern exhausted
        if pIdx >= pLen {
            return tIdx >= tLen
        }

        // Check for ** (double star — matches everything including /)
        if pIdx + 1 < pLen && pattern[pIdx] == "*" && pattern[pIdx + 1] == "*" {
            // Skip extra stars
            var nextPIdx = pIdx + 2
            while nextPIdx < pLen && pattern[nextPIdx] == "*" {
                nextPIdx += 1
            }
            // ** at end of pattern matches everything remaining
            if nextPIdx >= pLen {
                return true
            }
            // Try to match ** with each possible suffix of text
            for skip in tIdx...tLen {
                if matchHelper(pattern, nextPIdx, text, skip) {
                    return true
                }
            }
            return false
        }

        // Single * (matches any chars except /)
        if pattern[pIdx] == "*" {
            var nextPIdx = pIdx + 1
            // Skip consecutive single stars
            while nextPIdx < pLen && pattern[nextPIdx] == "*" && !(nextPIdx + 1 < pLen && pattern[nextPIdx + 1] == "*") {
                nextPIdx += 1
            }
            // * at end of pattern matches remaining text in the same path segment
            if nextPIdx >= pLen {
                // Check remaining text has no /
                return !text[tIdx..<tLen].contains("/")
            }
            // Try matching * with increasing portions of text (within same segment)
            for skip in tIdx...tLen {
                // Stop at first / — * doesn't cross segments
                if skip > tIdx && skip <= tLen && skip - 1 < tLen && text[skip - 1] == "/" && tIdx < skip - 1 {
                    break
                }
                if skip < tLen && text[skip] == "/" {
                    // Allow matching up to and including this position only if next pattern char is /
                    if matchHelper(pattern, nextPIdx, text, skip) {
                        return true
                    }
                    break
                }
                if matchHelper(pattern, nextPIdx, text, skip) {
                    return true
                }
            }
            return false
        }

        // Base case: text exhausted but pattern remains (non-wildcard)
        if tIdx >= tLen {
            return false
        }

        // ? matches any single character
        if pattern[pIdx] == "?" {
            return matchHelper(pattern, pIdx + 1, text, tIdx + 1)
        }

        // Literal character match
        if pattern[pIdx] == text[tIdx] {
            return matchHelper(pattern, pIdx + 1, text, tIdx + 1)
        }

        return false
    }
}

// MARK: - Convenience

extension RuleResolver {

    /// Quick check: does the resource match the pattern at all?
    static func matches(pattern: String, resource: String) -> Bool {
        matchSpecificity(pattern: pattern, resource: resource) != nil
    }
}
