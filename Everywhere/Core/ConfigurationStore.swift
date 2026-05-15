//
//  ConfigurationStore.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Combine
import CoreData
import Foundation

final class ConfigurationStore: ObservableObject {
    static let shared = ConfigurationStore()

    private enum Keys {
        static let selectedCore = "selectedCore"
        static let activeByCoreType = "activeByCoreType"
    }

    @Published private(set) var configurations: [Configuration] = []

    /// The core the user is currently working with — drives what
    /// HomeView's picker reads/writes and what `ConfigurationsView`
    /// filters its list by.
    @Published var selectedCore: CoreType {
        didSet { AppGroup.defaults.set(selectedCore.rawValue, forKey: Keys.selectedCore) }
    }

    /// Each core type has its own "active" configuration so switching
    /// the core picker doesn't lose the user's pick for the other
    /// cores.
    @Published private(set) var activeIDByCoreType: [CoreType: UUID] = [:]

    /// The configuration that the tunnel will run with right now —
    /// always the active one for the selected core.
    var active: Configuration? {
        guard let id = activeIDByCoreType[selectedCore] else { return nil }
        return configurations.first { $0.id == id }
    }

    /// Configurations filtered to the selected core. ConfigurationsView
    /// renders this.
    var configurationsForSelectedCore: [Configuration] {
        configurations.filter { $0.coreType == selectedCore }
    }

    private let context: NSManagedObjectContext

    private init() {
        self.context = PersistenceController.shared.container.viewContext

        let storedCoreRaw = AppGroup.defaults.string(forKey: Keys.selectedCore)
        self.selectedCore = storedCoreRaw.flatMap(CoreType.init(rawValue:)) ?? .xray

        loadActiveMap()
        reload()
        seedIfEmpty()
    }

    func reload() {
        let request = NSFetchRequest<Configuration>(entityName: "Configuration")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Configuration.createdAt, ascending: true)
        ]
        configurations = (try? context.fetch(request)) ?? []
        // Drop dangling active pointers (e.g. row deleted out of band).
        var changed = false
        for (core, id) in activeIDByCoreType {
            if !configurations.contains(where: { $0.id == id }) {
                activeIDByCoreType[core] = nil
                changed = true
            }
        }
        if changed { persistActiveMap() }
    }

    @discardableResult
    func create(name: String, type: CoreType, content: String) -> Configuration {
        let cfg = Configuration(context: context)
        cfg.id = UUID()
        cfg.name = name
        cfg.type = type.rawValue
        cfg.content = content
        cfg.createdAt = Date()
        cfg.updatedAt = Date()
        save()
        reload()
        if activeIDByCoreType[type] == nil {
            activeIDByCoreType[type] = cfg.id
            persistActiveMap()
        }
        return cfg
    }

    func update(_ cfg: Configuration, name: String? = nil, type: CoreType? = nil, content: String? = nil) {
        let oldType = cfg.coreType
        if let name { cfg.name = name }
        if let newType = type, newType != oldType {
            cfg.coreType = newType
            // Re-balance the per-core active map across the move.
            if activeIDByCoreType[oldType] == cfg.id {
                activeIDByCoreType[oldType] = configurations.first {
                    $0.coreType == oldType && $0.id != cfg.id
                }?.id
            }
            if activeIDByCoreType[newType] == nil {
                activeIDByCoreType[newType] = cfg.id
            }
            persistActiveMap()
        }
        if let content { cfg.content = content }
        cfg.updatedAt = Date()
        save()
        objectWillChange.send()
    }

    func delete(_ cfg: Configuration) {
        let type = cfg.coreType
        let id = cfg.id
        let wasActive = (activeIDByCoreType[type] == id)
        context.delete(cfg)
        save()
        reload()
        if wasActive {
            activeIDByCoreType[type] = configurations.first { $0.coreType == type }?.id
            persistActiveMap()
        }
    }

    func setActive(_ cfg: Configuration) {
        activeIDByCoreType[cfg.coreType] = cfg.id
        persistActiveMap()
    }

    // MARK: - Persistence helpers

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            NSLog("ConfigurationStore: save failed: \(error)")
        }
    }

    private func persistActiveMap() {
        let dict = activeIDByCoreType.reduce(into: [String: String]()) { acc, kv in
            acc[kv.key.rawValue] = kv.value.uuidString
        }
        AppGroup.defaults.set(dict, forKey: Keys.activeByCoreType)
    }

    private func loadActiveMap() {
        let raw = AppGroup.defaults.dictionary(forKey: Keys.activeByCoreType) as? [String: String] ?? [:]
        activeIDByCoreType = raw.reduce(into: [CoreType: UUID]()) { acc, kv in
            if let core = CoreType(rawValue: kv.key), let id = UUID(uuidString: kv.value) {
                acc[core] = id
            }
        }
    }

    // MARK: - First-run seeding

    private func seedIfEmpty() {
        guard configurations.isEmpty else { return }
        create(name: "Xray", type: .xray, content: ExampleConfigs.xray)
        create(name: "sing-box", type: .singbox, content: ExampleConfigs.singbox)
        create(name: "mihomo", type: .mihomo, content: ExampleConfigs.mihomo)
        // create() already populated activeIDByCoreType for each type.
    }
}
