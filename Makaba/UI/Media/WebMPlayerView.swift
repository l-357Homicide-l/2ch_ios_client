//
//  WebMPlayerView.swift
//  Makaba
//
//  Modular video player for WebM (VP8/VP9 + Opus/Vorbis) and MP4 video attachments.
//  Implements a dual-engine architecture:
//  1. Primary Engine: AVPlayer / KSPlayer bridge for hardware-accelerated playback.
//  2. Resilient Zero-Dependency Fallback: WebKit HTML5 <video> engine (WKWebView with
//     inline media playback, hardware VP9 decode, Opus audio, and custom SwiftUI controls).
//

import SwiftUI
import WebKit
import AVFoundation
import Combine

#if canImport(KSPlayer)
import KSPlayer
#endif

// MARK: - Engine Protocols & Types

/// Available video player engines.
public enum PlayerEngineType: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case avPlayer = "AVPlayer"
    case webKit = "WebKit HTML5"
    #if canImport(KSPlayer)
    case ksPlayer = "KSPlayer"
    #endif

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Автовыбор"
        case .avPlayer: return "AVPlayer (Нативный)"
        case .webKit: return "WebKit (HTML5 WebM)"
        #if canImport(KSPlayer)
        case .ksPlayer: return "KSPlayer (FFmpeg/VP9)"
        #endif
        }
    }
}

/// Status of the player playback engine.
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case finished
    case error(String)
}

/// Abstract contract for video player engines.
public protocol WebMPlayerEngine: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var isMuted: Bool { get set }
    var isLooping: Bool { get set }
    var isLoading: Bool { get }

    func load(url: URL)
    func play()
    func pause()
    func seek(to time: Double)
    func setVolume(_ volume: Float)
    func cleanup()
}

// MARK: - WebM Player Model (Observable Controller)

@MainActor
public final class WebMPlayerModel: ObservableObject {
    public let videoURL: URL
    @Published public var autoPlay: Bool

    @Published public var activeEngine: PlayerEngineType
    @Published public var playbackState: PlaybackState = .idle
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0.0
    @Published public var duration: Double = 0.0
    @Published public var isMuted: Bool = false
    @Published public var isLooping: Bool = true
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String? = nil

    // Scrubbing state
    @Published public var isScrubbing: Bool = false
    @Published public var scrubTime: Double = 0.0

    // Engine delegation closures
    var onPlayCommand: (() -> Void)?
    var onPauseCommand: (() -> Void)?
    var onSeekCommand: ((Double) -> Void)?
    var onMuteCommand: ((Bool) -> Void)?
    var onLoopCommand: ((Bool) -> Void)?
    var onVolumeCommand: ((Float) -> Void)?
    var onReloadCommand: (() -> Void)?
    var onPiPCommand: (() -> Void)?

    private var wasPlayingBeforeScrub: Bool = false
    private var isAudioActive: Bool = false

    private func updateAudioSessionState() {
        let shouldBeActive = isPlaying && !isMuted
        if shouldBeActive && !isAudioActive {
            AudioSessionManager.shared.activatePlayback()
            isAudioActive = true
        } else if !shouldBeActive && isAudioActive {
            AudioSessionManager.shared.deactivatePlayback()
            isAudioActive = false
        }
    }

    deinit {
        if isAudioActive {
            AudioSessionManager.shared.deactivatePlayback()
            isAudioActive = false
        }
    }

    public static func configureAudioSession() {
        AudioSessionManager.shared.activatePlayback()
    }

    public init(
        url: URL,
        autoPlay: Bool = true,
        isLooping: Bool = true,
        initialEngine: PlayerEngineType = .auto
    ) {
        self.videoURL = url
        self.autoPlay = autoPlay
        self.isLooping = isLooping

        // Auto-detect optimal engine based on file format & capabilities
        if initialEngine == .auto {
            let pathLower = url.path.lowercased()
            if pathLower.hasSuffix(".mp4") || pathLower.hasSuffix(".m4v") || pathLower.hasSuffix(".mov") {
                self.activeEngine = .avPlayer
            } else {
                #if canImport(KSPlayer)
                self.activeEngine = .ksPlayer
                #else
                self.activeEngine = .webKit
                #endif
            }
        } else {
            self.activeEngine = initialEngine
        }
    }

    // MARK: - Playback Commands

    public func play() {
        guard !isScrubbing else { return }
        isPlaying = true
        playbackState = .playing
        updateAudioSessionState()
        onPlayCommand?()
    }

