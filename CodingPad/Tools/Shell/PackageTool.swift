// PackageTool.swift
// CodingPad
//
// Package management tool wrapping apk (Alpine), npm, and pip.

import Foundation

struct PackageTool: AgentTool {

    // MARK: - AgentTool Conformance

    let name = "PackageTool"

    let description = """
        Install, remove, or search packages using the system package managers \
        (apk for Alpine, npm for Node.js, pip for Python) inside the iSH environment.
        """

    let isReadOnly = false
    let isConcurrencySafe = false

    var inputSchema: ToolInputSchema {
        ToolInputSchema(
            type: "object",
            properties: [
                "manager": .init(
                    type: "string",
                    description: "Package manager to use.",
                    enumValues: ["apk", "npm", "pip"]
                ),
                "action": .init(
                    type: "string",
                    description: "Action to perform.",
                    enumValues: ["install", "remove", "search", "list", "update"]
                ),
                "packages": .init(
                    type: "string",
                    description: "Space-separated package names.",
                    enumValues: nil
                ),
                "flags": .init(
                    type: "string",
                    description: "Additional flags (e.g., --save-dev, --global).",
                    enumValues: nil
                )
            ],
            required: ["manager", "action"]
        )
    }

    var usagePrompt: String {
        """
        Manage packages in the iSH environment.

        Package managers:
        - apk: Alpine Linux packages (git, python3, nodejs, etc.)
        - npm: Node.js packages (requires nodejs to be installed via apk)
        - pip: Python packages (requires python3 to be installed via apk)

        Actions:
        - install: Install packages (e.g., manager="apk", action="install", packages="git nodejs npm")
        - remove: Remove packages
        - search: Search for available packages
        - list: List installed packages
        - update: Update package index/registry

        Performance note: Package installation in iSH may take 10-60 seconds \
        depending on the package size and whether it requires compilation. \
        Pre-built Alpine packages (apk) install fastest.
        """
    }

    // MARK: - Permission Check

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let action = input.string(for: "action") else {
            return .deny(reason: "No action specified.")
        }

        switch action {
        case "search", "list":
            return .allow
        case "install", "remove", "update":
            let packages = input.string(for: "packages") ?? ""
            return .ask(reason: "Package \(action): \(packages)")
        default:
            return .deny(reason: "Unknown action: \(action)")
        }
    }

    // MARK: - Execution

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let manager = input.string(for: "manager"),
              let action = input.string(for: "action") else {
            return .error("Missing required parameters: manager and action")
        }

        let packages = input.string(for: "packages") ?? ""
        let flags = input.string(for: "flags") ?? ""

        let command = buildCommand(
            manager: manager,
            action: action,
            packages: packages,
            flags: flags
        )

        guard let command = command else {
            return .error("Invalid manager/action combination: \(manager) \(action)")
        }

        let engine = ISHEngine.shared

        do {
            let result = try await engine.execute(
                command: command,
                timeout: 300.0 // 5 min for package operations
            )

            var output = result.stdout
            if !result.stderr.isEmpty {
                output += "\nSTDERR:\n\(result.stderr)"
            }

            return ToolResult(
                content: output.isEmpty ? "(no output)" : output,
                isError: result.exitCode != 0,
                metadata: [
                    "manager": manager,
                    "action": action,
                    "exit_code": "\(result.exitCode)"
                ]
            )
        } catch {
            return .error("Package operation error: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Building

    private func buildCommand(
        manager: String,
        action: String,
        packages: String,
        flags: String
    ) -> String? {
        let flagsPart = flags.isEmpty ? "" : " \(flags)"
        let pkgPart = packages.isEmpty ? "" : " \(packages)"

        switch manager {
        case "apk":
            switch action {
            case "install": return "apk add --no-cache\(flagsPart)\(pkgPart)"
            case "remove": return "apk del\(flagsPart)\(pkgPart)"
            case "search": return "apk search\(flagsPart)\(pkgPart)"
            case "list": return "apk list --installed\(flagsPart)"
            case "update": return "apk update\(flagsPart)"
            default: return nil
            }

        case "npm":
            switch action {
            case "install": return "npm install\(flagsPart)\(pkgPart)"
            case "remove": return "npm uninstall\(flagsPart)\(pkgPart)"
            case "search": return "npm search\(flagsPart)\(pkgPart)"
            case "list": return "npm list\(flagsPart)"
            case "update": return "npm update\(flagsPart)\(pkgPart)"
            default: return nil
            }

        case "pip":
            switch action {
            case "install": return "pip install\(flagsPart)\(pkgPart)"
            case "remove": return "pip uninstall -y\(flagsPart)\(pkgPart)"
            case "search": return "pip index versions\(flagsPart)\(pkgPart)"
            case "list": return "pip list\(flagsPart)"
            case "update": return "pip install --upgrade\(flagsPart)\(pkgPart)"
            default: return nil
            }

        default:
            return nil
        }
    }
}
