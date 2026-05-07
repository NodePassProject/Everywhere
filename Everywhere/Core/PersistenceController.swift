//
//  PersistenceController.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "Everywhere", managedObjectModel: model)
        
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