    public func pause() {
        isPlaying = false
        playbackState = .paused
        updateAudioSessionState()
        onPauseCommand?()
    }

    public func togglePlayPause() {
        guard !isScrubbing else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to time: Double) {
        let clampedTime = max(0.0, min(time, max(duration, 0.0)))
        currentTime = clampedTime
        onSeekCommand?(clampedTime)
    }

    public func startScrubbing() {
        isScrubbing = true
        scrubTime = currentTime
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            pause()
        }
    }

    public func endScrubbing() {
        isScrubbing = false
        seek(to: scrubTime)
        if wasPlayingBeforeScrub {
            play()
        }
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        updateAudioSessionState()
        onMuteCommand?(muted)
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    public func setLooping(_ looping: Bool) {
        isLooping = looping
        onLoopCommand?(looping)
    }

    public func toggleLoop() {
        setLooping(!isLooping)
    }

    public func togglePictureInPicture() {
        onPiPCommand?()
    }

    public func switchEngine(to engine: PlayerEngineType) {
        guard engine != activeEngine else { return }
        pause()
        if engine == .auto {
            let pathLower = videoURL.path.lowercased()
            if pathLower.hasSuffix(".mp4") || pathLower.hasSuffix(".m4v") || pathLower.hasSuffix(".mov") {
                self.activeEngine = .avPlayer
            } else {
                #if canImport(KSPlayer)
                self.activeEngine = .ksPlayer
                #else
                self.activeEngine = .webKit
                #endif
            }
        } else {
            self.activeEngine = engine
        }
        isLoading = true
        errorMessage = nil
    }

    public func cleanup() {
        pause()
        onPlayCommand = nil
        onPauseCommand = nil
        onSeekCommand = nil
        onMuteCommand = nil
        onLoopCommand = nil
        onVolumeCommand = nil
        onReloadCommand = nil
        onPiPCommand = nil
    }

    // MARK: - Engine Callbacks

    func handleEngineMetadataLoaded(duration: Double) {
        self.duration = duration
        self.isLoading = false
        if isPlaying && !isScrubbing {
            play()
        }
    }

    func handleEngineTimeUpdate(currentTime: Double) {
        if !isScrubbing {
            self.currentTime = currentTime
        }
    }

    func handleEngineStateChange(isPlaying: Bool, isLoading: Bool) {
        guard !isScrubbing else { return }
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        if isPlaying {
            self.playbackState = .playing
        } else if !isLoading && self.playbackState != .finished {
            self.playbackState = .paused
        }
    }

    func handleEngineEnded() {
        if isLooping {
            seek(to: 0.0)
            play()
        } else {
            self.isPlaying = false
            self.playbackState = .finished
        }
    }

    func handleEngineError(_ message: String) {
        self.errorMessage = message
        self.isLoading = false
        self.playbackState = .error(message)
    }
}

// MARK: - Resilient Zero-Dependency Fallback: WebKit HTML5 Engine

