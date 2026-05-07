//
//  HomeView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

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
                            if tunnel.state != .disconnected {
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
        }
        .navigationViewStyle(.stack)
    }

    private var statusText: String {
        switch tunnel.state {
        case .loading: return String(localized: "Loading")
        case .disconnected: return String(localized: "Disconnected")
        case .connecting: return String(localized: "Connecting")
        case .connected: return String(localized: "Connected")
        case .disconnecting: return String(localized: "Disconnecting")
        case .failed: return String(localized: "Failed")
        }
    }

    private var isToggleDisabled: Bool {
        switch tunnel.state {
        case .connecting, .disconnecting, .loading: return true
        default: return store.active == nil
        }
    }

    private var tunnelToggleBinding: Binding<Bool> {
        Binding(
            get: { tunnel.state == .connected || tunnel.state == .connecting },
            set: { newValue in
                guard let active = store.active else { return }
                Task {
                    await tunnel.setEnabled(newValue, configuration: active)
                }
            }
        )
    }
}
