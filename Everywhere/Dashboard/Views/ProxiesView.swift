//
//  ProxiesView.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI

enum ProxySort: String, CaseIterable, Identifiable {
    case configuration, latency, name

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .configuration: return "Configuration Order"
        case .latency: return "Latency"
        case .name: return "Name"
        }
    }
}

struct ProxiesView: View {
    @ObservedObject var model: ProxiesModel

    private enum Page: Hashable {
        case proxies, providers
    }

    @State private var page: Page = .proxies
    @State private var searchText = ""
    @State private var showsSettings = false
    @AppStorage(DashboardPreferences.sortKey) private var sort: ProxySort = .configuration
    @AppStorage(DashboardPreferences.hideUnavailableKey) private var hidesUnavailable = false

    private var core: CoreType { model.core }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("View", selection: $page) {
                    Text("Proxies").tag(Page.proxies)
                    Text("Providers").tag(Page.providers)
                }
                .pickerStyle(.segmented)

                switch page {
                case .proxies: groups
                case .providers: providers
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Proxies")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort Nodes By", selection: $sort) {
                        ForEach(ProxySort.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Hide Unavailable Nodes", isOn: $hidesUnavailable)
                    Divider()
                    Button {
                        model.expanded.removeAll()
                    } label: {
                        Label("Collapse All", systemImage: "rectangle.compress.vertical")
                    }
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Dashboard Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationView {
                DashboardSettingsView(core: core)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        .alert("Something went wrong", isPresented: actionErrorBinding, presenting: model.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
    }

    // MARK: Groups

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var visibleGroups: [ProxyGroup] {
        guard !query.isEmpty else { return model.topology.groups }
        return model.topology.groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.members.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func visibleMembers(of group: ProxyGroup) -> [String] {
        var members = group.members
        if !query.isEmpty, !group.name.localizedCaseInsensitiveContains(query) {
            members = members.filter { $0.localizedCaseInsensitiveContains(query) }
        }
        if hidesUnavailable {
            members = members.filter { $0 == group.selected || model.topology.delay(of: $0) != .failed }
        }
        switch sort {
        case .configuration:
            break
        case .latency:
            members = members.enumerated().sorted {
                let (lhs, rhs) = (model.topology.delay(of: $0.element).sortKey, model.topology.delay(of: $1.element).sortKey)
                return lhs != rhs ? lhs < rhs : $0.offset < $1.offset
            }.map(\.element)
        case .name:
            members.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return members
    }

    @ViewBuilder
    private var groups: some View {
        if !model.isLoaded {
            if let error = model.loadError {
                DashboardPlaceholder(systemImage: "exclamationmark.triangle", title: "Can't load proxies", message: error)
            } else {
                ProgressView()
                    .padding(.vertical, 40)
            }
        } else {
            ForEach(visibleGroups) { group in
                ProxyGroupCard(
                    group: group,
                    members: visibleMembers(of: group),
                    model: model,
                    isExpanded: model.expanded.contains(group.name) || !query.isEmpty
                )
            }
            if visibleGroups.isEmpty {
                DashboardPlaceholder(systemImage: "magnifyingglass", title: "No matching proxies")
            }
            if core == .xray, !model.topology.groups.contains(where: { !$0.isSynthetic }) {
                Text("Define `routing.balancers` to switch nodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Providers

    @ViewBuilder
    private var providers: some View {
        if !DashboardFeature.proxyProviders.isAvailable(on: core) {
            FeatureUnavailableView(title: "Proxy Providers", systemImage: "shippingbox", core: core)
                .frame(minHeight: 320)
        } else if model.providers.isEmpty {
            DashboardPlaceholder(systemImage: "shippingbox", title: "No proxy providers")
        } else {
            ForEach(model.providers) { provider in
                ProxyProviderCard(
                    provider: provider,
                    isBusy: model.busyProviders.contains(provider.name),
                    onUpdate: { model.updateProvider(provider.name) },
                    onHealthCheck: { model.healthCheckProvider(provider.name) }
                )
            }
        }
    }
}

// MARK: - Group card

private struct ProxyGroupCard: View {
    let group: ProxyGroup
    let members: [String]
    @ObservedObject var model: ProxiesModel
    let isExpanded: Bool

    private var topology: ProxyTopology { model.topology }
    private var isTesting: Bool { model.testingGroups.contains(group.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                    .padding(.leading, 14)
                detail
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if model.expanded.contains(group.name) {
                        model.expanded.remove(group.name)
                    } else {
                        model.expanded.insert(group.name)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(verbatim: group.name)
                                .font(.headline)
                                .lineLimit(1)
                            if group.pinned != nil {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Pinned")
                            }
                        }
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !group.isSynthetic, let selected = group.selected {
                            RouteLabel(text: route(from: selected))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if !group.isSynthetic, let selected = group.selected {
                        DelayLabel(delay: topology.delay(of: selected))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.test(group: group)
            } label: {
                Group {
                    if isTesting {
                        ProgressView()
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(isTesting || group.members.isEmpty)
            .accessibilityLabel("Test Latency")

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contextMenu {
            if group.pinned != nil {
                Button {
                    model.unpin(group)
                } label: {
                    Label("Resume Automatic Selection", systemImage: "pin.slash")
                }
            }
        }
    }

    private var subtitle: String {
        let count = String(group.members.count)
        return group.type.isEmpty ? count : "\(group.type) · \(count)"
    }

    private func route(from selected: String) -> String {
        let leaf = topology.leaf(of: selected)
        return leaf == selected ? selected : "\(selected) → \(leaf)"
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pinned = group.pinned {
                HStack {
                    Label("Pinned to \(pinned)", systemImage: "pin.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Resume Auto") { model.unpin(group) }
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                }
            }
            if members.isEmpty {
                Text("No nodes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                    ForEach(members, id: \.self) { member in
                        ProxyNodeCell(
                            name: member,
                            node: topology.nodes[member],
                            delay: topology.delay(of: member),
                            isSelected: !group.isSynthetic && group.selected == member,
                            isPinned: group.pinned == member,
                            isDefault: group.isSynthetic && group.selected == member,
                            isTesting: model.testingNodes.contains(topology.leaf(of: member)),
                            onTap: {
                                if group.isSelectable {
                                    model.select(member, in: group)
                                } else {
                                    model.test(node: topology.leaf(of: member))
                                }
                            },
                            onTest: { model.test(node: topology.leaf(of: member)) },
                            onUnpin: group.pinned == member ? { model.unpin(group) } : nil
                        )
                    }
                }
            }
            if model.core == .singbox, group.picksAutomatically, !group.isSelectable {
                Label("Pinning a node · \(model.core.unavailableLabel)", systemImage: "pin.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

private struct ProxyNodeCell: View {
    let name: String
    let node: ProxyNode?
    let delay: Delay
    let isSelected: Bool
    let isPinned: Bool
    let isDefault: Bool
    let isTesting: Bool
    let onTap: () -> Void
    let onTest: () -> Void
    let onUnpin: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    Text(verbatim: name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(verbatim: caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    DelayLabel(delay: delay, isTesting: isTesting)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTest) {
                Label("Test Latency", systemImage: "bolt")
            }
            if let onUnpin {
                Button(action: onUnpin) {
                    Label("Resume Automatic Selection", systemImage: "pin.slash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var caption: String {
        let type = node?.type ?? ""
        guard isDefault else { return type }
        let label = String(localized: "Default")
        return type.isEmpty ? label : "\(type) · \(label)"
    }
}

// MARK: - Provider card

private struct ProxyProviderCard: View {
    let provider: ProxyProvider
    let isBusy: Bool
    let onUpdate: () -> Void
    let onHealthCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: provider.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(verbatim: "\(provider.vehicleType) · \(provider.nodeCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Button(action: onHealthCheck) {
                        Image(systemName: "bolt.fill")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Test Latency")
                    if provider.vehicleType != "Inline" {
                        Button(action: onUpdate) {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Update")
                    }
                }
            }
            .buttonStyle(.borderless)

            if let subscription = provider.subscription {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: subscription.fraction)
                        .tint(subscription.fraction >= 0.9 ? .red : (subscription.fraction >= 0.7 ? .orange : .accentColor))
                    HStack {
                        Text(verbatim: "\(DashboardFormat.bytes(subscription.used)) / \(DashboardFormat.bytes(subscription.total))")
                        Spacer()
                        if let expire = subscription.expire {
                            Text("Expires \(DashboardFormat.day.string(from: expire))")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            if let updatedAt = provider.updatedAt {
                Text("Updated \(DashboardFormat.relative(updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Settings

struct DashboardSettingsView: View {
    let core: CoreType?

    @AppStorage(DashboardPreferences.testURLKey) private var testURL = ""
    @AppStorage(DashboardPreferences.closeOnSwitchKey) private var closesOnSwitch = true

    var body: some View {
        Form {
            Section {
                TextField(DelayTestOptions.defaultURL, text: $testURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("Latency Test URL")
            }

            Section {
                if let core, !DashboardFeature.connections.isAvailable(on: core) {
                    HStack {
                        Text("Close Connections on Switch")
                        Spacer()
                        Text(core.unavailableLabel)
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Toggle("Close Connections on Switch", isOn: $closesOnSwitch)
                }
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}
