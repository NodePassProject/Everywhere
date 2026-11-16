//
//  OverviewView.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: OverviewModel
    let core: CoreType

    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var showsOutboundTraffic = false

    var body: some View {
        List {
            if case .failed(let message) = model.link {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Can't reach the core")
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                trafficCard
            }

            Section("Status") {
                coreRow
                if let started = tunnel.connectedDate {
                    LabeledRow("Uptime", systemImage: "clock") {
                        Text(started, style: .timer)
                            .monospacedDigit()
                    }
                }
                LabeledRow("Extension Memory", systemImage: "memorychip") {
                    if let runtime = model.runtime {
                        Text(verbatim: memoryDescription(runtime))
                            .monospacedDigit()
                    } else {
                        Text(verbatim: "—")
                    }
                }
                FeatureRow(feature: .connections, core: core, title: "Connections", systemImage: "arrow.left.arrow.right") {
                    LabeledRow("Connections", systemImage: "arrow.left.arrow.right") {
                        Text(verbatim: model.connectionCount.map(String.init) ?? "—")
                            .monospacedDigit()
                    }
                }
            }

            Section("Outbound Mode") {
                FeatureRow(feature: .outboundMode, core: core, title: "Outbound Mode", systemImage: "arrow.triangle.branch") {
                    modePicker
                }
            }

            Section("Outbound Traffic") {
                FeatureRow(feature: .outboundTraffic, core: core, title: "Per-Outbound Totals", systemImage: "chart.bar") {
                    outboundTraffic
                }
            }

            Section("Tools") {
                toolRow(.flushFakeIP, title: "Flush Fake-IP Cache", systemImage: "eraser", success: String(localized: "Fake-IP cache flushed."))
                toolRow(.flushDNSCache, title: "Flush DNS Cache", systemImage: "arrow.counterclockwise", success: String(localized: "DNS cache flushed."))
                toolRow(.updateGeoData, title: "Update GEO Databases", systemImage: "globe", success: String(localized: "GEO databases updated."))
                FeatureRow(feature: .dnsQuery, core: core, title: "DNS Query", systemImage: "magnifyingglass") {
                    NavigationLink {
                        DNSQueryView(model: model)
                    } label: {
                        Label("DNS Query", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.dashboardHidden = true
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Go Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        Task { await tunnel.setEnabled(false, configuration: store.active) }
                    } label: {
                        Label("Stop VPN", systemImage: "stop.fill")
                    }
                } label: {
                    Image(systemName: "power")
                }
                .tint(.red)
                .accessibilityLabel("Stop VPN")
            }
        }
        .alert(item: $model.notice) { notice in
            Alert(
                title: Text(notice.isError ? "Something went wrong" : "Done"),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Traffic

    private var trafficCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                speedColumn(
                    title: "Upload",
                    systemImage: "arrow.up",
                    color: DashboardColor.upload,
                    rate: model.rate.up,
                    total: model.totals?.up
                )
                Spacer(minLength: 12)
                speedColumn(
                    title: "Download",
                    systemImage: "arrow.down",
                    color: DashboardColor.download,
                    rate: model.rate.down,
                    total: model.totals?.down
                )
            }
            TrafficChart(samples: model.history)
                .frame(height: 72)
        }
        .padding(.vertical, 6)
    }

    private func speedColumn(
        title: LocalizedStringKey,
        systemImage: String,
        color: Color,
        rate: Double,
        total: Int64?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(color)
            Text(verbatim: DashboardFormat.speed(rate))
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let total {
                Text("Total \(DashboardFormat.bytes(total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Status

    private var coreRow: some View {
        HStack {
            Label {
                Text(verbatim: core.displayName)
            } icon: {
                Image(core.rawValue)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            Spacer()
            if let version = displayVersion {
                Text(verbatim: version)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var displayVersion: String? {
        guard let version = model.version, !version.isEmpty else { return nil }
        switch core {
        case .mihomo where version == "1.10.0": return nil
        case .singbox where version == "unknown": return nil
        default: return version
        }
    }

    private func memoryDescription(_ runtime: ExtensionRuntime) -> String {
        let used = DashboardFormat.bytes(runtime.footprint)
        guard runtime.available > 0 else { return used }
        return "\(used) / \(DashboardFormat.bytes(runtime.footprint + runtime.available))"
    }

    // MARK: Mode

    @ViewBuilder
    private var modePicker: some View {
        if model.modes.isEmpty {
            HStack {
                Label("Outbound Mode", systemImage: "arrow.triangle.branch")
                Spacer()
                ProgressView()
            }
        } else {
            let selection = Binding(
                get: { model.mode ?? "" },
                set: { model.setMode($0) }
            )
            if model.modes.count <= 4 {
                Picker("Outbound Mode", selection: selection) {
                    ForEach(model.modes, id: \.self) { mode in
                        Text(verbatim: modeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker(selection: selection) {
                    ForEach(model.modes, id: \.self) { mode in
                        Text(verbatim: modeTitle(mode)).tag(mode)
                    }
                } label: {
                    Label("Outbound Mode", systemImage: "arrow.triangle.branch")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode.lowercased() {
        case "rule": return String(localized: "Rule")
        case "global": return String(localized: "Global")
        case "direct": return String(localized: "Direct")
        default: return mode
        }
    }

    // MARK: Outbound traffic

    @ViewBuilder
    private var outboundTraffic: some View {
        if model.outboundTraffic.isEmpty {
            Text("No traffic yet")
                .foregroundStyle(.secondary)
        } else {
            let visible = showsOutboundTraffic ? model.outboundTraffic : Array(model.outboundTraffic.prefix(5))
            ForEach(visible, id: \.tag) { entry in
                HStack {
                    Text(verbatim: entry.tag)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Label {
                            Text(verbatim: DashboardFormat.bytes(entry.totals.up))
                        } icon: {
                            Image(systemName: "arrow.up").foregroundStyle(DashboardColor.upload)
                        }
                        Label {
                            Text(verbatim: DashboardFormat.bytes(entry.totals.down))
                        } icon: {
                            Image(systemName: "arrow.down").foregroundStyle(DashboardColor.download)
                        }
                    }
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            if model.outboundTraffic.count > 5 {
                Button(showsOutboundTraffic ? "Show Less" : "Show All \(model.outboundTraffic.count)") {
                    showsOutboundTraffic.toggle()
                }
            }
        }
    }

    // MARK: Tools

    private func toolRow(
        _ feature: DashboardFeature,
        title: LocalizedStringKey,
        systemImage: String,
        success: String
    ) -> some View {
        FeatureRow(feature: feature, core: core, title: title, systemImage: systemImage) {
            Button {
                model.run(feature, success: success)
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    if model.busyTools.contains(feature) {
                        ProgressView()
                    }
                }
            }
            .disabled(model.busyTools.contains(feature))
        }
    }
}

private struct LabeledRow<Value: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: Value

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.systemImage = systemImage
        self.value = value()
    }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            value
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: LabelStyleConfiguration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - DNS query

struct DNSQueryView: View {
    let model: OverviewModel

    private static let recordTypes = ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "HTTPS"]

    @State private var name = ""
    @State private var type = "A"
    @State private var answers: [DNSAnswer] = []
    @State private var message: String?
    @State private var isQuerying = false

    var body: some View {
        Form {
            Section {
                TextField("example.com", text: $name)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit(query)
                Picker("Record Type", selection: $type) {
                    ForEach(Self.recordTypes, id: \.self) { Text(verbatim: $0).tag($0) }
                }
            }

            Section {
                Button(action: query) {
                    HStack {
                        Text("Query")
                        Spacer()
                        if isQuerying { ProgressView() }
                    }
                }
                .disabled(trimmedName.isEmpty || isQuerying)
            }

            if let message {
                Section {
                    Text(verbatim: message)
                        .foregroundStyle(.secondary)
                }
            }

            if !answers.isEmpty {
                Section("Answers") {
                    ForEach(answers) { answer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: answer.data)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            Text(verbatim: "\(answer.type) · TTL \(answer.ttl) · \(answer.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("DNS Query")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func query() {
        let name = trimmedName
        guard !name.isEmpty, !isQuerying else { return }
        isQuerying = true
        message = nil
        Task {
            defer { isQuerying = false }
            do {
                answers = try await model.queryDNS(name: name, type: type)
                message = answers.isEmpty ? String(localized: "No records.") : nil
            } catch {
                answers = []
                message = error.localizedDescription
            }
        }
    }
}
