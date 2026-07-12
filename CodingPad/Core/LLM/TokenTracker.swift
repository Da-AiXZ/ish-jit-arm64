// TokenTracker.swift
// CodingPad
//
// Tracks token usage and cost across a session. Thread-safe via `actor`.

import Foundation

// MARK: - Pricing

/// Per-model pricing for token usage, in USD per million tokens.
///
/// Values are based on published Anthropic API pricing as of 2025.
/// Cache read tokens are significantly cheaper than regular input tokens;
/// cache creation tokens carry a premium over regular input tokens.
struct ModelPricing: Sendable {

    /// Price per 1M input tokens (standard, non-cached).
    let inputPerMillion: Double
    /// Price per 1M output tokens.
    let outputPerMillion: Double
    /// Price per 1M cache-read input tokens.
    let cacheReadPerMillion: Double
    /// Price per 1M cache-creation input tokens.
    let cacheCreationPerMillion: Double

    /// Known pricing for Anthropic models.
    ///
    /// Source: https://www.anthropic.com/pricing
    static let knownModels: [String: ModelPricing] = [
        // Claude Opus 4 — premium tier
        "claude-opus-4-8": ModelPricing(
            inputPerMillion: 15.0,
            outputPerMillion: 75.0,
            cacheReadPerMillion: 1.50,
            cacheCreationPerMillion: 18.75
        ),
        "claude-opus-4": ModelPricing(
            inputPerMillion: 15.0,
            outputPerMillion: 75.0,
            cacheReadPerMillion: 1.50,
            cacheCreationPerMillion: 18.75
        ),
        // Claude Sonnet 4 — balanced tier
        "claude-sonnet-4-6": ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75
        ),
        "claude-sonnet-4": ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75
        ),
        // Claude Haiku 4.5 — fast tier
        "claude-haiku-4-5": ModelPricing(
            inputPerMillion: 1.0,
            outputPerMillion: 5.0,
            cacheReadPerMillion: 0.10,
            cacheCreationPerMillion: 1.25
        ),
        // Fallback for older naming conventions
        "claude-3-5-sonnet-20241022": ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75
        ),
        "claude-3-5-haiku-20241022": ModelPricing(
            inputPerMillion: 0.80,
            outputPerMillion: 4.0,
            cacheReadPerMillion: 0.08,
            cacheCreationPerMillion: 1.0
        )
    ]

    /// Returns pricing for a given model ID, falling back to Sonnet-tier
    /// pricing if the model is not explicitly listed.
    static func pricing(for modelId: String) -> ModelPricing {
        if let exact = knownModels[modelId] {
            return exact
        }

        // Try prefix matching for versioned model IDs (e.g., "claude-opus-4-8-20250115").
        for (key, value) in knownModels {
            if modelId.hasPrefix(key) {
                return value
            }
        }

        // Default: Sonnet-tier pricing as a reasonable fallback.
        return ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75
        )
    }
}

// MARK: - Session Usage Summary

/// An immutable snapshot of cumulative token usage and cost for a session.
struct SessionUsageSnapshot: Sendable {
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheCreationTokens: Int
    let totalCacheReadTokens: Int
    let totalCost: Double
    let requestCount: Int
    let modelId: String

    /// Total tokens consumed (input + output).
    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Effective input tokens (standard input + cache reads, since cache reads
    /// replace standard input tokens).
    var effectiveInputTokens: Int {
        totalInputTokens + totalCacheReadTokens
    }
}

// MARK: - Token Tracker Actor

/// Thread-safe, session-level tracker for token usage and cost.
///
/// Use this actor to accumulate `TokenUsage` values reported by the LLM
/// provider across multiple API calls in a single conversation session.
/// All mutations are serialized through the actor, ensuring safe concurrent
/// access from multiple tasks.
actor TokenTracker {

    // MARK: - Stored State

    private(set) var accumulatedInputTokens: Int = 0
    private(set) var accumulatedOutputTokens: Int = 0
    private(set) var accumulatedCacheCreationTokens: Int = 0
    private(set) var accumulatedCacheReadTokens: Int = 0
    private(set) var requestCount: Int = 0
    private(set) var totalCost: Double = 0.0

    /// The model ID used for pricing lookups.
    private let modelId: String

    /// Cached pricing for the model, computed once at init.
    private let pricing: ModelPricing

    // MARK: - Initialization

    /// Creates a tracker for the specified model.
    /// - Parameter modelId: The model identifier (e.g., "claude-opus-4-8").
    init(modelId: String) {
        self.modelId = modelId
        self.pricing = ModelPricing.pricing(for: modelId)
    }

    // MARK: - Recording Usage

    /// Records a single API call's token usage and updates the cumulative cost.
    /// - Parameter usage: Token usage from the API response.
    func record(usage: TokenUsage) {
        accumulatedInputTokens += usage.inputTokens
        accumulatedOutputTokens += usage.outputTokens
        accumulatedCacheCreationTokens += usage.cacheCreationInputTokens
        accumulatedCacheReadTokens += usage.cacheReadInputTokens
        requestCount += 1

        let cost = calculateCost(
            input: usage.inputTokens,
            output: usage.outputTokens,
            cacheCreation: usage.cacheCreationInputTokens,
            cacheRead: usage.cacheReadInputTokens
        )
        totalCost += cost
    }

    // MARK: - Snapshot

    /// Returns an immutable snapshot of the current cumulative usage.
    func snapshot() -> SessionUsageSnapshot {
        SessionUsageSnapshot(
            totalInputTokens: accumulatedInputTokens,
            totalOutputTokens: accumulatedOutputTokens,
            totalCacheCreationTokens: accumulatedCacheCreationTokens,
            totalCacheReadTokens: accumulatedCacheReadTokens,
            totalCost: totalCost,
            requestCount: requestCount,
            modelId: modelId
        )
    }

    // MARK: - Reset

    /// Resets all counters to zero (e.g., when starting a new session).
    func reset() {
        accumulatedInputTokens = 0
        accumulatedOutputTokens = 0
        accumulatedCacheCreationTokens = 0
        accumulatedCacheReadTokens = 0
        requestCount = 0
        totalCost = 0.0
    }

    // MARK: - Cost Calculation

    /// Calculates the cost in USD for a single API call.
    private func calculateCost(
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> Double {
        let inputCost = Double(input) * pricing.inputPerMillion / 1_000_000
        let outputCost = Double(output) * pricing.outputPerMillion / 1_000_000
        let cacheCreationCost = Double(cacheCreation) * pricing.cacheCreationPerMillion / 1_000_000
        let cacheReadCost = Double(cacheRead) * pricing.cacheReadPerMillion / 1_000_000

        return inputCost + outputCost + cacheCreationCost + cacheReadCost
    }
}

// MARK: - Formatting Extensions

extension SessionUsageSnapshot {

    /// Formats the total cost as a human-readable USD string.
    /// - Parameter includeCents: If `true`, always shows 2 decimal places.
    ///   If `false`, uses adaptive precision (e.g., "$0.012" for small amounts).
    func formattedCost(includeCents: Bool = false) -> String {
        if includeCents {
            return String(format: "$%.2f", totalCost)
        }

        // For very small amounts, show more precision.
        if totalCost < 0.01 {
            return String(format: "$%.4f", totalCost)
        }
        return String(format: "$%.2f", totalCost)
    }

    /// A short summary string suitable for a status bar or debug panel.
    var summary: String {
        let tokens = totalTokens
        let cost = formattedCost(includeCents: false)
        return "\(tokens) tokens · \(cost)"
    }
}
