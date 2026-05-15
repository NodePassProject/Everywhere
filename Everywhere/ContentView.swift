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
        ZStack {
            if tunnel.coreRunning {
                RunningRootView()
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
    }
}

// Fullscreen view shown while the tunnel core is running. Mirrors the
// macOS sibling: the regular navigation collapses out of the way and
// the dashboard (or a placeholder for Xray, which has no clash API)
// takes the whole screen, with a draggable stop button as the only
// way out.
private struct RunningRootView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var store = ConfigurationStore.shared

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
            FloatingStopButton(action: stopTunnel)
        }
    }

    private func stopTunnel() {
        Task { await tunnel.setEnabled(false, configuration: store.active) }
    }
}
