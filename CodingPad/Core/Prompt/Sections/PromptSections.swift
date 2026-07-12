// PromptSections.swift
// CodingPad
//
// Defines individual sections that compose the system prompt.
// Sections are categorized as CACHEABLE (stable) or DYNAMIC (per-request).

import Foundation

// MARK: - Section Protocol

/// A named section of the system prompt with content and cacheability info.
protocol PromptSection: Sendable {
    /// The section identifier used in `=== SECTION: xxx ===` markers.
    var name: String { get }

    /// Whether this section's content is stable across requests.
    var isCacheable: Bool { get }

    /// Generates the section content.
    func render() -> String
}

// MARK: - CACHEABLE Sections

/// Section 1: Role definition and core capabilities.
struct IntroSection: PromptSection {
    let name = "intro"
    let isCacheable = true

    func render() -> String {
        """
        You are CodingPad, a powerful AI coding assistant built for iPad and iOS.

        You operate as an interactive agent that combines conversational intelligence with \
        direct access to the local filesystem and development tools. You can read, write, \
        search, and edit files, run commands, and manage projects — all from a mobile device.

        Your core capabilities:
        1. **File Operations**: Read, write, edit, and search files with precision. You see \
        the full file content and make surgical edits, never guessing at code you haven't read.
        2. **Code Intelligence**: Understand codebases deeply — trace dependencies, identify \
        patterns, and reason about architecture across multiple files.
        3. **Tool Use**: You have access to specialized tools and always use the right tool \
        for the job. You check permissions before destructive operations.
        4. **Memory**: You remember important context across sessions — user preferences, \
        project conventions, and ongoing work.
        5. **Iterative Problem Solving**: You break complex problems into steps, verify each \
        step works, and adapt when things don't go as expected.

        Operating principles:
        - **Read before writing**: Always read a file before editing it. Never guess at content.
        - **Verify changes**: After making edits, confirm the result is correct.
        - **Ask before destroying**: Never delete files, overwrite important data, or run \
        dangerous commands without explicit confirmation.
        - **Be precise**: Use exact string matching for edits. Show relevant code, not summaries.
        - **Stay focused**: Complete the current task before moving on. Track progress explicitly.
        - **Fail gracefully**: When something goes wrong, explain what happened and suggest fixes.

        You think step-by-step, explain your reasoning when helpful, and always prioritize \
        correctness over speed.
        """
    }
}

/// Section 2: iOS/iPad/iSH environment description.
struct SystemSection: PromptSection {
    let name = "system"
    let isCacheable = true

    func render() -> String {
        """
        Environment:
        - Platform: iPad / iOS (running CodingPad app)
        - Shell: iSH (Alpine Linux userland via x86 emulation)
        - Filesystem: App sandbox + iSH mount points
        - Limitations: No root access outside sandbox, no system package manager, \
        limited memory compared to desktop
        - File encoding: UTF-8 (default)
        - Path separator: / (POSIX)
        - Line endings: LF (Unix-style)

        iSH-specific notes:
        - Alpine Linux commands available (apk, ash, busybox utilities)
        - Git available if installed via apk
        - No GUI applications — terminal and file operations only
        - Performance varies — prefer efficient file operations over brute force
        """
    }
}

/// Section 3: Coding style and conventions.
struct CodingStyleSection: PromptSection {
    let name = "coding_style"
    let isCacheable = true

    func render() -> String {
        """
        Coding conventions:
        - Write clean, readable code with descriptive names
        - Keep functions small (<50 lines) and files focused (<800 lines)
        - Prefer immutability: use `let` over `var`, create new values instead of mutating
        - Handle errors explicitly at every level — never silently swallow errors
        - Validate inputs at system boundaries
        - Use constants or configuration for magic values
        - Avoid deep nesting (>4 levels) — prefer early returns
        - Follow the project's existing style and conventions when modifying code
        - Add comments only when the "why" isn't obvious from the code itself
        """
    }
}

/// Section 4: Available tools with schema and usage instructions.
struct ToolsSection: PromptSection {
    let name = "tools"
    let isCacheable = true

    let tools: [any AgentTool]

    func render() -> String {
        guard !tools.isEmpty else {
            return "No tools are currently available."
        }

        var lines: [String] = ["Available tools:\n"]

        for tool in tools {
            lines.append("### \(tool.name)")
            lines.append(tool.description)
            lines.append("")

            // Parameters
            let schema = tool.inputSchema
            if !schema.properties.isEmpty {
                lines.append("Parameters:")
                for (paramName, prop) in schema.properties.sorted(by: { $0.key < $1.key }) {
                    let requiredMark = schema.required.contains(paramName) ? " (required)" : ""
                    lines.append("  - \(paramName): \(prop.type)\(requiredMark) — \(prop.description)")
                }
                lines.append("")
            }

            // Usage prompt
            if !tool.usagePrompt.isEmpty {
                lines.append(tool.usagePrompt)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - DYNAMIC Sections

/// Section 5: Project-specific context (CLAUDE.md + git info).
struct ProjectSection: PromptSection {
    let name = "project"
    let isCacheable = false

    let contextSegments: [ContextSegment]

    func render() -> String {
        let projectSegments = contextSegments.filter { $0.level == .l1 || $0.level == .l2 }

        guard !projectSegments.isEmpty else {
            return "No active project context."
        }

        var parts: [String] = []
        for segment in projectSegments {
            parts.append("[\(segment.label)]")
            parts.append(segment.content)
        }

        return parts.joined(separator: "\n\n")
    }
}

/// Section 6: Relevant memories from the memory system.
struct MemorySection: PromptSection {
    let name = "memory"
    let isCacheable = false

    let memories: [MemoryEntry]

    func render() -> String {
        guard !memories.isEmpty else {
            return "No relevant memories loaded."
        }

        var lines: [String] = ["Relevant context from memory:\n"]

        for memory in memories {
            lines.append("[\(memory.type.rawValue)] \(memory.name): \(memory.description)")
            if !memory.content.isEmpty {
                lines.append(memory.content)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

/// Section 7: User preferences (language, output style).
struct UserPrefSection: PromptSection {
    let name = "user_preferences"
    let isCacheable = false

    let config: AgentConfig

    func render() -> String {
        var lines: [String] = []

        // Language preference
        switch config.language {
        case "zh-CN":
            lines.append("Respond in Simplified Chinese (简体中文) unless the user writes in another language.")
        case "zh-TW":
            lines.append("Respond in Traditional Chinese (繁體中文) unless the user writes in another language.")
        case "en":
            lines.append("Respond in English unless the user writes in another language.")
        case "ja":
            lines.append("Respond in Japanese (日本語) unless the user writes in another language.")
        default:
            lines.append("Respond in the same language the user uses.")
        }

        // Output style
        switch config.outputStyle {
        case "concise":
            lines.append("Be concise and direct. Avoid unnecessary preamble or filler.")
        case "detailed":
            lines.append("Provide detailed explanations with context and reasoning.")
        case "minimal":
            lines.append("Give the shortest correct answer. Skip explanations unless asked.")
        default:
            lines.append("Adapt your response length to the complexity of the question.")
        }

        return lines.joined(separator: "\n")
    }
}

/// Section 8: Reminders and active to-do items.
struct ReminderSection: PromptSection {
    let name = "reminders"
    let isCacheable = false

    let reminders: [String]

    func render() -> String {
        guard !reminders.isEmpty else {
            return ""
        }

        var lines: [String] = ["Active reminders:\n"]
        for (index, reminder) in reminders.enumerated() {
            lines.append("\(index + 1). \(reminder)")
        }

        return lines.joined(separator: "\n")
    }
}
