// CompactTool.swift
// CodingPad
//
// Triggers context compression to reclaim context window space.

import Foundation

// MARK: - CompactTool

/// Triggers context compression to reclaim context window space.
///
/// This is a placeholder interface that signals the agent loop to perform
/// context compaction. The actual compression logic lives in the ContextEngine.
struct CompactTool: AgentTool {
    let name = "compact"

    let description = "Triggers context compression to reclaim context window space. Use when the conversation is getting long."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [:],
        required: []
    )

    let usagePrompt = """
    Triggers context compression to reclaim context window space.

    - Use when the conversation history is getting long and approaching context limits.
    - No parameters required.
    - The actual compression is handled by the ContextEngine.
    - After compaction, older messages are summarized to free up token budget.
    - This is a signal to the agent loop; the tool itself returns a confirmation.
    """

    let isReadOnly = true
    let isConcurrencySafe = false

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        .allow
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        // This tool acts as a signal to the agent loop.
        // The actual compaction is performed by the ContextEngine
        // when it processes this tool result and sees the metadata flag.
        return ToolResult(
            content: "Context compression requested. The agent loop will compact conversation history on the next cycle.",
            metadata: ["action": "compact_requested"]
        )
    }
}
