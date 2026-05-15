//
//  SettingsView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var tunnel = TunnelManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section("VPN") {
                    Toggle(isOn: $appState.alwaysOnEnabled) {
                        Label("Always On", systemImage: "bolt")
                    }
                    .disabled(tunnel.pendingReconnect)
                }
                
                Section("Network") {
                    NavigationLink {
                        DNSSettingsView()
                    } label: {
                        Label("DNS", systemImage: "network")
                    }
                }

                Section("IO") {
                    NavigationLink {
                        ResourcesView()
                    } label: {
                        Label("Resources", systemImage: "folder")
                    }
                }
                
                Section("About") {
                    Link(destination: URL(string: "https://t.me/everywhere_proxy")!) {
                        HStack {
                            HStack {
                                Image("TelegramSymbol")
                                    .interpolation(.high)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 25)
                                Text("Join Telegram Group")
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        AcknowledgementView()
                    } label: {
                        Label("Acknowledgements", systemImage: "heart")
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: appState.alwaysOnEnabled) { _ in
                Task { await tunnel.reconnect() }
            }
        }
        .navigationViewStyle(.stack)
    }
}
