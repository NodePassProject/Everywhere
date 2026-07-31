//
//  MihomoNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

enum MihomoNormalizer: CoreNormalizer {
    private static let logFloor = "warning"
    private static let logOrder = ["debug", "info", "warning", "error", "silent"]
    
    private static let tunForcedKeys: Set<String> = [
        "enable",
        "stack",
        "mtu",
        "inet4-address",
        "inet6-address",
    ]
    
    private static let tunStrippedKeys: Set<String> = [
        "device",
        "file-descriptor",
    ]
    
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
    
    private static func matchesTopLevelKey(_ line: String, key: String) -> Bool {
        guard line.hasPrefix(key + ":") else { return false }
        let rest = line.dropFirst(key.count + 1)
        guard let next = rest.first else { return true }
        return next == " " || next == "\t" || next == "#"
    }
    
    private static func isColumnZeroContent(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == " " || first == "\t" { return false }
        if first == "#" { return false }
        return true
    }
    
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
    
    private static func inlineScalarValue(_ line: String, key: String) -> String {
        var rest = line.dropFirst(key.count + 1)
        if let hash = rest.firstIndex(of: "#") { rest = rest[..<hash] }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
