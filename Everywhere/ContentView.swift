//
//  ContentView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var store = ConfigurationStore.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            if showController {
                ControllerView()
                    .tabItem { Label("Controller", systemImage: "gauge") }
            }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    // yacd talks to the clash REST API, which Xray-core does not expose.
    private var showController: Bool {
        tunnel.coreRunning && store.selectedCore != .xray
    }
}
