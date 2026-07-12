// PromptAssembler.swift
// CodingPad
//
// Builds the complete system prompt from multiple sections.
// Sections are ordered, deduplicated, and separated by markers.

import Foundation

// MARK: - PromptAssembler

/// Assembles the multi-section system prompt from tools, context, memories, and config.
///
/// The prompt is composed of 8 sections in order:
/// - **CACHEABLE** (stable across requests):
///   1. intro — Role definition and core capabilities
///   2. system — iOS/iPad/iSH environment
///   3. coding_style — Coding conventions
///   4. tools — Tool schemas and usage prompts
/// - **DYNAMIC** (change per request):
///   5. project — CLAUDE.md + git info
///   6. memory — Relevant memories
///   7. user_preferences — Language and output style
///   8. reminders — Active reminders and to-do items
///
/// Each section is wrapped with `=== SECTION: xxx ===` markers for clear separation.
struct PromptAssembler {

    /// Separator template used between sections.
    private static func sectionHeader(_ name: String) -> String {
        "=== SECTION: \(name) ==="
    }

    private static func sectionFooter(_ name: String) -> String {
        "=== END: \(name) ==="
    }

    // MARK: - Build

    /// Builds the complete system prompt string.
    ///
    /// - Parameters:
    ///   - tools: All registered agent tools (for schema and usage prompts).
    ///   - contextSegments: Context segments assembled by the ContextEngine.
    ///   - memories: Relevant memory entries loaded by the MemoryManager.
    ///   - config: The current agent configuration.
    ///   - reminders: Optional list of active reminders or to-do items.
    /// - Returns: The fully assembled system prompt string.
    func build(
        tools: [any AgentTool],
        contextSegments: [ContextSegment],
        memories: [MemoryEntry],
        config: AgentConfig,
        reminders: [String] = []
    ) -> String {
        let sections: [any PromptSection] = [
            // CACHEABLE
            IntroSection(),
            SystemSection(),
            CodingStyleSection(),
            ToolsSection(tools: tools),
            // DYNAMIC
            ProjectSection(contextSegments: contextSegments),
            MemorySection(memories: memories),
            UserPrefSection(config: config),
            ReminderSection(reminders: reminders),
        ]

        return assembleSections(sections)
    }

    /// Builds a minimal prompt with only the cacheable sections.
    /// Useful for pre-computing the stable portion of the prompt.
    func buildCacheableOnly(tools: [any AgentTool]) -> String {
        let sections: [any PromptSection] = [
            IntroSection(),
            SystemSection(),
            CodingStyleSection(),
            ToolsSection(tools: tools),
        ]

        return assembleSections(sections)
    }

    /// Builds only the dynamic sections for appending to a cached base prompt.
    func buildDynamicOnly(
        contextSegments: [ContextSegment],
        memories: [MemoryEntry],
        config: AgentConfig,
        reminders: [String] = []
    ) -> String {
        let sections: [any PromptSection] = [
            ProjectSection(contextSegments: contextSegments),
            MemorySection(memories: memories),
            UserPrefSection(config: config),
            ReminderSection(reminders: reminders),
        ]

        return assembleSections(sections)
    }

    // MARK: - Private

    /// Renders an array of sections into a single prompt string.
    private func assembleSections(_ sections: [any PromptSection]) -> String {
        var parts: [String] = []

        for section in sections {
            let content = section.render()

            // Skip empty sections entirely
            guard !content.isEmpty else { continue }

            let wrapped = [
                Self.sectionHeader(section.name),
                "",
                content,
                "",
                Self.sectionFooter(section.name),
            ].joined(separator: "\n")

            parts.append(wrapped)
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Prompt Statistics

extension PromptAssembler {

    /// Computes approximate statistics about the assembled prompt.
    struct PromptStats: Sendable {
        let totalCharacters: Int
        let estimatedTokens: Int
        let sectionCount: Int
        let cacheableSectionCount: Int
        let dynamicSectionCount: Int
    }

    /// Returns stats about a prompt built from the given inputs.
    func stats(
        tools: [any AgentTool],
        contextSegments: [ContextSegment],
        memories: [MemoryEntry],
        config: AgentConfig,
        reminders: [String] = []
    ) -> PromptStats {
        let sections: [any PromptSection] = [
            IntroSection(),
            SystemSection(),
            CodingStyleSection(),
            ToolsSection(tools: tools),
            ProjectSection(contextSegments: contextSegments),
            MemorySection(memories: memories),
            UserPrefSection(config: config),
            ReminderSection(reminders: reminders),
        ]

        let nonEmpty = sections.filter { !$0.render().isEmpty }
        let cacheableCount = nonEmpty.filter(\.isCacheable).count
        let dynamicCount = nonEmpty.count - cacheableCount

        let fullPrompt = build(
            tools: tools,
            contextSegments: contextSegments,
            memories: memories,
            config: config,
            reminders: reminders
        )

        return PromptStats(
            totalCharacters: fullPrompt.count,
            estimatedTokens: max(1, fullPrompt.count / 4),
            sectionCount: nonEmpty.count,
            cacheableSectionCount: cacheableCount,
            dynamicSectionCount: dynamicCount
        )
    }
}
