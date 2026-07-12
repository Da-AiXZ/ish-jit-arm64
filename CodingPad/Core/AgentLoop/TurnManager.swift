// TurnManager.swift
// CodingPad
//
// Manages turn counting, loop detection, and token accumulation
// for the agent harness loop.

import Foundation
import os

// MARK: - Turn Tracking Error

enum TurnManagerError: Error, LocalizedError {
    case maxTurnsReached(current: Int, max: Int)
    case loopDetected(tool: String, consecutiveCount: Int)

    var errorDescription: String? {
        switch self {
        case .maxTurnsReached(let current, let max):
            return "Maximum turns reached: \(current)/\(max). Stopping to prevent runaway execution."
        case .loopDetected(let tool, let count):
            return "Loop detected: tool '\(tool)' called \(count) times with identical parameters."
        }
    }
}

// MARK: - Tool Call Fingerprint

/// A fingerprint of a single tool call for loop detection.
/// Consists of tool name + input parameters.
struct ToolCallFingerprint: Hashable, Sendable {
    let toolName: String
    let inputHash: String

    init(toolName: String, input: ToolInput) {
        self.toolName = toolName
        // Hash the input parameters to a stable string representation
        var hasher = Hasher()
        for key in input.parameters.keys.sorted() {
            hasher.combine(key)
            hasher.combine(String(describing: input.parameters[key]))
        }
        self.inputHash = String(hasher.finalize())
    }

    init(toolName: String, inputHash: String) {
        self.toolName = toolName
        self.inputHash = inputHash
    }
}

// MARK: - Turn Statistics

/// Immutable snapshot of turn statistics.
struct TurnStatistics: Sendable {
    let currentTurn: Int
    let maxTurns: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheReadTokens: Int
    let totalCacheCreationTokens: Int
    let toolCallCount: Int

    var remainingTurns: Int {
        max(0, maxTurns - currentTurn)
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }
}

// MARK: - Turn Manager

/// Tracks turn state, detects repetitive loops, and accumulates token usage.
///
/// Loop detection: if the same tool is called with the same parameters
/// for `loopDetectionThreshold` (default 3) consecutive turns,
/// a loop is detected and the harness should stop.
///
/// Uses a class with internal locking rather than an actor because
/// the TurnManager is called synchronously within the agent loop's
/// stream processing pipeline.
final class TurnManager: @unchecked Sendable {
    private let lock = NSLock()

    private var currentTurn: Int = 0
    private let maxTurns: Int

    // Token accumulation
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var totalCacheReadTokens: Int = 0
    private var totalCacheCreationTokens: Int = 0

    // Tool call tracking
    private var toolCallCount: Int = 0
    private var recentFingerprints: [ToolCallFingerprint] = []
    private let loopDetectionThreshold: Int
    private let fingerprintHistorySize: Int

    private let logger = Logger(subsystem: "com.codingpad", category: "TurnManager")

    init(maxTurns: Int, loopDetectionThreshold: Int = 3) {
        self.maxTurns = maxTurns
        self.loopDetectionThreshold = loopDetectionThreshold
        self.fingerprintHistorySize = max(loopDetectionThreshold, 10)
    }

    // MARK: - Turn Management

    /// Increment the turn counter. Returns the new turn number.
    /// Throws if maxTurns is exceeded.
    @discardableResult
    func incrementTurn() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        currentTurn += 1

        if currentTurn > maxTurns {
            logger.warning("Max turns exceeded: \(self.currentTurn)/\(self.maxTurns)")
            throw TurnManagerError.maxTurnsReached(current: currentTurn, max: maxTurns)
        }

        logger.debug("Turn incremented to \(self.currentTurn)/\(self.maxTurns)")
        return currentTurn
    }

    /// Returns the current turn number (0-indexed before any increment).
    var currentTurnNumber: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentTurn
    }

    /// Returns true if we've reached the maximum turns.
    var hasReachedMaxTurns: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentTurn >= maxTurns
    }

    /// Returns true if there are remaining turns available.
    var hasRemainingTurns: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentTurn < maxTurns
    }

    // MARK: - Loop Detection

    /// Record a tool call fingerprint and check for loops.
    ///
    /// - Parameter fingerprint: The fingerprint of the tool call being recorded.
    /// - Returns: `true` if a loop is detected.
    @discardableResult
    func recordToolCall(fingerprint: ToolCallFingerprint) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        toolCallCount += 1
        recentFingerprints.append(fingerprint)

        // Trim history to avoid unbounded growth
        if recentFingerprints.count > fingerprintHistorySize {
            recentFingerprints.removeFirst(recentFingerprints.count - fingerprintHistorySize)
        }

        // Check for loop: last N fingerprints are identical
        if recentFingerprints.count >= loopDetectionThreshold {
            let recentSlice = recentFingerprints.suffix(loopDetectionThreshold)
            let first = recentSlice.first!
            let allSame = recentSlice.allSatisfy { $0 == first }

            if allSame {
                logger.error("Loop detected: tool '\(fingerprint.toolName)' repeated \(self.loopDetectionThreshold) times")
                return true
            }
        }

        return false
    }

    /// Convenience overload that creates a fingerprint from tool name + input.
    @discardableResult
    func recordToolCall(toolName: String, input: ToolInput) -> Bool {
        recordToolCall(fingerprint: ToolCallFingerprint(toolName: toolName, input: input))
    }

    /// Reset loop detection history (e.g., after a successful non-looping turn).
    func resetLoopDetection() {
        lock.lock()
        defer { lock.unlock() }
        recentFingerprints.removeAll()
    }

    // MARK: - Token Accumulation

    /// Add token usage from a completed API call.
    func addUsage(_ usage: TokenUsage) {
        lock.lock()
        defer { lock.unlock() }

        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        totalCacheReadTokens += usage.cacheReadInputTokens
        totalCacheCreationTokens += usage.cacheCreationInputTokens
    }

    /// Returns an immutable snapshot of current statistics.
    func snapshot() -> TurnStatistics {
        lock.lock()
        defer { lock.unlock() }

        return TurnStatistics(
            currentTurn: currentTurn,
            maxTurns: maxTurns,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCacheReadTokens: totalCacheReadTokens,
            totalCacheCreationTokens: totalCacheCreationTokens,
            toolCallCount: toolCallCount
        )
    }

    // MARK: - Reset

    /// Reset all counters for a new conversation.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        currentTurn = 0
        totalInputTokens = 0
        totalOutputTokens = 0
        totalCacheReadTokens = 0
        totalCacheCreationTokens = 0
        toolCallCount = 0
        recentFingerprints.removeAll()
    }
}
