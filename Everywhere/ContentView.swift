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
                RunningRootView(onHome: { minimized = true })
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .animation(.default, value: tunnel.coreRunning)
        .animation(.default, value: minimized)
        .onChange(of: tunnel.coreRunning) { running in
            if !running { minimized = false }
        }
    }
}

// Fullscreen view shown while the tunnel core is running. Mirrors the
// macOS sibling: the regular navigation collapses out of the way and
// the dashboard (or a placeholder for Xray, which has no clash API)
// takes the whole screen, with a draggable menu button offering either
// a return to the home screen or a disconnect.
private struct RunningRootView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var store = ConfigurationStore.shared
    let onHome: () -> Void

    var body: some View {
        ZStack {
            VStack {
                if store.selectedCore == .xray {
                    Text("Xray is running")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DashboardView()
                }
            }
            FloatingMenuButton(onHome: onHome, onStop: stopTunnel)
        }
    }

    private func stopTunnel() {
        Task { await tunnel.setEnabled(false, configuration: store.active) }
    }
}
