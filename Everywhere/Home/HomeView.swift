//
//  HomeView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import NetworkExtension
import SwiftUI

struct HomeView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var tunnel = TunnelManager.shared
    @State private var coreSwitchBlocked = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: tunnelToggleBinding) {
                        HStack {
                            Image(store.selectedCore.rawValue)
                                .resizable()
                                .frame(width: 25, height: 25)
                            Text("Tunnel")
                            Spacer()
                            Text(statusText)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(isToggleDisabled)
                }

                Section {
                    ForEach(CoreType.allCases) { core in
                        HStack {
                            Image(core.rawValue)
                                .resizable()
                                .frame(width: 25, height: 25)
                            Text(core.displayName)
                            if store.selectedCore == core {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.caption.bold())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if tunnel.status.isActive {
                                coreSwitchBlocked = true
                            } else {
                                store.selectedCore = core
                            }
                        }
                    }
                }

                NavigationLink {
                    ConfigurationsView()
                } label: {
                    HStack {
                        Text("Configurations")
                            .fixedSize()
                        Spacer()
                        Text(store.active?.name ?? "None")
                            .foregroundColor(.secondary)
                            .truncationMode(.middle)
                    }
                    .lineLimit(1)
                }
            }
            .navigationTitle("Home")
            .alert("Tunnel is running", isPresented: $coreSwitchBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Stop the tunnel before switching cores.")
            }
            .alert(
                "Connection failed",
                isPresented: errorAlertBinding,
                presenting: tunnel.lastError
            ) { _ in
                Button("OK", role: .cancel) { tunnel.clearLastError() }
            } message: { message in
                Text(message)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { tunnel.lastError != nil },
            set: { if !$0 { tunnel.clearLastError() } }
        )
    }

    private var statusText: String {
        if !tunnel.isReady { return String(localized: "Loading") }
        switch tunnel.status {
        case .connected: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting")
        case .disconnecting: return String(localized: "Disconnecting")
        case .reasserting: return String(localized: "Reconnecting")
        case .disconnected: return String(localized: "Disconnected")
        case .invalid: return String(localized: "Not Configured")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private var isToggleDisabled: Bool {
        if !tunnel.isReady { return true }
        if tunnel.status.isTransitioning { return true }
        return store.active == nil
    }

    private var tunnelToggleBinding: Binding<Bool> {
        Binding(
            get: { tunnel.status == .connected || tunnel.status == .connecting },
            set: { newValue in
                guard let active = store.active else { return }
                Task {
                    await tunnel.setEnabled(newValue, configuration: active)
                }
            }
        )
    }
}