public struct WebKitPlayerBridgeView: UIViewRepresentable {
    @ObservedObject var model: WebMPlayerModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Register custom JavaScript bridge
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "playerBridge")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.isUserInteractionEnabled = false

        context.coordinator.setup(webView: webView)
        context.coordinator.loadVideo()

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        // State updates are handled reactively via model closures
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "playerBridge")
        uiView.navigationDelegate = nil
        // Direct load of empty document synchronously stops WebProcess media threads and releases video decoders immediately
        uiView.loadHTMLString("<!DOCTYPE html><html><head></head><body></body></html>", baseURL: nil)
    }

    // MARK: - Coordinator & Script Message Handler

    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var model: WebMPlayerModel?
        private weak var webView: WKWebView?
        private var isPageLoaded: Bool = false

        init(model: WebMPlayerModel) {
            self.model = model
            super.init()
        }

        func setup(webView: WKWebView) {
            self.webView = webView

            // Bind model commands to JavaScript evaluation
            model?.onPlayCommand = { [weak self] in
                self?.evaluateJS("window.playVideo && window.playVideo();")
            }

            model?.onPauseCommand = { [weak self] in
                self?.evaluateJS("window.pauseVideo && window.pauseVideo();")
            }

            model?.onSeekCommand = { [weak self] seconds in
                self?.evaluateJS("window.seekTo && window.seekTo(\(seconds));")
            }

            model?.onMuteCommand = { [weak self] muted in
                self?.evaluateJS("window.setMuted && window.setMuted(\(muted ? "true" : "false"));")
            }

            model?.onLoopCommand = { [weak self] loop in
                self?.evaluateJS("window.setLooping && window.setLooping(\(loop ? "true" : "false"));")
            }

            model?.onVolumeCommand = { [weak self] volume in
                self?.evaluateJS("window.setVolume && window.setVolume(\(volume));")
            }

            model?.onReloadCommand = { [weak self] in
                self?.loadVideo()
            }

            model?.onPiPCommand = { [weak self] in
                let js = """
                (function() {
                    const v = document.querySelector('video');
                    if (!v) return;
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                    } else if (v.requestPictureInPicture) {
                        v.requestPictureInPicture();
                    }
                })();
                """
                self?.evaluateJS(js)
            }
        }

        func loadVideo() {
            guard let model = model, let webView = webView else { return }

            let videoURLString = model.videoURL.absoluteString
            let htmlContent = generateHTML(
                videoURL: videoURLString,
                autoPlay: model.autoPlay,
                isLooping: model.isLooping,
                isMuted: model.isMuted
            )

            isPageLoaded = false
            let baseURL = DomainConfigurationService.shared.baseURL
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = HTTPCookieStorage.shared.cookies ?? []

            guard !cookies.isEmpty else {
                webView.loadHTMLString(htmlContent, baseURL: baseURL)
                return
            }

            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main) { [weak webView] in
                webView?.loadHTMLString(htmlContent, baseURL: baseURL)
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            guard let model = model else { return }
            if model.isPlaying {
                evaluateJS("window.playVideo && window.playVideo();")
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model?.handleEngineError("Ошибка загрузки веб-плеера: \(error.localizedDescription)")
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "playerBridge",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self, let model = self.model else { return }

                switch event {
                case "loadedmetadata", "durationchange":
                    if let dur = body["duration"] as? Double, dur.isFinite && dur > 0 {
                        model.handleEngineMetadataLoaded(duration: dur)
                    }
                case "timeupdate":
                    if let curr = body["currentTime"] as? Double, curr.isFinite {
                        model.handleEngineTimeUpdate(currentTime: curr)
                    }
                    if model.duration <= 0, let dur = body["duration"] as? Double, dur.isFinite && dur > 0 {
                        model.handleEngineMetadataLoaded(duration: dur)
                    }
                case "play", "playing":
                    model.handleEngineStateChange(isPlaying: true, isLoading: false)
                case "pause":
                    model.handleEngineStateChange(isPlaying: false, isLoading: false)
                case "waiting":
                    model.handleEngineStateChange(isPlaying: model.isPlaying, isLoading: true)
                case "canplay", "canplaythrough":
                    model.isLoading = false
                case "ended":
                    model.handleEngineEnded()
                case "error":
                    let errorMsg = body["error"] as? String ?? "Неизвестная ошибка декодирования видео"
                    model.handleEngineError(errorMsg)
                default:
                    break
                }
            }
        }

        private func evaluateJS(_ script: String) {
            guard isPageLoaded, let webView = webView else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func cleanup() {
            evaluateJS("window.pauseVideo && window.pauseVideo();")
            webView = nil
            model = nil
        }

        // Embedded responsive HTML5 video template
        private func generateHTML(videoURL: String, autoPlay: Bool, isLooping: Bool, isMuted: Bool) -> String {
            let escapedURL = videoURL
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")

            return """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
              <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                  width: 100%;
                  height: 100%;
                  background-color: #000000;
                  overflow: hidden;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  -webkit-user-select: none;
                  user-select: none;
                }
                video {
                  width: 100%;
                  height: 100%;
                  max-width: 100%;
                  max-height: 100%;
                  object-fit: contain;
                  background-color: #000000;
                }
              </style>
            </head>
            <body>
              <video id="player"
                     playsinline
                     webkit-playsinline
                     x-webkit-airplay="allow"
                     preload="auto"
                     \(isLooping ? "loop" : "")
                     \(isMuted ? "muted" : "")
                     src="\(escapedURL)">
              </video>
              <script>
                const video = document.getElementById('player');

                function notify(eventName, extra = {}) {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    const payload = {
                      event: eventName,
                      currentTime: video.currentTime || 0,
                      duration: isFinite(video.duration) ? video.duration : 0,
                      paused: video.paused,
                      muted: video.muted,
                      ended: video.ended,
                      readyState: video.readyState,
                      ...extra
                    };
                    window.webkit.messageHandlers.playerBridge.postMessage(payload);
                  }
                }

                video.addEventListener('loadedmetadata', () => notify('loadedmetadata'));
                video.addEventListener('durationchange', () => notify('durationchange'));
                video.addEventListener('timeupdate', () => notify('timeupdate'));
                video.addEventListener('play', () => notify('play'));
                video.addEventListener('playing', () => notify('playing'));
                video.addEventListener('pause', () => notify('pause'));
                video.addEventListener('waiting', () => notify('waiting'));
                video.addEventListener('canplay', () => notify('canplay'));
                video.addEventListener('canplaythrough', () => notify('canplaythrough'));
                video.addEventListener('ended', () => notify('ended'));
                video.addEventListener('error', () => {
                  let errMessage = 'Ошибка декодирования';
                  if (video.error) {
                    errMessage = 'WebKit Video Error (code ' + video.error.code + ')';
                  }
                  notify('error', { error: errMessage });
                });

                // JavaScript controls called from native Swift
                window.playVideo = function() {
                  video.play().catch(function(err) {
                    console.log('Autoplay deferred or error: ', err);
                  });
                };

                window.pauseVideo = function() {
                  video.pause();
                };

                window.seekTo = function(seconds) {
                  if (isFinite(seconds)) {
                    video.currentTime = Math.max(0, Math.min(seconds, video.duration || seconds));
                  }
                };

                window.setMuted = function(muted) {
                  video.muted = !!muted;
                };

                window.setLooping = function(loop) {
                  video.loop = !!loop;
                };

                window.setVolume = function(vol) {
                  if (isFinite(vol)) {
                    video.volume = Math.max(0, Math.min(1, vol));
                  }
                };
              </script>
            </body>
            </html>
            """
        }
    }
}

