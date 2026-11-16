//
//  TunnelSettingsView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/17/26.
//

import SwiftUI

struct TunnelSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var tunnel = TunnelManager.shared

    private var settings: Binding<TunnelNetworkSettings> { $appState.tunnelNetworkSettings }

    var body: some View {
        Form {
            Section {
                Toggle("Include All Networks", isOn: $appState.tunnelIncludeAllNetworks)
            }

            Section {
                Toggle("Include Local Networks", isOn: $appState.tunnelIncludeLocalNetworks)
                Toggle("Include APNs", isOn: $appState.tunnelIncludeAPNs)
                Toggle("Include Cellular Services", isOn: $appState.tunnelIncludeCellularServices)
            }
            .disabled(!appState.tunnelIncludeAllNetworks)

            Section("Network Settings") {
                NavigationLink {
                    TunnelIPv4SettingsView()
                } label: {
                    summaryRow("IPv4", value: appState.tunnelNetworkSettings.ipv4.addresses.first ?? "")
                }
                NavigationLink {
                    TunnelIPv6SettingsView()
                } label: {
                    summaryRow("IPv6", isOn: appState.tunnelNetworkSettings.ipv6.isEnabled)
                }
                NavigationLink {
                    TunnelDNSSettingsView()
                } label: {
                    summaryRow("DNS", isOn: appState.tunnelNetworkSettings.dns.isEnabled)
                }
                NavigationLink {
                    TunnelProxySettingsView()
                } label: {
                    summaryRow("Proxy", isOn: appState.tunnelNetworkSettings.proxy.isEnabled)
                }
                SettingNumberField(title: "MTU", value: settings.mtu, range: TunnelNetworkSettings.mtuRange)
                SettingTextField(
                    title: "Remote Address",
                    placeholder: TunnelNetworkSettings().remoteAddress,
                    value: settings.remoteAddress,
                    validate: { IPNetwork.isAddress($0) }
                )
            }

            Section {
                Button("Reset to default") {
                    appState.tunnelNetworkSettings = TunnelNetworkSettings()
                }
                .disabled(appState.tunnelNetworkSettings == TunnelNetworkSettings())
            }
        }
        .navigationTitle("Tunnel")
        .navigationBarTitleDisplayMode(.inline)
        .tunnelSettingsPage()
        .onChange(of: appState.tunnelIncludeAllNetworks) { _ in
            Task { await tunnel.reconnect() }
        }
        .onChange(of: appState.tunnelIncludeLocalNetworks) { _ in
            Task { await tunnel.reconnect() }
        }
        .onChange(of: appState.tunnelIncludeAPNs) { _ in
            Task { await tunnel.reconnect() }
        }
        .onChange(of: appState.tunnelIncludeCellularServices) { _ in
            Task { await tunnel.reconnect() }
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isOn ? "On" : "Off")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Page behavior

private struct TunnelSettingsPage: ViewModifier {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var tunnel = TunnelManager.shared

    func body(content: Content) -> some View {
        content
            .disabled(tunnel.pendingReconnect)
            .onChange(of: appState.tunnelNetworkSettings) { _ in
                tunnel.reconnectSoon()
            }
    }
}

extension View {
    func tunnelSettingsPage() -> some View {
        modifier(TunnelSettingsPage())
    }
}
