// FileTreeView.swift
// CodingPad
//
// File tree browser showing the project directory structure.

import SwiftUI

// MARK: - File Node

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [FileNode]?
    let fileSize: Int?
    let modificationDate: Date?

    init(
        name: String,
        path: String,
        isDirectory: Bool,
        children: [FileNode]? = nil,
        fileSize: Int? = nil,
        modificationDate: Date? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    // Icon based on file type
    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "j.square"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "md": return "doc.text"
        case "yml", "yaml": return "list.bullet.indent"
        case "h", "c", "cpp", "m": return "c.square"
        case "html", "css": return "globe"
        case "sh", "bash": return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .blue }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "py": return .green
        case "json": return .purple
        case "md": return .cyan
        case "h", "c", "cpp", "m": return .teal
        default: return .secondary
        }
    }
}

// MARK: - FileTreeView

struct FileTreeView: View {
    @Environment(AppState.self) private var appState
    @State private var rootNode: FileNode?
    @State private var selectedPath: String?
    @State private var expandedDirs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder")
                    .font(.caption)
                Text("Files")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await refreshTree() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // File tree
            if let root = rootNode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(root.children ?? []) { node in
                            fileNodeRow(node, depth: 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No project open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await refreshTree()
        }
    }

    // MARK: - Node Row

    @ViewBuilder
    private func fileNodeRow(_ node: FileNode, depth: Int) -> some View {
        let isExpanded = expandedDirs.contains(node.path)

        Button {
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedDirs.remove(node.path)
                    } else {
                        expandedDirs.insert(node.path)
                    }
                }
            } else {
                selectedPath = node.path
                // TODO: Open file in editor
            }
        } label: {
            HStack(spacing: 4) {
                // Indent
                Spacer()
                    .frame(width: CGFloat(depth) * 16)

                // Disclosure indicator for directories
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon
                Image(systemName: node.icon)
                    .font(.caption2)
                    .foregroundStyle(node.iconColor)
                    .frame(width: 16)

                // Name
                Text(node.name)
                    .font(.caption)
                    .foregroundStyle(selectedPath == node.path ? .accentColor : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(selectedPath == node.path ? Color.accentColor.opacity(0.1) : .clear)
        }
        .buttonStyle(.plain)

        // Children (if expanded)
        if node.isDirectory && isExpanded, let children = node.children {
            ForEach(children) { child in
                fileNodeRow(child, depth: depth + 1)
            }
        }
    }

    // MARK: - Tree Building

    private func refreshTree() async {
        guard let projectPath = appState.activeProjectPath else {
            rootNode = nil
            return
        }

        rootNode = await buildTree(at: projectPath, maxDepth: 4)
    }

    private func buildTree(at path: String, maxDepth: Int, currentDepth: Int = 0) async -> FileNode {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return FileNode(
                name: name,
                path: path,
                isDirectory: false,
                fileSize: attrs?[.size] as? Int,
                modificationDate: attrs?[.modificationDate] as? Date
            )
        }

        // Directory
        var children: [FileNode] = []
        if currentDepth < maxDepth {
            let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            let filtered = contents.filter { !Self.ignoredNames.contains($0) && !$0.hasPrefix(".") }
            let sorted = filtered.sorted { a, b in
                var aIsDir: ObjCBool = false
                var bIsDir: ObjCBool = false
                fm.fileExists(atPath: "\(path)/\(a)", isDirectory: &aIsDir)
                fm.fileExists(atPath: "\(path)/\(b)", isDirectory: &bIsDir)
                if aIsDir.boolValue != bIsDir.boolValue {
                    return aIsDir.boolValue  // Directories first
                }
                return a.localizedStandardCompare(b) == .orderedAscending
            }

            for item in sorted {
                let childPath = "\(path)/\(item)"
                let child = await buildTree(at: childPath, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                children.append(child)
            }
        }

        return FileNode(name: name, path: path, isDirectory: true, children: children)
    }

    private static let ignoredNames: Set<String> = [
        "node_modules", ".git", ".build", "DerivedData", "__pycache__",
        ".DS_Store", "Thumbs.db", ".Trash", "Pods", ".swiftpm"
    ]
}

#Preview {
    FileTreeView()
        .frame(width: 250)
        .environment(AppState())
}
