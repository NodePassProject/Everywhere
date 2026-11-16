//
//  TunnelNetworkSettingsViews.swift
//  Everywhere
//
//  Created by NodePassProject on 11/16/26.
//

import SwiftUI

// MARK: - IPv4

struct TunnelIPv4SettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private var ipv4: Binding<TunnelNetworkSettings.IPv4> { $appState.tunnelNetworkSettings.ipv4 }

    var body: some View {
        Form {
            EditableListSection(
                title: "Addresses",
                placeholder: "10.0.0.1/24",
                items: ipv4.addresses,
                minimumCount: 1,
                validate: { IPNetwork.isInterfaceAddress($0, family: .v4) }
            )
            EditableListSection(
                title: "Included Routes",
                placeholder: "10.0.0.0/8",
                items: ipv4.includedRoutes,
                validate: { IPNetwork.parse($0, family: .v4) != nil }
            )
            EditableListSection(
                title: "Excluded Routes",
                placeholder: "192.168.0.0/16",
                items: ipv4.excludedRoutes,
                validate: { IPNetwork.parse($0, family: .v4) != nil }
            )
        }
        .navigationTitle("IPv4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .tunnelSettingsPage()
    }
}

// MARK: - IPv6

struct TunnelIPv6SettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private var ipv6: Binding<TunnelNetworkSettings.IPv6> { $appState.tunnelNetworkSettings.ipv6 }

    var body: some View {
        Form {
            Section {
                Toggle("IPv6", isOn: ipv6.isEnabled)
            }
            if appState.tunnelNetworkSettings.ipv6.isEnabled {
                EditableListSection(
                    title: "Addresses",
                    placeholder: "fd12::1/64",
                    items: ipv6.addresses,
                    minimumCount: 1,
                    validate: { IPNetwork.isInterfaceAddress($0, family: .v6) }
                )
                EditableListSection(
                    title: "Included Routes",
                    placeholder: "2000::/3",
                    items: ipv6.includedRoutes,
                    validate: { IPNetwork.parse($0, family: .v6) != nil }
                )
                EditableListSection(
                    title: "Excluded Routes",
                    placeholder: "fc00::/7",
                    items: ipv6.excludedRoutes,
                    validate: { IPNetwork.parse($0, family: .v6) != nil }
                )
            }
        }
        .navigationTitle("IPv6")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .tunnelSettingsPage()
    }
}

// MARK: - DNS

struct TunnelDNSSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private var dns: Binding<TunnelNetworkSettings.DNS> { $appState.tunnelNetworkSettings.dns }
    private var current: TunnelNetworkSettings.DNS { appState.tunnelNetworkSettings.dns }

    var body: some View {
        Form {
            Section {
                Toggle("DNS", isOn: dns.isEnabled)
            }
            if current.isEnabled {
                Section {
                    Picker("Protocol", selection: dns.transport) {
                        Text("Cleartext").tag(TunnelNetworkSettings.DNSTransport.cleartext)
                        Text(verbatim: "TLS").tag(TunnelNetworkSettings.DNSTransport.tls)
                        Text(verbatim: "HTTPS").tag(TunnelNetworkSettings.DNSTransport.https)
                    }
                    switch current.transport {
                    case .cleartext:
                        EmptyView()
                    case .tls:
                        SettingTextField(
                            title: "Server Name",
                            placeholder: "dns.example.com",
                            value: dns.serverName,
                            validate: IPNetwork.isHostname
                        )
                    case .https:
                        SettingTextField(
                            title: "Server URL",
                            placeholder: "https://dns.example.com/dns-query",
                            value: dns.serverURL,
                            validate: { URL(string: $0)?.scheme == "https" && URL(string: $0)?.host != nil }
                        )
                    }
                }
                EditableListSection(
                    title: "DNS Servers",
                    placeholder: "9.9.9.9",
                    items: dns.servers,
                    minimumCount: 1,
                    validate: { IPNetwork.isAddress($0) }
                )
                Section {
                    SettingTextField(
                        title: "Domain Name",
                        placeholder: "example.com",
                        value: dns.domainName,
                        validate: { $0.isEmpty || IPNetwork.isHostname($0) }
                    )
                }
                EditableListSection(
                    title: "Search Domains",
                    placeholder: "example.com",
                    items: dns.searchDomains,
                    validate: IPNetwork.isHostname
                )
                EditableListSection(
                    title: "Match Domains",
                    placeholder: "example.com",
                    items: dns.matchDomains,
                    validate: IPNetwork.isHostname
                )
                Section {
                    Toggle("Match Domains No Search", isOn: dns.matchDomainsNoSearch)
                }
            }
        }
        .navigationTitle("DNS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .tunnelSettingsPage()
    }
}

// MARK: - Proxy

struct TunnelProxySettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private var proxy: Binding<TunnelNetworkSettings.Proxy> { $appState.tunnelNetworkSettings.proxy }
    private var current: TunnelNetworkSettings.Proxy { appState.tunnelNetworkSettings.proxy }

    var body: some View {
        Form {
            Section {
                Toggle("Proxy", isOn: proxy.isEnabled)
            }
            if current.isEnabled {
                Section {
                    Toggle("Auto Configuration", isOn: proxy.autoConfigurationEnabled)
                    if current.autoConfigurationEnabled {
                        SettingTextField(
                            title: "URL",
                            placeholder: "https://example.com/proxy.pac",
                            value: proxy.autoConfigurationURL,
                            validate: { $0.isEmpty || URL(string: $0)?.scheme != nil }
                        )
                        NavigationLink {
                            TunnelProxyScriptView()
                        } label: {
                            Text(verbatim: "JavaScript")
                        }
                    }
                }
                Section {
                    Toggle(isOn: proxy.httpEnabled) { Text(verbatim: "HTTP") }
                    if current.httpEnabled {
                        SettingTextField(
                            title: "Server",
                            placeholder: "127.0.0.1",
                            value: proxy.httpServer,
                            validate: IPNetwork.isHostname
                        )
                        SettingNumberField(title: "Port", value: proxy.httpPort, range: 1...65535)
                    }
                }
                Section {
                    Toggle(isOn: proxy.httpsEnabled) { Text(verbatim: "HTTPS") }
                    if current.httpsEnabled {
                        SettingTextField(
                            title: "Server",
                            placeholder: "127.0.0.1",
                            value: proxy.httpsServer,
                            validate: IPNetwork.isHostname
                        )
                        SettingNumberField(title: "Port", value: proxy.httpsPort, range: 1...65535)
                    }
                }
                Section {
                    Toggle("Exclude Simple Hostnames", isOn: proxy.excludeSimpleHostnames)
                }
                EditableListSection(
                    title: "Exception List",
                    placeholder: "*.local",
                    items: proxy.exceptionList,
                    validate: IPNetwork.isHostname
                )
                EditableListSection(
                    title: "Match Domains",
                    placeholder: "example.com",
                    items: proxy.matchDomains,
                    validate: IPNetwork.isHostname
                )
            }
        }
        .navigationTitle("Proxy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .tunnelSettingsPage()
    }
}

struct TunnelProxyScriptView: View {
    @ObservedObject private var appState = AppState.shared

    @State private var draft = ""

    var body: some View {
        TextEditor(text: $draft)
            .font(.footnote.monospaced())
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 12)
            .navigationTitle(Text(verbatim: "JavaScript"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = appState.tunnelNetworkSettings.proxy.autoConfigurationJavaScript }
            .onDisappear { appState.tunnelNetworkSettings.proxy.autoConfigurationJavaScript = draft }
            .tunnelSettingsPage()
    }
}
