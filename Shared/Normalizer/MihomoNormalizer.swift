//
//  MihomoNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

// mihomo (YAML).
//
// mihomo's YAML grammar is loose — it tolerates duplicate keys,
// mixed tabs/spaces, and other shapes a strict parser rejects. We
// don't want to gatekeep the user's config, so we walk lines and
// touch only what has to change:
//
//  - At `tun:` (column 0), enter sub-block mode. For each sub-key
//    in `tunForcedKeys` ∪ `tunStrippedKeys`, drop that line and any
//    deeper-indented children; everything else (loopback-address,
//    dns-hijack, route-address, strict-route, udp-timeout,
//    endpoint-independent-nat, …) passes through. After the block,
//    inject our forced lines at the sub-block's detected indent.
//  - At any Clash-API surface key (`external-controller*`,
//    `external-ui*`, `external-doh-server`, `secret`), drop the
//    entire sub-block; our canonical `external-controller` is
//    appended at the end. Both steps run only when zashboard is on;
//    with it off these keys pass through untouched.
//  - At `log-level`, cap verbosity down to `logFloor`.
enum MihomoNormalizer: CoreNormalizer {
    private static let logFloor = "warning"
    private static let logOrder = ["debug", "info", "warning", "error", "silent"]

    // Force-set sub-keys inside `tun:`. We drop the user's version and
    // emit ours at the end of the block.
    private static let tunForcedKeys: Set<String> = [
        "enable",
        "stack",
        "mtu",
        "inet4-address",
        "inet6-address",
    ]

    // Stripped sub-keys inside `tun:`. We drop the user's version and
    // don't emit a replacement — EverywhereCore plumbs the fd through
    // the Go bridge, and a user-supplied `device` or `file-descriptor`
    // would compete with that.
    private static let tunStrippedKeys: Set<String> = [
        "device",
        "file-descriptor",
    ]

    // Top-level keys whose entire sub-block we drop wholesale. `tun` is
    // handled by the sub-key walker below and is intentionally not in
    // this list.
    private static let strippedTopLevelKeys: [String] = [
        "external-controller",
        "external-controller-tls",
        "external-controller-unix",
        "external-controller-pipe",
        "external-controller-cors",
        "external-ui",
        "external-ui-url",
        "external-ui-name",
        "external-doh-server",
        "secret",
    ]

    // mihomo's normalize never actually throws — it walks lines and can't
    // fail — but conforms to the throwing `CoreNormalizer` requirement.
    static func normalize(_ content: String, useZashboard: Bool) throws -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var i = 0
        var sawTunBlock = false
        var sawLogLevel = false

        while i < lines.count {
            let line = lines[i]

            if useZashboard && matchesStrippedTopLevelKey(line) {
                i += 1
                while i < lines.count {
                    if isColumnZeroContent(lines[i]) { break }
                    i += 1
                }
                continue
            }

            if matchesTopLevelKey(line, key: "tun") {
                sawTunBlock = true
                // Normalize the header to a bare `tun:` so an inline
                // scalar (`tun: false`) or trailing comment can't
                // confuse the YAML parser once we add children.
                output.append("tun:")
                i += 1
                var subIndent: Int? = nil
                while i < lines.count {
                    let sub = lines[i]
                    if isColumnZeroContent(sub) { break }
                    if let key = extractSubKey(sub) {
                        let indent = leadingWhitespaceCount(sub)
                        if subIndent == nil { subIndent = indent }
                        if tunForcedKeys.contains(key) || tunStrippedKeys.contains(key) {
                            i += 1
                            // Skip any deeper-indented children of the
                            // dropped key, tolerating blank lines.
                            while i < lines.count {
                                let next = lines[i]
                                if isColumnZeroContent(next) { break }
                                let trimmed = next.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty || leadingWhitespaceCount(next) > indent {
                                    i += 1
                                    continue
                                }
                                break
                            }
                            continue
                        }
                    }
                    output.append(sub)
                    i += 1
                }
                output.append(contentsOf: tunForcedLines(indent: subIndent ?? 2))
                continue
            }

            if matchesTopLevelKey(line, key: "log-level") {
                sawLogLevel = true
                let level = inlineScalarValue(line, key: "log-level")
                output.append("log-level: \(cappedLevel(level, order: logOrder, floor: logFloor))")
                i += 1
                continue
            }

            output.append(line)
            i += 1
        }

        if !sawTunBlock {
            if let last = output.last, !last.isEmpty {
                output.append("")
            }
            output.append("tun:")
            output.append(contentsOf: tunForcedLines(indent: 2))
        }

        if !sawLogLevel {
            if let last = output.last, !last.isEmpty {
                output.append("")
            }
            output.append("log-level: \(logFloor)")
        }

        // Append our canonical controller so zashboard can attach. With
        // zashboard off we skip this (and the strip step above), leaving the
        // user's external-controller* / external-ui* / secret as written.
        if useZashboard {
            if let last = output.last, !last.isEmpty {
                output.append("")
            }
            output.append("external-controller: \(clashAPIAddress)")
        }

        return output.joined(separator: "\n")
    }

    private static func tunForcedLines(indent: Int) -> [String] {
        let pad = String(repeating: " ", count: max(indent, 1))
        let listPad = pad + "  "
        return [
            "\(pad)enable: true",
            "\(pad)stack: \(tunStack)",
            "\(pad)mtu: \(tunnelMTU)",
            "\(pad)inet4-address:",
            "\(listPad)- \(tunnelPrefix)",
            "\(pad)inet6-address:",
            "\(listPad)- \(tunnelPrefix6)",
        ]
    }

    private static func matchesStrippedTopLevelKey(_ line: String) -> Bool {
        for key in strippedTopLevelKeys {
            if matchesTopLevelKey(line, key: key) { return true }
        }
        return false
    }

    // True when the line declares a top-level mapping with the given
    // key. Matches `key:`, `key: <value>`, `key:  # comment`, etc.
    // — but not `keyfoo:`, `  key:` (nested), or `# key:` (comment).
    private static func matchesTopLevelKey(_ line: String, key: String) -> Bool {
        guard line.hasPrefix(key + ":") else { return false }
        let rest = line.dropFirst(key.count + 1)
        guard let next = rest.first else { return true }
        return next == " " || next == "\t" || next == "#"
    }

    // True when the line has non-whitespace content at column 0 that
    // isn't a comment. Inside a block we treat blank lines and column-0
    // comments as still inside; only real content resumes the document.
    private static func isColumnZeroContent(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == " " || first == "\t" { return false }
        if first == "#" { return false }
        return true
    }

    // Returns the bare sub-key on a line like "  loopback-address: …"
    // or "  stack: gvisor". Returns nil for blank lines, comments, list
    // items ("  - foo"), or otherwise shapes that don't have a leading
    // `key:`.
    private static func extractSubKey(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first else { return nil }
        if first == "#" || first == "-" { return nil }
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colon])
        return key.isEmpty ? nil : key
    }

    private static func leadingWhitespaceCount(_ line: String) -> Int {
        var count = 0
        for c in line {
            if c == " " || c == "\t" { count += 1 } else { break }
        }
        return count
    }

    // Extracts the inline scalar after a top-level `key:` on one line,
    // dropping a trailing `# comment`. mihomo never parses YAML.
    private static func inlineScalarValue(_ line: String, key: String) -> String {
        var rest = line.dropFirst(key.count + 1)
        if let hash = rest.firstIndex(of: "#") { rest = rest[..<hash] }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
