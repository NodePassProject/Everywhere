//
//  ConnectionsView.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI

enum ConnectionSort: String, CaseIterable, Identifiable {
    case newest, downloadSpeed, uploadSpeed, download, upload, host

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .newest: return "Newest"
        case .downloadSpeed: return "Download Speed"
        case .uploadSpeed: return "Upload Speed"
        case .download: return "Downloaded"
        case .upload: return "Uploaded"
        case .host: return "Host"
        }
    }
}

struct ConnectionsView: View {
    @ObservedObject var model: ConnectionsModel
    let core: CoreType

    @State private var searchText = ""
    @State private var confirmsCloseAll = false
    @AppStorage("dashboard.connectionSort") private var sort: ConnectionSort = .newest

    var body: some View {
        Group {
            if model.isSupported {
                list
            } else {
                FeatureUnavailableView(title: "Connections", systemImage: "arrow.left.arrow.right", core: core)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Connections")
    }

    private var visible: [ConnectionInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var items = model.items
        if !query.isEmpty {
            items = items.filter { connection in
                connection.destination.localizedCaseInsensitiveContains(query)
                    || connection.chain.contains { $0.localizedCaseInsensitiveContains(query) }
                    || connection.ruleDescription.localizedCaseInsensitiveContains(query)
                    || connection.process.localizedCaseInsensitiveContains(query)
                    || connection.sourceIP.localizedCaseInsensitiveContains(query)
            }
        }
        func ordered<T: Comparable>(_ key: (ConnectionInfo) -> T, descending: Bool) -> [ConnectionInfo] {
            items.sorted {
                let (lhs, rhs) = (key($0), key($1))
                if lhs != rhs { return descending ? lhs > rhs : lhs < rhs }
                return $0.id < $1.id
            }
        }
        switch sort {
        case .newest: return ordered(\.start, descending: true)
        case .downloadSpeed: return ordered(\.downloadSpeed, descending: true)
        case .uploadSpeed: return ordered(\.uploadSpeed, descending: true)
        case .download: return ordered(\.download, descending: true)
        case .upload: return ordered(\.upload, descending: true)
        case .host: return ordered({ $0.destination.lowercased() }, descending: false)
        }
    }

    private var list: some View {
        let connections = visible
        return List {
            Section {
                ForEach(connections) { connection in
                    NavigationLink {
                        ConnectionDetailView(model: model, id: connection.id, snapshot: connection)
                    } label: {
                        ConnectionRow(connection: connection)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.close(connection)
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                    }
                }
            } header: {
                Text("\(connections.count) Active")
            }
        }
        .listStyle(.plain)
        .overlay {
            if connections.isEmpty {
                DashboardPlaceholder(
                    systemImage: "arrow.left.arrow.right",
                    title: searchText.isEmpty ? "No active connections" : "No matching connections"
                )
            }
        }
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(model.isPaused ? "Resume" : "Pause")

                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(ConnectionSort.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmsCloseAll = true
                    } label: {
                        Label("Close All Connections", systemImage: "xmark.circle")
                    }
                    .disabled(model.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog(
            "Close all connections?",
            isPresented: $confirmsCloseAll,
            titleVisibility: .visible
        ) {
            Button("Close All Connections", role: .destructive) { model.closeAll() }
        }
        .alert("Something went wrong", isPresented: actionErrorBinding, presenting: model.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
    }
}

private struct ConnectionRow: View {
    let connection: ConnectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: connection.destination)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(verbatim: connection.network.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !connection.chain.isEmpty {
                Text(verbatim: connection.chain.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack(spacing: 10) {
                figure("arrow.down", DashboardColor.download, DashboardFormat.bytes(connection.download), DashboardFormat.speed(Double(connection.downloadSpeed)))
                figure("arrow.up", DashboardColor.upload, DashboardFormat.bytes(connection.upload), DashboardFormat.speed(Double(connection.uploadSpeed)))
                Spacer(minLength: 0)
                Text(verbatim: DashboardFormat.duration(since: connection.start))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func figure(_ systemImage: String, _ color: Color, _ total: String, _ speed: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(verbatim: "\(total) · \(speed)")
                .lineLimit(1)
        }
    }
}

// MARK: - Detail

struct ConnectionDetailView: View {
    @ObservedObject var model: ConnectionsModel
    let id: String
    let snapshot: ConnectionInfo

    @Environment(\.dismiss) private var dismiss

    private var live: ConnectionInfo? {
        model.items.first { $0.id == id }
    }

    var body: some View {
        let connection = live ?? snapshot
        Form {
            Section {
                row("State") {
                    Text(live != nil ? "Active" : "Closed")
                        .foregroundStyle(live != nil ? Color.green : Color.secondary)
                }
                row("Started", verbatim: DashboardFormat.clock.string(from: connection.start))
                row("Duration", verbatim: DashboardFormat.duration(since: connection.start))
            }

            Section("Destination") {
                row("Host", verbatim: connection.host)
                row("Sniffed Host", verbatim: connection.sniffHost)
                row("IP Address", verbatim: connection.destinationIP)
                row("Port", verbatim: connection.destinationPort)
                row("Remote Address", verbatim: connection.remoteDestination)
                row("Network", verbatim: connection.network.uppercased())
            }

            Section("Source") {
                row("Address", verbatim: sourceAddress(connection))
                row("Inbound", verbatim: connection.inbound)
                row("Process", verbatim: connection.process)
                row("DNS Mode", verbatim: connection.dnsMode)
            }

            Section("Routing") {
                row("Rule", verbatim: connection.ruleDescription)
                row("Chain", verbatim: connection.chain.joined(separator: " → "))
            }

            Section("Traffic") {
                row("Downloaded", verbatim: DashboardFormat.bytes(connection.download))
                row("Uploaded", verbatim: DashboardFormat.bytes(connection.upload))
                if live != nil {
                    row("Download Speed", verbatim: DashboardFormat.speed(Double(connection.downloadSpeed)))
                    row("Upload Speed", verbatim: DashboardFormat.speed(Double(connection.uploadSpeed)))
                }
            }

            if let live {
                Section {
                    Button("Close Connection", role: .destructive) {
                        model.close(live)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(connection.destination)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceAddress(_ connection: ConnectionInfo) -> String {
        guard !connection.sourceIP.isEmpty else { return "" }
        let host = connection.sourceIP.contains(":") ? "[\(connection.sourceIP)]" : connection.sourceIP
        return connection.sourcePort.isEmpty ? host : "\(host):\(connection.sourcePort)"
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            value()
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, verbatim value: String) -> some View {
        if !value.isEmpty {
            row(title) {
                Text(verbatim: value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
