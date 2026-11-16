//
//  LogsView.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import SwiftUI
import UIKit

struct LogsView: View {
    @ObservedObject var model: LogsModel

    @State private var searchText = ""

    private var visible: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let entries = visible
        List(entries) { entry in
            LogRow(entry: entry)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = entry.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
        .listStyle(.plain)
        .overlay {
            if entries.isEmpty {
                DashboardPlaceholder(
                    systemImage: "doc.text",
                    title: searchText.isEmpty ? "Waiting for logs" : "No matching logs"
                )
            }
        }
        .navigationTitle("Logs")
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
                    Picker("Log Level", selection: Binding(get: { model.level }, set: { model.setLevel($0) })) {
                        ForEach(LogLevel.allCases) { level in
                            Text(verbatim: level.title).tag(level)
                        }
                    }
                    Divider()
                    Button {
                        UIPasteboard.general.string = entries.reversed()
                            .map { "\(DashboardFormat.clock.string(from: $0.time)) [\($0.level.rawValue)] \($0.text)" }
                            .joined(separator: "\n")
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .disabled(entries.isEmpty)
                    Button(role: .destructive) {
                        model.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(model.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                }
            }
        }
        .onAppear { model.activate() }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: entry.level.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DashboardColor.level(entry.level))
                Text(verbatim: DashboardFormat.clock.string(from: entry.time))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: entry.text)
                .font(.caption.monospaced())
                .lineLimit(6)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}
