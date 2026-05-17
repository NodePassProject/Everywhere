//
//  ResourcesView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

struct ResourcesView: View {
    var body: some View {
        Form {
            Section {
                ForEach(CoreType.allCases) { core in
                    NavigationLink(core.displayName) {
                        DirectoryBrowserView(
                            url: ResourcesStore.directory(for: core),
                            title: core.displayName
                        )
                    }
                }
            }
        }
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
