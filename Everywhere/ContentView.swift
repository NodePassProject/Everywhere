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
    @State private var minimized: Bool = false

    var body: some View {
        ZStack {
            if tunnel.coreRunning && !minimized {
                RunningRootView()
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }

            // Overlay the menu button for the whole tunnel session so
            // it follows the user from the dashboard back to the home
            // tabs without losing its drag-positioned location.
            if tunnel.coreRunning {
                FloatingMenuButton(
                    isMinimized: minimized,
                    onToggleMinimize: { minimized.toggle() },
                    onStop: stopTunnel
                )
            }
        }
        .animation(.default, value: tunnel.coreRunning)
        .animation(.default, value: minimized)
        .onChange(of: tunnel.coreRunning) { running in
            if !running { minimized = false }
        }
    }

    private func stopTunnel() {
        Task { await tunnel.setEnabled(false, configuration: store.active) }
    }
}

private struct RunningRootView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        if appState.useZashboardEnabled && store.selectedCore != .xray {
            DashboardView()
        } else {
            Text("\(store.selectedCore.displayName) is running")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
