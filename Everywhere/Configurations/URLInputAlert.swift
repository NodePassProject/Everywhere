//
//  URLInputAlert.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import UIKit

// Mirrors NameInputAlert: drops down to UIAlertController so we keep
// working on iOS 15 where SwiftUI's `.alert` doesn't yet have a
// TextField action.
enum URLInputAlert {
    static func present(
        title: String,
        message: String? = nil,
        placeholder: String = "https://",
        onSubmit: @escaping (URL) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alert.addTextField { tf in
            tf.placeholder = placeholder
            tf.keyboardType = .URL
            tf.textContentType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))

        let submit = UIAlertAction(title: String(localized: "Download"), style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            guard let url = parsed(raw) else { return }
            onSubmit(url)
        }
        submit.isEnabled = false
        alert.addAction(submit)
        alert.preferredAction = submit

        alert.textFields?.first?.addAction(UIAction { _ in
            let text = alert.textFields?.first?.text ?? ""
            submit.isEnabled = parsed(text) != nil
        }, for: .editingChanged)

        topViewController()?.present(alert, animated: true)
    }

    private static func parsed(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        guard let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
