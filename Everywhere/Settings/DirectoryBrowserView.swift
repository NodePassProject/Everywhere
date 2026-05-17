//
//  DirectoryBrowserView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct DirectoryBrowserView: View {
    let url: URL
    let title: String

    @State private var entries: [ResourceEntry] = []
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if entries.isEmpty {
                    Text("No items")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                    .onDelete(perform: delete)
                }
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }
                Button {
                    promptCreateFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle(title)
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
        .onAppear { reload() }
    }

    @ViewBuilder
    private func row(for entry: ResourceEntry) -> some View {
        switch entry.kind {
        case .directory:
            NavigationLink {
                DirectoryBrowserView(url: entry.url, title: entry.name)
            } label: {
                Label {
                    Text(entry.name)
                } icon: {
                    Image(systemName: "folder.fill")
                }
            }
        case .file:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    if let size = entry.formattedSize {
                        Text(size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "doc.fill")
            }
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
            entries = try ResourcesStore.list(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            do {
                try ResourcesStore.delete(entries[offset])
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
            for source in urls {
                do {
                    try ResourcesStore.importFile(from: source, into: url)
                } catch {
                    errorMessage = "Could not import \(source.lastPathComponent): \(error.localizedDescription)"
                    break
                }
            }
            reload()
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func promptCreateFolder() {
        NameInputAlert.present(
            title: String(localized: "New Folder"),
            message: String(localized: "Enter a name for the new folder."),
            placeholder: String(localized: "Name")
        ) { name in
            do {
                try ResourcesStore.createFolder(named: name, in: url)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
