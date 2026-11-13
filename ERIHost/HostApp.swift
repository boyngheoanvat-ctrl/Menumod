import UIKit
import WebKit

// ERI native host is an independent app, NOT an injected module.
// The bridge controls only UI features owned by this app.
@main
final class ERIAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ERIHostViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class ERIHostViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let handlerName = "eri"
    private let initialStates = ["overlay": false, "darkCanvas": false, "haptics": true]
    private var states: [String: Bool] = [:]
    private var webView: WKWebView!
    private let nativeOverlay = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        for (name, initial) in initialStates {
            states[name] = UserDefaults.standard.object(forKey: "eri.feature." + name) as? Bool ?? initial
        }

        nativeOverlay.text = "● ERI NATIVE OVERLAY"
        nativeOverlay.font = .boldSystemFont(ofSize: 12)
        nativeOverlay.textAlignment = .center
        nativeOverlay.textColor = .white
        nativeOverlay.backgroundColor = UIColor(red: 0.10, green: 0.45, blue: 0.38, alpha: 1.0)
        nativeOverlay.layer.cornerRadius = 12
        nativeOverlay.clipsToBounds = true
        nativeOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nativeOverlay)

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Keep web preferences in WKWebKit's persistent store, not an ephemeral one.
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.userContentController.add(self, name: handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        self.webView = webView
        // Keep the app-owned overlay in front of the WebView so the toggle is observable.
        view.bringSubviewToFront(nativeOverlay)

        NSLayoutConstraint.activate([
            nativeOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nativeOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            nativeOverlay.widthAnchor.constraint(equalToConstant: 210),
            nativeOverlay.heightAnchor.constraint(equalToConstant: 32),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyOwnedFeatures()

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h2>ERI Host: missing Web/index.html</h2>", baseURL: nil)
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    // A WebKit process can be terminated by iOS for memory pressure.
    // Reload the bundled page; the next getState call rehydrates native state.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func applyOwnedFeatures() {
        let dark = states["darkCanvas"] ?? false
        view.backgroundColor = dark ? UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1) :
            UIColor(red: 0.10, green: 0.17, blue: 0.26, alpha: 1)
        nativeOverlay.isHidden = !(states["overlay"] ?? false)
    }

    private func snapshot() -> [String: Any] {
        return [
            "host": "ERIHost",
            "apiVersion": 1,
            "thirdPartyGameConnected": false,
            "features": states
        ]
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == handlerName,
              let request = message.body as? [String: Any],
              let requestID = request["id"] as? String,
              requestID.count <= 80,
              let type = request["type"] as? String else {
            return
        }

        var result: [String: Any] = ["id": requestID, "ok": true]

        switch type {
        case "ping", "getState":
            result["payload"] = snapshot()

        case "setFeature":
            guard let feature = request["feature"] as? String,
                  initialStates[feature] != nil,
                  let value = request["enabled"] as? Bool else {
                result["ok"] = false
                result["error"] = "invalid_feature_or_value"
                break
            }

            states[feature] = value
            UserDefaults.standard.set(value, forKey: "eri.feature." + feature)
            applyOwnedFeatures()

            if feature == "haptics" && value {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            result["payload"] = snapshot()

        case "reset":
            states = initialStates
            for (name, _) in initialStates {
                UserDefaults.standard.removeObject(forKey: "eri.feature." + name)
            }
            applyOwnedFeatures()
            result["payload"] = snapshot()

        default:
            result["ok"] = false
            result["error"] = "unknown_action"
        }

        send(result)
    }

    private func send(_ response: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.__eriReceive(\(json));", completionHandler: nil)
        }
    }
}
