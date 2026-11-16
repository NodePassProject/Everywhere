//
//  ResourcesStore.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Foundation

enum ResourceKind {
    case file
    case directory
}

struct ResourceEntry: Identifiable, Hashable {
    let url: URL
    let kind: ResourceKind
    let size: Int64?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var formattedSize: String? {
        guard let size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum ResourcesStoreError: LocalizedError {
    case folderNotEmpty
    case invalidName

    var errorDescription: String? {
        switch self {
        case .folderNotEmpty:
            return String(localized: "Folder is not empty.")
        case .invalidName:
            return String(localized: "Invalid name.")
        }
    }
}

enum ResourcesStore {
    static func directory(for core: CoreType) -> URL { EVCore.resourcesURL(for: core) }

    static func list(at url: URL) throws -> [ResourceEntry] {
        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey]
        )
        let mapped: [ResourceEntry] = children.compactMap { child in
            guard let v = try? child.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey]
            ) else { return nil }
            if v.isDirectory == true {
                return ResourceEntry(url: child, kind: .directory, size: nil)
            }
            if v.isRegularFile == true {
                return ResourceEntry(url: child, kind: .file, size: Int64(v.fileSize ?? 0))
            }
            return nil
        }
        return mapped.sorted { a, b in
            if a.kind != b.kind { return a.kind == .directory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func importFile(from sourceURL: URL, into destinationDir: URL) throws {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let dest = destinationDir.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    static func createFolder(named rawName: String, in parent: URL) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw ResourcesStoreError.invalidName
        }
        let dest = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
    }

    static func delete(_ entry: ResourceEntry) throws {
        if entry.kind == .directory {
            let contents = try FileManager.default.contentsOfDirectory(atPath: entry.url.path)
            if !contents.isEmpty {
                throw ResourcesStoreError.folderNotEmpty
            }
        }
        try FileManager.default.removeItem(at: entry.url)
    }
}