// MARK: - Native AVPlayer Engine (Hardware Accelerated MP4 / Native)

public struct AVPlayerBridgeView: UIViewRepresentable {
    @ObservedObject var model: WebMPlayerModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    public func makeUIView(context: Context) -> PlayerUIView {
        let playerView = PlayerUIView()
        context.coordinator.setup(playerView: playerView)
        return playerView
    }

    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Handled via coordinator & model bindings
    }

    public static func dismantleUIView(_ uiView: PlayerUIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: - Custom Player Layer UIView

    public final class PlayerUIView: UIView {
        override public class var layerClass: AnyClass {
            return AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
        }
    }

    // MARK: - Coordinator for AVPlayer Lifecycle

    @MainActor
    public final class Coordinator: NSObject {
        private weak var model: WebMPlayerModel?
        private var player: AVPlayer?
        private var timeObserverToken: Any?
        private var itemEndObserver: NSObjectProtocol?
        private var statusObserver: NSKeyValueObservation?
        private var timeControlObserver: NSKeyValueObservation?

        init(model: WebMPlayerModel) {
            self.model = model
            super.init()
        }

        func setup(playerView: PlayerUIView) {
            guard let model = model else { return }

            let asset = AVURLAsset(url: model.videoURL)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = model.isMuted
            playerView.playerLayer.player = player
            self.player = player

            // Bind model commands to AVPlayer methods
            model.onPlayCommand = { [weak player] in
                player?.play()
            }

            model.onPauseCommand = { [weak player] in
                player?.pause()
            }

            model.onSeekCommand = { [weak player] seconds in
                let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
                player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }

            model.onMuteCommand = { [weak player] muted in
                player?.isMuted = muted
            }

            model.onReloadCommand = { [weak self, weak playerView] in
                guard let self = self, let pv = playerView else { return }
                self.cleanup()
                self.setup(playerView: pv)
            }

            // Periodic time observer (~4 Hz for smooth seek bar)
            let interval = CMTime(value: 1, timescale: 4)
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor in
                    self?.model?.handleEngineTimeUpdate(currentTime: time.seconds)
                }
            }

            // Observe item status & duration
            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self = self, let model = self.model else { return }
                    switch item.status {
                    case .readyToPlay:
                        let duration = item.duration.seconds
                        if duration.isFinite && duration > 0 {
                            model.handleEngineMetadataLoaded(duration: duration)
                        } else {
                            model.isLoading = false
                        }
                        if model.isPlaying {
                            self.player?.play()
                        }
                    case .failed:
                        model.handleEngineError(item.error?.localizedDescription ?? "Ошибка загрузки AVPlayer")
                    case .unknown:
                        model.isLoading = true
                    @unknown default:
                        break
                    }
                }
            }

            // Observe play/pause time control status
            timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor in
                    guard let model = self?.model else { return }
                    switch player.timeControlStatus {
                    case .playing:
                        model.handleEngineStateChange(isPlaying: true, isLoading: false)
                    case .paused:
                        model.handleEngineStateChange(isPlaying: false, isLoading: false)
                    case .waitingToPlayAtSpecifiedRate:
                        model.handleEngineStateChange(isPlaying: model.isPlaying, isLoading: true)
                    @unknown default:
                        break
                    }
                }
            }

            // Observe End-Of-Track for looping
            itemEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let model = self.model else { return }
                    if model.isLooping {
                        self.player?.seek(to: .zero) { _ in
                            self.player?.play()
                        }
                    } else {
                        model.handleEngineEnded()
                    }
                }
            }
        }

        func cleanup() {
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
                timeObserverToken = nil
            }
            if let endObs = itemEndObserver {
                NotificationCenter.default.removeObserver(endObs)
                itemEndObserver = nil
            }
            statusObserver?.invalidate()
            statusObserver = nil
            timeControlObserver?.invalidate()
            timeControlObserver = nil

            player?.pause()
            player = nil
            model = nil
        }
    }
}

