//
//  ConfigurationsView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var tunnel = TunnelManager.shared
    @State private var pendingDelete: Configuration?
    @State private var blockedAlert = false
    @State private var fileImporting = false
    @State private var isDownloading = false
    @State private var importErrorMessage: String?

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
                if isDownloading {
                    ProgressView()
                } else {
                    Menu {
                        Button {
                            promptCreate()
                        } label: {
                            Label("New", systemImage: "plus")
                        }
                        Button {
                            fileImporting = true
                        } label: {
                            Label("Import from file", systemImage: "doc")
                        }
                        Button {
                            promptDownload()
                        } label: {
                            Label("Download from URL", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $fileImporting,
            allowedContentTypes: [.json, .yaml, .text, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Tunnel is running", isPresented: $blockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stop the tunnel before switching the active configuration or deleting the active one.")
        }
        .alert("Import error", isPresented: importErrorBinding, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .confirmationDialog(
            "Delete configuration?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { config in
            Button("Delete \(config.name)", role: .destructive) {
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

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
    }

    private func activate(_ config: Configuration) {
        if tunnel.status.isActive {
            blockedAlert = true
            return
        }
        store.setActive(config)
    }

    private func delete(_ config: Configuration) {
        defer { pendingDelete = nil }
        if tunnel.status.isActive, activeID == config.id {
            blockedAlert = true
            return
        }
        store.delete(config)
    }

    private func promptCreate() {
        let core = store.selectedCore
        NameInputAlert.present(
            title: String(localized: "New \(core.displayName) configuration"),
            message: String(localized: "Enter a name for the new configuration."),
            placeholder: String(localized: "Name")
        ) { name in
            store.create(name: name, type: core, content: core.defaultConfig)
        }
    }

    private func promptRename(_ config: Configuration) {
        NameInputAlert.present(
            title: String(localized: "Rename configuration"),
            initialValue: config.name
        ) { name in
            store.update(config, name: name)
        }
    }

    private func promptDownload() {
        let core = store.selectedCore
        URLInputAlert.present(
            title: String(localized: "Download \(core.displayName) configuration"),
            message: String(localized: "Enter a URL to download the configuration from.")
        ) { url in
            download(from: url, for: core)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let core = store.selectedCore
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                store.create(name: derivedName(from: url), type: core, content: content)
            } catch {
                importErrorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        case .failure(let err):
            importErrorMessage = err.localizedDescription
        }
    }

    private func download(from url: URL, for core: CoreType) {
        isDownloading = true
        Task {
            defer { Task { @MainActor in isDownloading = false } }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(
                        domain: "EverywhereDownload",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."]
                    )
                }
                guard let content = String(data: data, encoding: .utf8) else {
                    throw NSError(
                        domain: "EverywhereDownload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Response is not valid UTF-8 text."]
                    )
                }
                store.create(name: derivedName(from: url), type: core, content: content)
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func derivedName(from url: URL) -> String {
        let stripped = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty, stripped != "/" {
            return stripped
        }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return String(localized: "Imported Configuration")
    }
}
