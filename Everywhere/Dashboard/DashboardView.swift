//
//  DashboardView.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Combine
import SwiftUI
import WebKit

struct DashboardView: View {
    @StateObject private var bg = SafeAreaBackgroundStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(uiColor: bg.bottom)
                    .ignoresSafeArea()
                Color(uiColor: bg.top)
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
                ZashboardWebView(store: bg)
            }
        }
    }
}

private struct ZashboardWebView: UIViewRepresentable {
    let store: SafeAreaBackgroundStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(
            context.coordinator.schemeHandler,
            forURLScheme: ZashboardSchemeHandler.scheme
        )
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: SafeAreaColorBridge.messageName)
        ucc.addUserScript(WKUserScript(
            source: SafeAreaColorBridge.injectedSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        cfg.userContentController = ucc
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        view.load(URLRequest(url: ZashboardSchemeHandler.indexURL))
        return view
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let schemeHandler = ZashboardSchemeHandler()
        let store: SafeAreaBackgroundStore

        init(store: SafeAreaBackgroundStore) {
            self.store = store
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == SafeAreaColorBridge.messageName,
                  let dict = message.body as? [String: String] else { return }
            let top = SafeAreaColorBridge.parse(dict["top"])
            let bottom = SafeAreaColorBridge.parse(dict["bottom"])
            DispatchQueue.main.async { [store] in
                store.update(top: top, bottom: bottom)
            }
        }
    }
}

// MARK: - SafeAreaBackgroundStore

fileprivate final class SafeAreaBackgroundStore: ObservableObject {
    @Published var top: UIColor
    @Published var bottom: UIColor

    private static let topKey = "ZashboardSafeAreaTop"
    private static let bottomKey = "ZashboardSafeAreaBottom"

    init() {
        let d = UserDefaults.standard
        self.top = Self.unarchive(d.data(forKey: Self.topKey)) ?? Self.defaultTop
        self.bottom = Self.unarchive(d.data(forKey: Self.bottomKey)) ?? Self.defaultBottom
    }

    func update(top: UIColor?, bottom: UIColor?) {
        let d = UserDefaults.standard
        if let top, top != self.top {
            self.top = top
            d.set(Self.archive(top), forKey: Self.topKey)
        }
        if let bottom, bottom != self.bottom {
            self.bottom = bottom
            d.set(Self.archive(bottom), forKey: Self.bottomKey)
        }
    }

    // Sensible starting values that follow system appearance, used on
    // first launch before the WebView posts real colors.
    private static var defaultTop: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 33/255, green: 38/255, blue: 47/255, alpha: 1)
                : .white
        }
    }
    private static var defaultBottom: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 29/255, green: 34/255, blue: 42/255, alpha: 1)
                : UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1)
        }
    }

    private static func archive(_ c: UIColor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: c, requiringSecureCoding: true)
    }
    private static func unarchive(_ data: Data?) -> UIColor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
    }
}

// MARK: - SafeAreaColorBridge

private enum SafeAreaColorBridge {
    static let messageName = "safeAreaColors"

    // The script reports two CSS colors back to native:
    //   top    — `.need-blur` (the sticky CtrlsBar, `bg-base-100`)
    //   bottom — `.home-page`  (the content wrapper, `bg-base-200`)
    // Falls back to `#app-content` (also `bg-base-100`) if either
    // element is absent — e.g. on SetupPage before the main router
    // mounts.
    static let injectedSource = #"""
    (function () {
      function readBg(selector) {
        var el = document.querySelector(selector);
        if (!el) return null;
        var c = getComputedStyle(el).backgroundColor;
        if (!c || c === 'rgba(0, 0, 0, 0)' || c === 'transparent') return null;
        return c;
      }
      function post() {
        var fallback = readBg('#app-content') || readBg('html') || readBg('body');
        var top = readBg('.need-blur') || fallback;
        var bottom = readBg('.home-page') || fallback;
        if (!top && !bottom) return;
        var bridge = window.webkit
          && window.webkit.messageHandlers
          && window.webkit.messageHandlers.safeAreaColors;
        if (!bridge) return;
        bridge.postMessage({ top: top || '', bottom: bottom || '' });
      }
      // Initial probe after layout settles.
      requestAnimationFrame(function () {
        requestAnimationFrame(post);
      });
      // Re-probe on theme toggle, route change, or DOM swap.
      var mo = new MutationObserver(post);
      mo.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ['class', 'data-theme', 'style'],
      });
      mo.observe(document.body, {
        attributes: true,
        attributeFilter: ['class', 'data-theme', 'style'],
        childList: true,
        subtree: false,
      });
      var mql = window.matchMedia('(prefers-color-scheme: dark)');
      if (mql.addEventListener) mql.addEventListener('change', post);
      // Light-weight catch-all in case a deeply nested mutation slips
      // past the observers (e.g. router transition swapping `.home-page`).
      setInterval(post, 1500);
    })();
    """#

    static func parse(_ css: String?) -> UIColor? {
        guard var s = css?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        guard s.hasPrefix("rgb"),
              let open = s.firstIndex(of: "("),
              let close = s.lastIndex(of: ")") else { return nil }
        s = String(s[s.index(after: open)..<close])
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]) else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1.0) : 1.0
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a)
        )
    }
}

// MARK: - URL scheme handler

fileprivate final class ZashboardSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "zashboard"
    static let indexURL = URL(string: "zashboard://app/index.html")!

    private let bundleRoot: URL?

    override init() {
        self.bundleRoot = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "zashboard"
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