// MARK: - KSPlayer Bridge (When SPM Package is Linked)

#if canImport(KSPlayer)
public struct KSPlayerBridgeView: UIViewRepresentable {
    @ObservedObject var model: WebMPlayerModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        context.coordinator.setup(container: container)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    public final class Coordinator: NSObject {
        private weak var model: WebMPlayerModel?
        private var ksPlayer: KSVideoPlayerView?

        init(model: WebMPlayerModel) {
            self.model = model
            super.init()
        }

        func setup(container: UIView) {
            guard let model = model else { return }
            let player = KSVideoPlayerView()
            player.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(player)
            NSLayoutConstraint.activate([
                player.topAnchor.constraint(equalTo: container.topAnchor),
                player.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                player.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                player.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            self.ksPlayer = player

            // Set media URL and options
            player.set(url: model.videoURL)
            if model.isPlaying {
                player.play()
            }

            model.onPlayCommand = { [weak player] in player?.play() }
            model.onPauseCommand = { [weak player] in player?.pause() }
            model.onSeekCommand = { [weak player] sec in player?.seek(time: sec, completion: nil) }
            model.onMuteCommand = { [weak player] muted in player?.player?.isMuted = muted }
        }

        func cleanup() {
            ksPlayer?.pause()
            ksPlayer?.removeFromSuperview()
            ksPlayer = nil
            model = nil
        }
    }
}
#endif

// MARK: - Custom Native SwiftUI Playback Overlay

public struct WebMControlsOverlay: View {
    @ObservedObject var model: WebMPlayerModel
    public let title: String?
    public let bottomInset: CGFloat

    public var body: some View {
        VStack {
            // Top Bar: Active Engine & Status
            HStack {
                if let title = title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer()

                // Engine Switcher Menu
                engineMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Center Loading or Error Indicator
            if model.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(1.4)
                    .padding(16)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            } else if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
            }

            Spacer()

            // Bottom Playback Controls Bar
            bottomControlsBar
                .padding(.bottom, bottomInset)
        }
    }

    // MARK: - Engine Selector Menu

    private var engineMenu: some View {
        Menu {
            ForEach(PlayerEngineType.allCases) { engine in
                Button {
                    model.switchEngine(to: engine)
                } label: {
                    HStack {
                        Text(engine.displayName)
                        if model.activeEngine == engine {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                Text(model.activeEngine.rawValue)
                    .font(.caption2.monospaced().weight(.bold))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
        }
    }

    // MARK: - Bottom Controls Bar

    private var bottomControlsBar: some View {
        VStack(spacing: 8) {
            // Interactive Scrubber & Time Labels
            HStack(spacing: 10) {
                Text(formatTime(model.isScrubbing ? model.scrubTime : model.currentTime))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundColor(.white)
                    .frame(minWidth: 42, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { model.isScrubbing ? model.scrubTime : model.currentTime },
                        set: { model.scrubTime = $0 }
                    ),
                    in: 0...max(model.duration, 1.0),
                    onEditingChanged: { editing in
                        if editing {
                            model.startScrubbing()
                        } else {
                            model.endScrubbing()
                        }
                    }
                )
                .tint(.orange)

                Text(formatTime(model.duration))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(minWidth: 42, alignment: .trailing)
            }

            // Interactive Playback Action Buttons
            HStack(spacing: 20) {
                // Play / Pause Toggle
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }

                // Skip 5 Seconds Back
                Button {
                    model.seek(to: max(0, model.currentTime - 5))
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                }

                // Skip 5 Seconds Forward
                Button {
                    model.seek(to: min(model.duration, model.currentTime + 5))
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                // Loop Toggle Button
                Button {
                    model.toggleLoop()
                } label: {
                    Image(systemName: model.isLooping ? "repeat.1" : "repeat")
                        .font(.headline)
                        .foregroundColor(model.isLooping ? .orange : .white.opacity(0.7))
                        .padding(6)
                        .background(model.isLooping ? Color.orange.opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                }

                // Audio Mute Toggle Button
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.headline)
                        .foregroundColor(model.isMuted ? .red : .white)
                        .padding(6)
                        .background(model.isMuted ? Color.red.opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                }

                // Picture-in-Picture Toggle Button
                Button {
                    model.togglePictureInPicture()
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(6)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 16)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

// MARK: - Main WebMPlayerView Component

public struct WebMPlayerView: View {
    public let url: URL
    public let autoPlay: Bool
    public let isLooping: Bool
    public let thumbnailURL: URL?
    public let title: String?
    public let bottomInset: CGFloat
    public let isActive: Bool
    public let onSingleTap: (() -> Void)?

    @StateObject private var model: WebMPlayerModel
    @State private var showControls: Bool = true

    public init(
        url: URL,
        autoPlay: Bool = true,
        isLooping: Bool = true,
        thumbnailURL: URL? = nil,
        title: String? = nil,
        bottomInset: CGFloat = 0,
        isActive: Bool = true,
        initialEngine: PlayerEngineType = .auto,
        onSingleTap: (() -> Void)? = nil
    ) {
        self.url = url
        self.autoPlay = autoPlay
        self.isLooping = isLooping
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.bottomInset = bottomInset
        self.isActive = isActive
        self.onSingleTap = onSingleTap

        self._model = StateObject(
            wrappedValue: WebMPlayerModel(
                url: url,
                autoPlay: autoPlay,
                isLooping: isLooping,
                initialEngine: initialEngine
            )
        )
    }

    /// Convenience initializer matching analysis & architecture spec
    public init(videoURL: URL) {
        self.init(url: videoURL)
    }

    /// Convenience initializer for post media files
    public init(
        file: MediaFile,
        autoPlay: Bool = true,
        isLooping: Bool = true,
        bottomInset: CGFloat = 0,
        isActive: Bool = true,
        onSingleTap: (() -> Void)? = nil
    ) {
        let safeURL: URL = {
            if let fullURL = file.fullURL {
                return fullURL
            }
            if let encodedPath = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = DomainConfigurationService.shared.buildURL(path: encodedPath) {
                return url
            }
            return DomainConfigurationService.shared.baseURL
        }()

        self.init(
            url: safeURL,
            autoPlay: autoPlay,
            isLooping: isLooping,
            thumbnailURL: file.thumbnailURL,
            title: file.displayname ?? file.name,
            bottomInset: bottomInset,
            isActive: isActive,
            onSingleTap: onSingleTap
        )
    }

    public var body: some View {
        ZStack {
            // Pure black canvas
            Color.black.ignoresSafeArea()

            // Thumbnail Preview (shown while loading)
            if model.isLoading, let thumbURL = thumbnailURL {
                AsyncImage(url: thumbURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    }
                }
            }

            // Active Video Engine Canvas
            Group {
                switch model.activeEngine {
                case .avPlayer:
                    AVPlayerBridgeView(model: model)
                case .webKit:
                    WebKitPlayerBridgeView(model: model)
                #if canImport(KSPlayer)
                case .ksPlayer:
                    KSPlayerBridgeView(model: model)
                #endif
                case .auto:
                    // Auto resolves in WebMPlayerModel init, fallback to WebKit
                    WebKitPlayerBridgeView(model: model)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                model.togglePlayPause()
            }
            .onTapGesture(count: 1) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                onSingleTap?()
            }

            // Native SwiftUI Playback Controls Overlay
            if showControls {
                WebMControlsOverlay(
                    model: model,
                    title: title,
                    bottomInset: bottomInset
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .id(url)
        .onAppear {
            if isActive && autoPlay {
                model.play()
            }
        }
        .onDisappear {
            model.pause()
        }
        .onValueChange(of: isActive) { active in
            if !active {
                model.pause()
            } else if autoPlay {
                model.play()
            }
        }
        .onValueChange(of: autoPlay) { model.autoPlay = $0 }
    }
}
