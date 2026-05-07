//
//  ControllerView.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import SwiftUI
import WebKit

// Hosts the bundled yacd dashboard via a custom yacd:// scheme
struct ControllerView: View {
    var body: some View {
        ZStack {
            Color("yacdColor")
                .ignoresSafeArea()
            YACDWebView()
        }
    }
}

private struct YACDWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(
            context.coordinator.handler,
            forURLScheme: YACDSchemeHandler.scheme
        )
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        view.load(URLRequest(url: YACDSchemeHandler.indexURL))
        return view
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    final class Coordinator {
        let handler = YACDSchemeHandler()
    }
}

private final class YACDSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "yacd"
    static let indexURL = URL(string: "yacd://app/index.html")!

    private let bundleRoot: URL?

    override init() {
        self.bundleRoot = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "yacd-gh-pages"
        )?.deletingLastPathComponent()
    }

    func webView(_: WKWebView, start task: WKURLSchemeTask) {
        guard let bundleRoot else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        var rel = url.path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "index.html" }
        let fileURL = bundleRoot.appendingPathComponent(rel)

        guard let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(resp)
            task.didFinish()
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: fileURL.pathExtension),
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-cache",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico": return "image/x-icon"
        case "svg": return "image/svg+xml"
        case "woff", "woff2": return "font/\(ext.lowercased())"
        case "ttf": return "font/ttf"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
