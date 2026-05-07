//
//  DNSSettingsView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Network
import SwiftUI

struct DNSSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var newServer: String = ""

    var body: some View {
        Form {
            Section {
                if appState.dnsServers.isEmpty {
                    Text("No servers configured.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.dnsServers, id: \.self) { server in
                        Text(server)
                    }
                    .onDelete { offsets in
                        var s = appState.dnsServers
                        s.remove(atOffsets: offsets)
                        appState.dnsServers = s
                    }
                    .onMove { source, destination in
                        var s = appState.dnsServers
                        s.move(fromOffsets: source, toOffset: destination)
                        appState.dnsServers = s
                    }
                }
            } header: {
                Text("DNS Servers")
            }

            Section {
                HStack {
                    TextField("Address", text: $newServer)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.numbersAndPunctuation)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(!isValid(newServer))
                }
            }

            Section {
                Button("Reset to Defaults") {
                    appState.dnsServers = AppState.defaultDNSServers
                }
            }
        }
        .navigationTitle("DNS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }

    private func add() {
        let trimmed = newServer.trimmingCharacters(in: .whitespaces)
        guard isValid(trimmed), !appState.dnsServers.contains(trimmed) else { return }
        appState.dnsServers.append(trimmed)
        newServer = ""
    }

    private func isValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return IPv4Address(s) != nil || IPv6Address(s) != nil
    }
}
