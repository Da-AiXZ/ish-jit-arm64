// WebFetchTool.swift
// CodingPad
//
// Fetches web page or API content via URLSession.

import Foundation

// MARK: - WebFetchTool

/// Fetches content from a URL using URLSession.
///
/// Supports HTTP/HTTPS URLs. HTML content is converted to plain text by
/// stripping tags. Response content is truncated to 50,000 characters.
/// Requires network permission.
struct WebFetchTool: AgentTool {
    let name = "web_fetch"

    let description = "Fetches content from a URL. HTML is converted to plain text. Response is truncated to 50,000 characters."

    let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "url": .init(
                type: "string",
                description: "The URL to fetch content from (must be http:// or https://).",
                enumValues: nil
            ),
            "prompt": .init(
                type: "string",
                description: "Optional prompt describing what information to extract from the page.",
                enumValues: nil
            )
        ],
        required: ["url"]
    )

    let usagePrompt = """
    Fetches content from a URL using URLSession.

    - Only HTTP and HTTPS URLs are supported.
    - HTML responses are automatically converted to plain text by stripping tags.
    - Response content is truncated to 50,000 characters to fit within context limits.
    - Use the optional `prompt` parameter to describe what information you're looking for.
    - This tool requires network permission and will prompt the user for confirmation.
    - Timeout is 30 seconds for the HTTP request.
    """

    let isReadOnly = false  // Network access scope
    let isConcurrencySafe = true

    // MARK: - Constants

    private enum Constants {
        static let maxContentLength = 50_000
        static let requestTimeout: TimeInterval = 30
    }

    // MARK: - Permission

    func checkPermission(_ input: ToolInput) -> PermissionDecision {
        guard let urlString = input.string(for: "url") else {
            return .deny(reason: "Missing required parameter: url")
        }
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .deny(reason: "Invalid or unsupported URL. Only http:// and https:// are allowed.")
        }
        return .ask(reason: "Fetch URL: \(urlString)")
    }

    // MARK: - Execute

    func execute(_ input: ToolInput) async throws -> ToolResult {
        guard let urlString = input.string(for: "url") else {
            return .error("Missing required parameter: url")
        }

        guard let url = URL(string: urlString) else {
            return .error("Invalid URL: \(urlString)")
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .error("Unsupported URL scheme. Only http:// and https:// are allowed.")
        }

        let prompt = input.string(for: "prompt")

        // Configure request
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.requestTimeout
        request.setValue("CodingPad/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, application/json, text/plain", forHTTPHeaderField: "Accept")

        // Perform request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .error("Failed to fetch URL '\(urlString)': \(error.localizedDescription)")
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            return .error("Unexpected response type from URL: \(urlString)")
        }

        guard (200..<400).contains(httpResponse.statusCode) else {
            return .error("HTTP \(httpResponse.statusCode) error fetching '\(urlString)'")
        }

        // Decode response body
        guard var content = String(data: data, encoding: .utf8) else {
            return .error("Response is not valid UTF-8 text.")
        }

        // Determine content type
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isHTML = contentType.lowercased().contains("text/html")

        // Strip HTML tags if needed
        if isHTML {
            content = stripHTML(content)
        }

        // Truncate if too long
        let wasTruncated = content.count > Constants.maxContentLength
        if wasTruncated {
            content = String(content.prefix(Constants.maxContentLength))
            content += "\n\n... [Content truncated at \(Constants.maxContentLength) characters]"
        }

        // Build output
        var output = ""
        if let prompt = prompt {
            output += "Prompt: \(prompt)\n\n"
        }
        output += "URL: \(urlString)\n"
        output += "Status: \(httpResponse.statusCode)\n"
        output += "Content-Type: \(contentType)\n"
        output += "---\n"
        output += content

        return ToolResult(
            content: output,
            metadata: [
                "url": urlString,
                "status_code": "\(httpResponse.statusCode)",
                "content_type": contentType,
                "truncated": "\(wasTruncated)"
            ]
        )
    }

    // MARK: - HTML Processing

    /// Strips HTML tags and decodes common HTML entities, converting to plain text.
    private func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style blocks entirely
        text = removeHTMLBlocks(from: text, tag: "script")
        text = removeHTMLBlocks(from: text, tag: "style")
        text = removeHTMLBlocks(from: text, tag: "nav")

        // Replace block elements with newlines
        let blockTags = ["p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6",
                         "li", "tr", "blockquote", "pre", "hr", "section", "article"]
        for tag in blockTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>",
                with: "\n",
                options: .regularExpression,
                range: nil
            )
        }

        // Remove remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric HTML entities
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let mutableText = NSMutableString(string: text)
            regex.replaceMatches(in: mutableText, options: [], range: range, withTemplate: "")
            text = mutableText as String
        }

        // Collapse multiple blank lines
        text = text.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression,
            range: nil
        )

        // Trim whitespace from each line
        text = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes all content between opening and closing tags of the specified element.
    private func removeHTMLBlocks(from html: String, tag: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            with: "",
            options: [.regularExpression, .caseInsensitive],
            range: nil
        )
    }
}
