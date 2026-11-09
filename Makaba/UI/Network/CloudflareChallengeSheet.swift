//
//  CloudflareChallengeSheet.swift
//  Makaba
//
//  Interactive webview sheet allowing users to solve Cloudflare Turnstile anti-bot gates.
//

import SwiftUI
import WebKit

public struct CloudflareChallengeSheet: View {
    public let challengeURL: URL
    public let onSolved: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(challengeURL: URL, onSolved: @escaping () -> Void) {
        self.challengeURL = challengeURL
        self.onSolved = onSolved
    }

    public var body: some View {
        NavigationStack {
            CloudflareBridgeWebView(
                url: challengeURL,
                onClearanceCaptured: {
                    onSolved()
                    dismiss()
                }
            )
            .navigationTitle("Проверка Cloudflare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}

public struct CloudflareBridgeWebView: UIViewRepresentable {
    public let url: URL
    public let onClearanceCaptured: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(onClearanceCaptured: onClearanceCaptured)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        webView.load(request)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let onClearanceCaptured: () -> Void
        private var hasCaptured = false

        init(onClearanceCaptured: @escaping () -> Void) {
            self.onClearanceCaptured = onClearanceCaptured
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkClearanceCookie(webView: webView)
        }

        private func checkClearanceCookie(webView: WKWebView) {
            guard !hasCaptured else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasCaptured else { return }
                for cookie in cookies {
                    if cookie.name == "cf_clearance" {
                        self.hasCaptured = true
                        // Synchronize back to Foundation HTTPCookieStorage
                        HTTPCookieStorage.shared.setCookie(cookie)
                        DispatchQueue.main.async {
                            self.onClearanceCaptured()
                        }
                        break
                    }
                }
            }
        }
    }
}
