//
//  AudioSessionManager.swift
//  Makaba
//
//  Manages shared AVAudioSession lifecycle so playing WebM/MP4 attachments does not
//  permanently duck or pause user background music (Spotify, Apple Music).
//

import AVFoundation

public final class AudioSessionManager: @unchecked Sendable {
    public static let shared = AudioSessionManager()
    private var activePlaybackCount = 0
    private let lock = NSLock()

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }

    /// Activates playback audio session when video is unmuted and actively playing audio.
    public func activatePlayback() {
        lock.lock()
        defer { lock.unlock() }
        activePlaybackCount += 1
        if activePlaybackCount == 1 {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    /// Deactivates playback audio session when video is paused, muted, or dismissed, restoring ambient background audio.
    public func deactivatePlayback() {
        lock.lock()
        defer { lock.unlock() }
        guard activePlaybackCount > 0 else { return }
        activePlaybackCount -= 1
        if activePlaybackCount == 0 {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            lock.lock()
            activePlaybackCount = 0
            lock.unlock()
        }
    }
}
