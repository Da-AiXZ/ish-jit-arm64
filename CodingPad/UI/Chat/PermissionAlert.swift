// PermissionAlert.swift
// CodingPad
//
// SwiftUI modifier and model for permission confirmation dialogs.
// Shown when the AgentLoop encounters a tool that requires user approval.

import SwiftUI

// MARK: - Permission Request Model

/// Immutable value describing a pending permission prompt.
struct PermissionRequest: Identifiable, Sendable {
    let id: String
    let toolName: String
    let input: ToolInput
    let reason: String

    /// A human-readable summary of what the tool wants to do.
    var displaySummary: String {
        switch toolName {
        case "bash", "shell":
            return input.string(for: "command") ?? "Execute shell command"
        case "file_write":
            return "Write to: \(input.string(for: "file_path") ?? "unknown file")"
        case "file_edit":
            return "Edit: \(input.string(for: "file_path") ?? "unknown file")"
        case "web_fetch":
            return "Fetch: \(input.string(for: "url") ?? "unknown URL")"
        default:
            return "Execute tool: \(toolName)"
        }
    }
}

// MARK: - Permission Alert View

/// A modal card shown when a tool requires user confirmation.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────┐
/// │ 🔧 BashTool needs confirmation   │
/// │                                  │
/// │ Execute: git push origin main    │
/// │ Reason:  Shell command           │
/// │                                  │
/// │  [Deny]  [Always Allow]  [Allow] │
/// └──────────────────────────────────┘
/// ```
struct PermissionAlertView: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                Text("\(request.toolName) needs confirmation")
                    .font(.headline)
            }

            Divider()

            // Details
            VStack(alignment: .leading, spacing: 6) {
                detailRow(label: "Action", value: request.displaySummary)
                detailRow(label: "Reason", value: request.reason)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDeny()
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onAlwaysAllow()
                } label: {
                    Text("Always Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onAllow()
                } label: {
                    Label("Allow", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

// MARK: - Permission Overlay Modifier

/// A view modifier that overlays a `PermissionAlertView` when a request is present.
///
/// Usage:
/// ```swift
/// ContentView()
///     .permissionAlert(
///         request: appState.pendingPermission,
///         onAllow: { ... },
///         onAlwaysAllow: { ... },
///         onDeny: { ... }
///     )
/// ```
struct PermissionAlertModifier: ViewModifier {
    let request: PermissionRequest?
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if let request {
                // Dim background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                PermissionAlertView(
                    request: request,
                    onAllow: onAllow,
                    onAlwaysAllow: onAlwaysAllow,
                    onDeny: onDeny
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: request?.id)
    }
}

extension View {
    /// Adds a permission confirmation overlay triggered by a pending request.
    func permissionAlert(
        request: PermissionRequest?,
        onAllow: @escaping () -> Void,
        onAlwaysAllow: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) -> some View {
        modifier(PermissionAlertModifier(
            request: request,
            onAllow: onAllow,
            onAlwaysAllow: onAlwaysAllow,
            onDeny: onDeny
        ))
    }
}

// MARK: - Preview

