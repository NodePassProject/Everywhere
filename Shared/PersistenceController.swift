//
//  PersistenceController.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "Everywhere", managedObjectModel: model)

        // The store lives inside the App Group container so the
        // Network Extension can open the same SQLite and read the
        // active config directly. Without this the NE would need
        // the config blob shipped through providerConfiguration,
        // which iOS caps at 512 KB.
        let storeURL = AppGroup.containerURL.appendingPathComponent("Everywhere.sqlite")
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Configuration"
        entity.managedObjectClassName = NSStringFromClass(Configuration.self)

        func attr(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = false
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        entity.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType, defaultValue: ""),
            attr("type", .stringAttributeType, defaultValue: CoreType.xray.rawValue),
            attr("content", .stringAttributeType, defaultValue: ""),
            attr("createdAt", .dateAttributeType),
            attr("updatedAt", .dateAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
