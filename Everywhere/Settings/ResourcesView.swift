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
                    NavigationLink {
                        DirectoryBrowserView(
                            url: ResourcesStore.directory(for: core),
                            title: core.displayName
                        )
                    } label: {
                        Label {
                            Text(core.displayName)
                        } icon: {
                            Image(core.rawValue)
                                .interpolation(.high)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                    }
                }
            }
        }
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
