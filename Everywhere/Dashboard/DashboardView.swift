//
//  DashboardView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var store: DashboardStore
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(core: CoreType, configID: UUID?) {
        _store = StateObject(wrappedValue: DashboardStore(core: core, configID: configID))
    }

    var body: some View {
        TabView {
            tab("Overview", systemImage: "speedometer") {
                OverviewView(model: store.overview, core: store.core)
            }
            tab("Proxies", systemImage: "point.3.connected.trianglepath.dotted") {
                ProxiesView(model: store.proxies)
            }
            tab("Connections", systemImage: "arrow.left.arrow.right") {
                ConnectionsView(model: store.connections, core: store.core)
            }
            tab("Rules", systemImage: "arrow.triangle.branch") {
                RulesView(model: store.rules)
            }
            tab("Logs", systemImage: "doc.text") {
                LogsView(model: store.logs)
            }
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.start() } else { store.stop() }
        }
    }

    private func tab<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationView {
            content()
        }
        .navigationViewStyle(.stack)
        .tabItem { Label(title, systemImage: systemImage) }
    }
}
