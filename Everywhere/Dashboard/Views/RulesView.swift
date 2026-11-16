//
//  RulesView.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI

struct RulesView: View {
    @ObservedObject var model: RulesModel

    private enum Page: Hashable {
        case rules, providers
    }

    @State private var page: Page = .rules
    @State private var searchText = ""

    private var core: CoreType { model.core }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $page) {
                    Text("Rules").tag(Page.rules)
                    Text("Providers").tag(Page.providers)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            switch page {
            case .rules: rules
            case .providers: providers
            }
        }
        .listStyle(.plain)
        .navigationTitle("Rules")
        .searchable(text: $searchText)
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .alert("Something went wrong", isPresented: actionErrorBinding, presenting: model.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Rules

    private var visibleRules: [RoutingRule] {
        guard !query.isEmpty else { return model.rules }
        return model.rules.filter {
            $0.payload.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
                || $0.target.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var rules: some View {
        if !model.isLoaded {
            placeholderRow {
                if let error = model.loadError {
                    DashboardPlaceholder(systemImage: "exclamationmark.triangle", title: "Can't load rules", message: error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        } else if visibleRules.isEmpty {
            placeholderRow {
                DashboardPlaceholder(
                    systemImage: "arrow.triangle.branch",
                    title: query.isEmpty ? "No rules" : "No matching rules"
                )
            }
        } else {
            Section {
                ForEach(visibleRules) { rule in
                    RuleRow(rule: rule)
                }
            } header: {
                Text("\(visibleRules.count) Rules")
            }
        }
    }

    // MARK: Providers

    private var visibleProviders: [RuleProvider] {
        guard !query.isEmpty else { return model.providers }
        return model.providers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private var providers: some View {
        if !DashboardFeature.ruleProviders.isAvailable(on: core) {
            placeholderRow {
                FeatureUnavailableView(title: "Rule Providers", systemImage: "shippingbox", core: core)
                    .frame(minHeight: 320)
            }
        } else if visibleProviders.isEmpty {
            placeholderRow {
                DashboardPlaceholder(
                    systemImage: "shippingbox",
                    title: query.isEmpty ? "No rule providers" : "No matching providers"
                )
            }
        } else {
            ForEach(visibleProviders) { provider in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: provider.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(verbatim: [provider.behavior, provider.vehicleType, provider.format]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text("\(provider.ruleCount) Rules")
                            if let updatedAt = provider.updatedAt {
                                Text(verbatim: "·")
                                Text("Updated \(DashboardFormat.relative(updatedAt))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busyProviders.contains(provider.name) {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else if provider.vehicleType != "Inline" {
                        Button {
                            model.updateProvider(provider.name)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Update")
                    }
                }
            }
        }
    }

    private func placeholderRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

private struct RuleRow: View {
    let rule: RoutingRule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: String(rule.id + 1))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                if !rule.type.isEmpty {
                    Text(verbatim: rule.type)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if !rule.payload.isEmpty {
                    Text(verbatim: rule.payload)
                        .font(.subheadline)
                        .lineLimit(4)
                }
                if !rule.target.isEmpty {
                    RouteLabel(text: rule.target)
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
