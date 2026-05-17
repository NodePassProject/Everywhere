//
//  Configuration.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import CoreData
import Foundation

@objc(Configuration)
public final class Configuration: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var type: String
    @NSManaged public var content: String
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension Configuration {
    var coreType: CoreType {
        get { CoreType(rawValue: type) ?? .xray }
        set { type = newValue.rawValue }
    }
}
