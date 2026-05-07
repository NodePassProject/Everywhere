//
//  NameInputAlert.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import UIKit

// SwiftUI's `.alert` did not get a `TextField` action until iOS 16.
// Since the app targets iOS 15, the simplest cross-version path is to
// drop down to UIAlertController and present it on top of whatever
// view controller SwiftUI is currently showing.
enum NameInputAlert {
    static func present(
        title: String,
        message: String? = nil,
        placeholder: String = "Name",
        initialValue: String = "",
        onSubmit: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alert.addTextField { tf in
            tf.placeholder = placeholder
            tf.text = initialValue
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        let save = UIAlertAction(title: "Save", style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
        }
        save.isEnabled = !initialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        alert.addAction(save)
        alert.preferredAction = save

        // Keep Save disabled while the field is empty.
        alert.textFields?.first?.addAction(UIAction { _ in
            let text = alert.textFields?.first?.text ?? ""
            save.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, for: .editingChanged)

        topViewController()?.present(alert, animated: true)
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
