//
//  ResourcesStore.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Foundation

struct ResourceFile: Identifiable, Hashable {
    let name: String
    let size: Int64
    var id: String { name }
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum ResourcesStore {
    static func directory(for core: CoreType) -> URL { AppGroup.resourcesURL(for: core) }

    static func list(for core: CoreType) throws -> [ResourceFile] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory(for: core),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        )
        return entries.compactMap { entry in
            let v = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard v?.isRegularFile == true else { return nil }
            return ResourceFile(name: entry.lastPathComponent, size: Int64(v?.fileSize ?? 0))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Copies a user-picked file into the given core's resources directory.
    /// Caller is responsible for security-scoped resource handling.
    static func importFile(from sourceURL: URL, for core: CoreType) throws {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let dest = directory(for: core).appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    static func delete(named name: String, for core: CoreType) throws {
        let path = directory(for: core).appendingPathComponent(name)
        try FileManager.default.removeItem(at: path)
    }
}
