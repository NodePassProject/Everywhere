//
//  ConfigurationsView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI

struct ConfigurationsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var tunnel = TunnelManager.shared
    @State private var pendingDelete: Configuration?
    @State private var blockedAlert = false

    private var activeID: UUID? { store.activeIDByCoreType[store.selectedCore] }

    var body: some View {
        List {
            ForEach(store.configurationsForSelectedCore) { config in
                NavigationLink {
                    ConfigEditorScreen(configuration: config)
                } label: {
                    row(for: config)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = config
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        promptRename(config)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("\(store.selectedCore.displayName) configurations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    promptCreate()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Tunnel is running", isPresented: $blockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stop the tunnel before switching the active configuration or deleting the active one.")
        }
        .confirmationDialog(
            "Delete configuration?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { config in
            Button("Delete \"\(config.name)\"", role: .destructive) {
                delete(config)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func row(for config: Configuration) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activeID == config.id ? "checkmark.circle.fill" : "circle")
                .foregroundColor(activeID == config.id ? .accentColor : .secondary)
                .font(.title3)
                .onTapGesture {
                    activate(config)
                }
            Text(config.name)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func activate(_ config: Configuration) {
        if tunnel.state != .disconnected {
            blockedAlert = true
            return
        }
        store.setActive(config)
    }

    private func delete(_ config: Configuration) {
        defer { pendingDelete = nil }
        if tunnel.state != .disconnected, activeID == config.id {
            blockedAlert = true
            return
        }
        store.delete(config)
    }

    private func promptCreate() {
        let core = store.selectedCore
        NameInputAlert.present(
            title: "New \(core.displayName) configuration",
            message: "Enter a name for the new configuration.",
            placeholder: "Name"
        ) { name in
            store.create(name: name, type: core, content: core.defaultConfig)
        }
    }

    private func promptRename(_ config: Configuration) {
        NameInputAlert.present(
            title: "Rename configuration",
            initialValue: config.name
        ) { name in
            store.update(config, name: name)
        }
    }
}
