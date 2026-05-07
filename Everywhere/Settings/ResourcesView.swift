//
//  ResourcesView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ResourcesView: View {
    @State private var selectedCore: CoreType = ConfigurationStore.shared.selectedCore
    @State private var files: [ResourceFile] = []
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Core", selection: $selectedCore) {
                    ForEach(CoreType.allCases) { core in
                        Text(core.displayName).tag(core)
                    }
                }
            }

            Section {
                if files.isEmpty {
                    Text("No files")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(files) { file in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                Text(file.formattedSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("Files")
            } footer: {
                Text(footerText)
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("Resources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.data, .json, .yaml, .text, .xml, .item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Resources error", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .onAppear {
            selectedCore = ConfigurationStore.shared.selectedCore
            reload()
        }
        .onChange(of: selectedCore) { _ in reload() }
    }

    private var footerText: String {
        switch selectedCore {
        case .xray:
            return """
            Xray-core picks files up here via xray.location.asset (geoip.dat, geosite.dat) and xray.location.cert (PEMs).
            """
        case .singbox:
            return """
            sing-box resolves relative paths in your config (cache_file.path, geoip.path, geosite.path, rule_set[].path) here.
            """
        case .mihomo:
            return """
            mihomo's $HOME/.config/mihomo is overridden to this directory (cache.db, GeoIP.dat, GeoSite.dat, ASN.mmdb, etc).
            """
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func reload() {
        do {
            files = try ResourcesStore.list(for: selectedCore)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            do {
                try ResourcesStore.delete(named: files[offset].name, for: selectedCore)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        reload()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    try ResourcesStore.importFile(from: url, for: selectedCore)
                } catch {
                    errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
                    break
                }
            }
            reload()
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }
}
