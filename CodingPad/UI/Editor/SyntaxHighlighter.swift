// SyntaxHighlighter.swift
// CodingPad
//
// Regex-based syntax highlighting for common programming languages.
// Converts source code into AttributedString with language-aware coloring.

import SwiftUI

struct SyntaxHighlighter {

    // MARK: - Public API

    /// Converts source code into an AttributedString with syntax coloring.
    static func highlight(_ code: String, language: String) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.font = .system(.body, design: .monospaced)
        attributed.foregroundColor = .primary

        guard !code.isEmpty else { return attributed }

        let lang = language.lowercased().trimmingCharacters(in: .whitespaces)
        let tokenPatterns = buildPatterns(for: lang)
        let sorted = tokenPatterns.sorted { $0.priority < $1.priority }

        for pattern in sorted {
            applyPattern(pattern, to: &attributed, source: code)
        }

        return attributed
    }

    /// Determines the programming language from a file extension.
    static func languageFromExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift":               return "swift"
        case "ts", "tsx":           return "typescript"
        case "js", "jsx":          return "javascript"
        case "py":                  return "python"
        case "html", "htm":        return "html"
        case "css":                 return "css"
        case "json":                return "json"
        case "sh", "bash", "zsh":  return "bash"
        case "rb":                  return "ruby"
        case "rs":                  return "rust"
        case "go":                  return "go"
        case "md", "markdown":     return "markdown"
        default:                    return "plain"
        }
    }

    // MARK: - Token Pattern

    private struct TokenPattern {
        let regex: String
        let options: NSRegularExpression.Options
        let color: Color
        let bold: Bool
        let priority: Int // higher priority = applied later, overrides lower
    }

    // MARK: - Pattern Application

    private static func applyPattern(
        _ pattern: TokenPattern,
        to attributed: inout AttributedString,
        source: String
    ) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern.regex,
            options: pattern.options
        ) else { return }

        let nsRange = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: nsRange)
        let charCount = attributed.characters.count

        for match in matches {
            guard let stringRange = Range(match.range, in: source) else { continue }

            let startOffset = source.distance(from: source.startIndex, to: stringRange.lowerBound)
            let length = source.distance(from: stringRange.lowerBound, to: stringRange.upperBound)

            guard startOffset >= 0, length > 0, startOffset + length <= charCount else { continue }

            let start = attributed.characters.index(
                attributed.characters.startIndex, offsetBy: startOffset
            )
            let end = attributed.characters.index(start, offsetBy: length)
            let range = start..<end

            attributed[range].foregroundColor = pattern.color
            if pattern.bold {
                attributed[range].font = .system(.body, design: .monospaced).bold()
            }
        }
    }

    // MARK: - Pattern Building

    private static func buildPatterns(for language: String) -> [TokenPattern] {
        switch language {
        case "swift":                       return swiftPatterns
        case "typescript", "javascript":    return jsPatterns
        case "python":                      return pythonPatterns
        case "html":                        return htmlPatterns
        case "css":                         return cssPatterns
        case "json":                        return jsonPatterns
        case "bash", "shell", "sh":         return bashPatterns
        default:                            return commonPatterns
        }
    }

    // MARK: - Shared Patterns

    private static let numberPattern = TokenPattern(
        regex: #"\b\d+\.?\d*([eE][+-]?\d+)?\b"#,
        options: [],
        color: .blue,
        bold: false,
        priority: 10
    )

    private static let doubleQuoteStringPattern = TokenPattern(
        regex: #""(?:[^"\\]|\\.)*""#,
        options: [],
        color: .green,
        bold: false,
        priority: 80
    )

    private static let singleQuoteStringPattern = TokenPattern(
        regex: #"'(?:[^'\\]|\\.)*'"#,
        options: [],
        color: .green,
        bold: false,
        priority: 80
    )

    private static let lineCommentPattern = TokenPattern(
        regex: #"//.*$"#,
        options: [.anchorsMatchLines],
        color: .gray,
        bold: false,
        priority: 90
    )

    private static let blockCommentPattern = TokenPattern(
        regex: #"/\*[\s\S]*?\*/"#,
        options: [.dotMatchesLineSeparators],
        color: .gray,
        bold: false,
        priority: 90
    )

    private static let hashCommentPattern = TokenPattern(
        regex: #"#.*$"#,
        options: [.anchorsMatchLines],
        color: .gray,
        bold: false,
        priority: 90
    )

    private static var commonPatterns: [TokenPattern] {
        [numberPattern, doubleQuoteStringPattern, singleQuoteStringPattern,
         lineCommentPattern, blockCommentPattern]
    }

    // MARK: - Keyword Helper

    private static func keywordPattern(_ keywords: [String]) -> TokenPattern {
        let joined = keywords.joined(separator: "|")
        return TokenPattern(
            regex: "\\b(\(joined))\\b",
            options: [],
            color: .purple,
            bold: true,
            priority: 20
        )
    }

    // MARK: - Swift Patterns

    private static var swiftPatterns: [TokenPattern] {
        let keywords = [
            "func", "var", "let", "struct", "class", "enum", "protocol",
            "import", "return", "if", "else", "guard", "for", "while",
            "switch", "case", "throw", "try", "catch", "async", "await",
            "actor", "self", "true", "false", "nil", "private", "public",
            "internal", "fileprivate", "open", "static", "override",
            "init", "deinit", "extension", "where", "typealias",
            "associatedtype", "some", "any", "in", "is", "as", "super",
            "break", "continue", "default", "do", "repeat", "defer",
            "weak", "unowned", "lazy", "mutating", "throws", "rethrows"
        ]

        let attributePattern = TokenPattern(
            regex: #"@\w+"#,
            options: [],
            color: .purple,
            bold: true,
            priority: 25
        )

        let typePattern = TokenPattern(
            regex: #"\b[A-Z][A-Za-z0-9]*\b"#,
            options: [],
            color: .teal,
            bold: false,
            priority: 15
        )

        return [
            numberPattern, typePattern, keywordPattern(keywords),
            attributePattern, doubleQuoteStringPattern,
            lineCommentPattern, blockCommentPattern
        ]
    }

    // MARK: - TypeScript / JavaScript Patterns

    private static var jsPatterns: [TokenPattern] {
        let keywords = [
            "function", "const", "let", "var", "return", "if", "else",
            "for", "while", "switch", "case", "import", "export",
            "async", "await", "class", "interface", "type", "enum",
            "true", "false", "null", "undefined", "this", "new",
            "throw", "try", "catch", "finally", "default", "break",
            "continue", "from", "of", "in", "instanceof", "typeof",
            "void", "delete", "yield", "extends", "implements",
            "static", "readonly", "abstract", "private", "public",
            "protected", "super"
        ]

        let templateLiteralPattern = TokenPattern(
            regex: #"`(?:[^`\\]|\\.)*`"#,
            options: [.dotMatchesLineSeparators],
            color: .green,
            bold: false,
            priority: 80
        )

        return [
            numberPattern, keywordPattern(keywords),
            doubleQuoteStringPattern, singleQuoteStringPattern,
            templateLiteralPattern, lineCommentPattern, blockCommentPattern
        ]
    }

    // MARK: - Python Patterns

    private static var pythonPatterns: [TokenPattern] {
        let keywords = [
            "def", "class", "import", "from", "return", "if", "elif",
            "else", "for", "while", "try", "except", "with", "as",
            "in", "not", "and", "or", "True", "False", "None", "self",
            "async", "await", "pass", "break", "continue", "raise",
            "finally", "yield", "lambda", "global", "nonlocal", "del",
            "assert", "is"
        ]

        let tripleDoubleQuotePattern = TokenPattern(
            regex: #"\"\"\"[\s\S]*?\"\"\""#,
            options: [.dotMatchesLineSeparators],
            color: .green,
            bold: false,
            priority: 85
        )

        let tripleSingleQuotePattern = TokenPattern(
            regex: #"'''[\s\S]*?'''"#,
            options: [.dotMatchesLineSeparators],
            color: .green,
            bold: false,
            priority: 85
        )

        let decoratorPattern = TokenPattern(
            regex: #"@\w+"#,
            options: [],
            color: .orange,
            bold: true,
            priority: 25
        )

        return [
            numberPattern, keywordPattern(keywords), decoratorPattern,
            doubleQuoteStringPattern, singleQuoteStringPattern,
            tripleDoubleQuotePattern, tripleSingleQuotePattern,
            hashCommentPattern
        ]
    }

    // MARK: - HTML Patterns

    private static var htmlPatterns: [TokenPattern] {
        let tagPattern = TokenPattern(
            regex: #"</?[a-zA-Z][a-zA-Z0-9]*"#,
            options: [],
            color: .red,
            bold: false,
            priority: 20
        )

        let attrNamePattern = TokenPattern(
            regex: #"\b[a-zA-Z_-]+(?=\s*=)"#,
            options: [],
            color: .orange,
            bold: false,
            priority: 25
        )

        let closingBracketPattern = TokenPattern(
            regex: #"/?\s*>"#,
            options: [],
            color: .red,
            bold: false,
            priority: 20
        )

        let htmlCommentPattern = TokenPattern(
            regex: #"<!--[\s\S]*?-->"#,
            options: [.dotMatchesLineSeparators],
            color: .gray,
            bold: false,
            priority: 90
        )

        return [
            tagPattern, closingBracketPattern, attrNamePattern,
            doubleQuoteStringPattern, singleQuoteStringPattern,
            htmlCommentPattern
        ]
    }

    // MARK: - CSS Patterns

    private static var cssPatterns: [TokenPattern] {
        let selectorPattern = TokenPattern(
            regex: #"[.#]?[a-zA-Z_-][a-zA-Z0-9_-]*(?=\s*\{)"#,
            options: [],
            color: .orange,
            bold: true,
            priority: 15
        )

        let propertyPattern = TokenPattern(
            regex: #"[a-zA-Z-]+(?=\s*:)"#,
            options: [],
            color: .cyan,
            bold: false,
            priority: 20
        )

        let unitPattern = TokenPattern(
            regex: #"\b\d+\.?\d*(px|em|rem|%|vh|vw|s|ms|deg)\b"#,
            options: [],
            color: .blue,
            bold: false,
            priority: 25
        )

        let colorHexPattern = TokenPattern(
            regex: #"#[0-9a-fA-F]{3,8}\b"#,
            options: [],
            color: .purple,
            bold: false,
            priority: 25
        )

        return [
            numberPattern, selectorPattern, propertyPattern,
            unitPattern, colorHexPattern,
            doubleQuoteStringPattern, singleQuoteStringPattern,
            blockCommentPattern
        ]
    }

    // MARK: - JSON Patterns

    private static var jsonPatterns: [TokenPattern] {
        let keyPattern = TokenPattern(
            regex: #""[^"]*"\s*(?=:)"#,
            options: [],
            color: .cyan,
            bold: true,
            priority: 30
        )

        let boolNullPattern = TokenPattern(
            regex: #"\b(true|false|null)\b"#,
            options: [],
            color: .orange,
            bold: true,
            priority: 20
        )

        return [numberPattern, boolNullPattern, keyPattern, doubleQuoteStringPattern]
    }

    // MARK: - Bash / Shell Patterns

    private static var bashPatterns: [TokenPattern] {
        let keywords = [
            "if", "then", "fi", "for", "do", "done", "while", "case",
            "esac", "echo", "export", "function", "return", "local",
            "source", "alias", "unset", "set", "shift", "exit",
            "read", "eval", "exec", "trap", "select", "until",
            "elif", "else", "in"
        ]

        let variablePattern = TokenPattern(
            regex: #"\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?"#,
            options: [],
            color: .cyan,
            bold: false,
            priority: 25
        )

        return [
            numberPattern, keywordPattern(keywords), variablePattern,
            doubleQuoteStringPattern, singleQuoteStringPattern,
            hashCommentPattern
        ]
    }
}
