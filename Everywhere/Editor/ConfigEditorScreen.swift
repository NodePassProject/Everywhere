//
//  ConfigEditorScreen.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI

struct ConfigEditorScreen: View {
    @ObservedObject var configuration: Configuration
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var draft: String = ""

    var body: some View {
        ConfigEditorView(text: draftBinding, language: configuration.coreType.configLanguage)
            .id(configuration.id)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(configuration.name.isEmpty ? "Configuration" : configuration.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            draft = configuration.coreType.defaultConfig
                            store.update(configuration, content: draft)
                        } label: {
                            Label("Reset to default", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .onAppear { draft = configuration.content }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                store.update(configuration, content: newValue)
            }
        )
    }
}
