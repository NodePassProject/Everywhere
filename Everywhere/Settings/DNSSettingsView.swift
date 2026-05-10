//
//  DNSSettingsView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI
import Network

private struct DNSServerDraft: Identifiable, Equatable {
    let id = UUID()
    var value: String
}

struct DNSSettingsView: View {
    @Environment(\.editMode) private var editMode
    
    @ObservedObject private var appState = AppState.shared
    @State private var serverDrafts: [DNSServerDraft] = []
    
    private var isEditing: Bool {
        if editMode?.wrappedValue.isEditing == true { return true }
        return false
    }

    var body: some View {
        Form {
            Section("DNS Servers") {
                ForEach($serverDrafts) { $draft in
                    if isEditing == true {
                        TextField("Address", text: $draft.value)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        Text(draft.value)
                    }
                }
                .onDelete { offsets in
                    serverDrafts.remove(atOffsets: offsets)
                    save()
                }
                .onMove { source, destination in
                    serverDrafts.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            }

            Section {
                Button("Reset to default") {
                    reset()
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
        .onAppear { loadInitial() }
        .onChange(of: isEditing) { newValue in
            if newValue {
                serverDrafts.append(DNSServerDraft(value: ""))
            } else {
                save()
            }
        }
    }
    
    private func loadInitial() {
        serverDrafts = appState.dnsServers.map { DNSServerDraft(value: $0) }
    }

    private func save() {
        serverDrafts = serverDrafts
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let servers = serverDrafts
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
        appState.dnsServers = servers
    }
    
    private func reset() {
        appState.dnsServers = AppState.defaultDNSServers
    }

    private func isValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return IPv4Address(s) != nil || IPv6Address(s) != nil
    }
}
