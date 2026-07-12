// MarkdownRenderer.swift
// CodingPad
//
// Parses Markdown text into structured blocks and renders them as SwiftUI views.
// Supports code blocks (with syntax highlighting), inline code, bold, italic,
// headings, lists, links, and horizontal rules.

import SwiftUI

// MARK: - Markdown Block Model

enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(content: String)
    case codeBlock(language: String, code: String)
    case unorderedList(items: [String])
    case orderedList(items: [(number: Int, content: String)])
    case horizontalRule
}

// MARK: - Markdown Parser

struct MarkdownParser {

    /// Parses a Markdown string into an array of block-level elements.
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let parsed = parseCodeBlock(lines: lines, startIndex: index)
                blocks.append(parsed.block)
                index = parsed.nextIndex
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                let parsed = parseUnorderedList(lines: lines, startIndex: index)
                blocks.append(parsed.block)
                index = parsed.nextIndex
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                let parsed = parseOrderedList(lines: lines, startIndex: index)
                blocks.append(parsed.block)
                index = parsed.nextIndex
                continue
            }

            // Paragraph — collect consecutive non-special lines
            let parsed = parseParagraph(lines: lines, startIndex: index)
            blocks.append(parsed.block)
            index = parsed.nextIndex
        }

        return blocks
    }

    // MARK: - Block Parsers

    private static func parseCodeBlock(
        lines: [String], startIndex: Int
    ) -> (block: MarkdownBlock, nextIndex: Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            if current.hasPrefix("```") {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }

        let code = codeLines.joined(separator: "\n")
        return (.codeBlock(language: language, code: code), index)
    }

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.first == "#" else { return nil }

        let hashes = trimmed.prefix(while: { $0 == "#" })
        let level = hashes.count
        guard level >= 1, level <= 6 else { return nil }

        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.first == " " else { return nil }

        let content = String(afterHashes).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, content: content)
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed.filter { !$0.isWhitespace })
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    private static func isUnorderedListItem(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ trimmed: String) -> Bool {
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[trimmed.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return false }
        let afterDot = trimmed.index(after: dotIndex)
        return afterDot < trimmed.endIndex && trimmed[afterDot] == " "
    }

    private static func parseUnorderedList(
        lines: [String], startIndex: Int
    ) -> (block: MarkdownBlock, nextIndex: Int) {
        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if isUnorderedListItem(trimmed) {
                let content = String(trimmed.dropFirst(2))
                items.append(content)
                index += 1
            } else if trimmed.isEmpty {
                index += 1
                break
            } else {
                break
            }
        }

        return (.unorderedList(items: items), index)
    }

    private static func parseOrderedList(
        lines: [String], startIndex: Int
    ) -> (block: MarkdownBlock, nextIndex: Int) {
        var items: [(number: Int, content: String)] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if isOrderedListItem(trimmed) {
                let numStr = trimmed.prefix(while: { $0.isNumber })
                let num = Int(numStr) ?? (items.count + 1)
                let afterDot = trimmed.drop(while: { $0.isNumber }).dropFirst() // drop "."
                let content = String(afterDot).trimmingCharacters(in: .whitespaces)
                items.append((number: num, content: content))
                index += 1
            } else if trimmed.isEmpty {
                index += 1
                break
            } else {
                break
            }
        }

        return (.orderedList(items: items), index)
    }

    private static func parseParagraph(
        lines: [String], startIndex: Int
    ) -> (block: MarkdownBlock, nextIndex: Int) {
        var paragraphLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            let isSpecial = trimmed.isEmpty
                || trimmed.hasPrefix("```")
                || trimmed.first == "#"
                || isHorizontalRule(trimmed)
                || isUnorderedListItem(trimmed)
                || isOrderedListItem(trimmed)

            if isSpecial { break }

            paragraphLines.append(lines[index])
            index += 1
        }

        let content = paragraphLines.joined(separator: "\n")
        return (.paragraph(content: content), index)
    }
}

// MARK: - MarkdownView

struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            headingView(level: level, content: content)

        case .paragraph(let content):
            paragraphView(content: content)

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .unorderedList(let items):
            unorderedListView(items: items)

        case .orderedList(let items):
            orderedListView(items: items)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Block Views

    private func headingView(level: Int, content: String) -> some View {
        let font: Font = switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        case 4: .headline
        default: .subheadline
        }

        return inlineMarkdownText(content)
            .font(font)
            .fontWeight(.bold)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    private func paragraphView(content: String) -> some View {
        inlineMarkdownText(content)
            .font(.body)
    }

    private func unorderedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2022}")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    inlineMarkdownText(item)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }

    private func orderedListView(items: [(number: Int, content: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(item.number).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    inlineMarkdownText(item.content)
                        .font(.body)
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Inline Markdown

    /// Renders inline Markdown (bold, italic, code, links) using AttributedString.
    private func inlineMarkdownText(_ content: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        } else {
            return Text(content)
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label header
            if !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    copyButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(codeHeaderBackground)
            }

            // Highlighted code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = code
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var codeHeaderBackground: Color {
        Color(.secondarySystemBackground).opacity(0.8)
    }
}

// MARK: - Preview

#Preview("Markdown Rendering") {
    ScrollView {
        MarkdownView(text: """
        # Heading 1

        ## Heading 2

        This is a paragraph with **bold**, *italic*, and `inline code`.

        Here is a [link](https://example.com).

        ```swift
        struct Hello {
            let name: String

            func greet() -> String {
                return "Hello, \\(name)!"
            }
        }
        ```

        - First item
        - Second item
        - Third item

        1. Step one
        2. Step two
        3. Step three

        ---

        Another paragraph after the rule.
        """)
        .padding()
    }
}
