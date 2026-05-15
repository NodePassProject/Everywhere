//
//  ConfigEditorView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Runestone
import SwiftUI
import TreeSitterJSONRunestone
import TreeSitterYAMLRunestone

struct ConfigEditorView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let language: String

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .always
        textView.showLineNumbers = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        textView.lineSelectionDisplayType = .line
        textView.lineHeightMultiplier = 1.3
        textView.kern = 0.3
        textView.pageGuideColumn = 80
        
        textView.setLanguageMode(Self.languageMode(for: language))
        
        return textView
    }

    func updateUIView(_ textView: TextView, context: Context) {
        switch colorScheme {
        case .light:
            textView.backgroundColor = .white
        case .dark:
            textView.backgroundColor = .black
        }
        textView.text = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: TextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: TextView) {
            text.wrappedValue = textView.text
        }
    }

    private static func languageMode(for language: String) -> any LanguageMode {
        switch language {
        case "json": return TreeSitterLanguageMode(language: .json)
        case "yaml": return TreeSitterLanguageMode(language: .yaml)
        default:     return PlainTextLanguageMode()
        }
    }
}
