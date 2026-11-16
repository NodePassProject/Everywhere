//
//  SettingsFields.swift
//  Everywhere
//
//  Created by NodePassProject on 11/16/26.
//

import SwiftUI

// MARK: - Text field

struct SettingTextField: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var value: String
    var keyboardType: UIKeyboardType = .URL
    var validate: (String) -> Bool = { _ in true }

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            TextField(placeholder, text: $draft)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(isValid ? Color.primary : Color.red)
                .focused($isFocused)
                .onSubmit(commit)
        }
        .onAppear { draft = value }
        .onChange(of: value) { draft = $0 }
        .onChange(of: isFocused) { focused in
            if !focused { commit() }
        }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        validate(trimmed)
    }

    private func commit() {
        if isValid {
            value = trimmed
        }
        draft = value
    }
}

struct SettingNumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SettingTextField(
            title: title,
            placeholder: String(value),
            value: Binding(
                get: { String(value) },
                set: { if let number = Int($0) { value = number } }
            ),
            keyboardType: .numbersAndPunctuation,
            validate: { Int($0).map(range.contains) ?? false }
        )
    }
}

// MARK: - List

struct EditableListSection: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var items: [String]
    var minimumCount = 0
    var validate: (String) -> Bool = { !$0.isEmpty }

    @State private var draft = ""

    var body: some View {
        Section(title) {
            ForEach(items, id: \.self) { item in
                Text(verbatim: item)
                    .font(.body.monospaced())
                    .deleteDisabled(items.count <= minimumCount)
            }
            .onDelete { items.remove(atOffsets: $0) }
            .onMove { items.move(fromOffsets: $0, toOffset: $1) }

            HStack {
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(canAdd ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .accessibilityLabel("Add")
                TextField(placeholder, text: $draft)
                    .font(.body.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onSubmit(add)
            }
        }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        validate(trimmed) && !items.contains(trimmed)
    }

    private func add() {
        guard canAdd else { return }
        items.append(trimmed)
        draft = ""
    }
}
