//
//  SettingsView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                NavigationLink {
                    DNSSettingsView()
                } label: {
                    Label("DNS", systemImage: "network")
                }
                NavigationLink {
                    ResourcesView()
                } label: {
                    Label("Resources", systemImage: "folder")
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}
