//
//  ContentView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var appState = AppState.shared

    private var showsDashboard: Bool {
        tunnel.coreRunning && appState.dashboardEnabled && !appState.dashboardHidden
    }

    var body: some View {
        ZStack {
            if showsDashboard {
                DashboardView(core: store.selectedCore, configID: store.active?.id)
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .animation(.default, value: showsDashboard)
        .onChange(of: tunnel.coreRunning) { running in
            if !running { appState.dashboardHidden = false }
        }
    }
}
