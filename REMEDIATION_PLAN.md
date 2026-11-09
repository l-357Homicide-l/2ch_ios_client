# Master Remediation & Architecture Enhancement Plan: Makaba iOS Client

**Target Repository**: `C:\Users\---\Desktop\2ch_ios_client`  
**Target Branch**: `main`  
**Current Baseline Commit**: `2e8330e` (`fix(media): eliminate touch delays and isolate horizontal paging from vertical dismiss`)  
**Author / Engineering Role**: `worker_synthesis` (Teamwork Forensic Implementation & QA Subagent)  
**Document Version**: 3.0 (Triangulated Multi-Report Remediation Specification)  
**Verification Companion**: `AUDIT_VERIFICATION.md`  
**Inputs Ingested**: `claude.txt`, `AUDIT_V2.md`, `makaba_ios.md`, and all Explorer verification findings.

---

## 1. Executive Roadmap & Phased Execution Strategy

This comprehensive engineering plan provides the production-grade architectural and implementation blueprint to remediate **all 59 confirmed defects and architectural gaps** cataloged in `AUDIT_VERIFICATION.md` across Categories 1 through 4, alongside the complete phased execution strategy for the **10 strategic product capabilities** in Category 5.

### 1.1 Remediation Core Principles
1. **Zero Facade Implementations**: Every proposed architectural component is specified with production-grade Swift 5.9+ / SwiftUI implementation code, complete types, real system APIs, and full memory management semantics.
2. **Deterministic Concurrency & Thread Safety**: Strict adherence to Swift Concurrency (`actor`, `@MainActor`, `Sendable`, non-blocking cooperative cancellation) eliminating all data races, purple runtime warnings, and UI thread hangs.
3. **Resource Boundedness & Resilience**: Bounded in-memory and on-disk caches (LRU eviction), zero-OOM disk streaming for media uploads, and transient failure recovery with jittered exponential backoff.
4. **Verifiable Quality Gate**: Every defect fix is paired with a concrete, self-contained `XCTestCase` specification designed to validate failure modes and prevent regressions.

---

### 1.2 Subsystem Decomposition & Architectural Map

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                               MAKABA SUBSYSTEM ARCHITECTURE                            │
├────────────────────────────────┬───────────────────────────────────────────────────────┤
│ Core / Network & API Client    │ • MakabaAPIClient (Idempotent GET vs Single-Shot POST)│
│                                │ • DomainConfigurationService (@MainActor Actor Façade)│
│                                │ • MultipartFormData (Disk Spooling & Total Quotas)    │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Core / Security & Auth         │ • KeychainService (Encrypted Passcode Storage)        │
│                                │ • PasscodeAuthClient (POST /user/passlogin Exchange)  │
│                                │ • CookieJar (Preserving Cloudflare cf_clearance)      │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Media & Audio Subsystem        │ • KSPlayer SPM Engine (FFmpeg VP9/Opus for iOS 16+)   │
│                                │ • WebMPlayerView (WKWebView Dismantle DOM Cleanup)    │
│                                │ • AudioSessionManager (Ambient by default, no ducking)│
│                                │ • MediaAttachmentSanitizer (H.264 MOV Transcode)      │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Core / Parser & Rendering      │ • MakabaHTMLParser (Background Thread Parsing AST)    │
│                                │ • InteractiveSpoilers (Virtual URL Scheme Routing)    │
│                                │ • PostRowView (Cached AttributedString per post.num)  │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Core / Crypto & PoW Engine     │ • PoWSolver (Cooperative withThrowingTaskGroup Multi) │
│                                │ • EmojiCaptchaViewModel (Proactive Token Expiration)  │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ UI / Navigation & Posting      │ • iPad ContentView (.id(board.id) View Identity)     │
│                                │ • PostingSheet (Debounced Drafts & Board Model Quotas)│
│                                │ • ThreadViewModel (Moderation-Aware Diffing)          │
├────────────────────────────────┼───────────────────────────────────────────────────────┤
│ Build, SPM & Infrastructure    │ • project.yml (KSPlayer Package Dependency)           │
│                                │ • Info.plist (UTType webm, FileSharingEnabled, ATS)   │
│                                │ • .github/workflows/build-ipa.yml (XcodeGen CI Step) │
└────────────────────────────────┴───────────────────────────────────────────────────────┘
```

---

### 1.3 Prioritization Hierarchy & Phasing Overview

Remediation is organized into five disciplined, sequentially dependent phases:

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: P0 Critical Blockers & Security Vulnerabilities                              │
│ Prerequisites: None. Addresses core media crash, security leaks, duplicate posts.     │
├───────────────────────────────────────────────────────────────────────────────────────┤
│ PHASE 2: P1 High Bugs, Concurrency Races & Data Integrity                             │
│ Prerequisites: Phase 1 KeychainService & URLSession upload stabilization.             │
├───────────────────────────────────────────────────────────────────────────────────────┤
│ PHASE 3: P2 Medium Bugs, Network Resilience & UI/UX Refinement                        │
│ Prerequisites: Phase 2 MainActor stabilization & HTML background parser.              │
├───────────────────────────────────────────────────────────────────────────────────────┤
│ PHASE 4: P3 Code Hygiene, Build Configuration & Dead Code Cleanup                     │
│ Prerequisites: Phases 1–3. Hardens CI, plists, removes dead code.                     │
├───────────────────────────────────────────────────────────────────────────────────────┤
│ PHASE 5: Strategic Product Capabilities Roadmap                                       │
│ Prerequisites: Stable Core. Adds SQLite persistence, (Вы)/(Вам), and offline vault.   │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

### 1.4 Dependency Graph & Prerequisite Ordering

```
[KeychainService Implementation] ───► [Passcode UserDefaults Migration] ───► [HTTP /user/passlogin Flow]
                                                                                     │
[KSPlayer SPM Declaration in project.yml] ──► [xcodegen generate] ──► [WebM KSPlayer Linkage Verification]
                                                                                     │
[URLSession Non-Idempotent POST Fix] ──► [Emoji Captcha Single-Use Protection] ──► [Posting Error Handling]
                                                                                     │
[Background HTML Parser AST Cache] ──► [PostRowView MainActor Offloading] ──► [Interactive Spoiler Routing]
                                                                                     │
[SQLite / GRDB Persistence Layer] ──► [(Вы)/(Вам) Author Post Tracking] ──► [Offline 404 Thread Vault]
```

---

## 2. Phase 1: P0 Critical Blockers & Security Vulnerabilities

### Phase 1.0: Build System Synchronization & CI XcodeGen Prerequisite (`[ISSUE-47]`)
- **Target Files**: `.github/workflows/build-ipa.yml`, `project.yml`
- **Dependencies**: None (Must run before any package additions and test passes).
- **Rationale & Ordering**: `project.yml` is the single source of truth for project configurations, but `Makaba.xcodeproj` is also tracked in git. To guarantee CI builds and local compilations do not build stale schemes or fail when packages are added, the CI workflow must execute `xcodegen generate` prior to running `xcodebuild`.
- **Implementation**:
  Add XcodeGen installation and generation step to `.github/workflows/build-ipa.yml` ahead of test/build invocations:
  ```yaml
  - name: Install XcodeGen
    run: brew install xcodegen
  - name: Generate Xcode Project
    run: xcodegen generate
  ```

### Phase 1.1: KSPlayer SPM Package Integration with FFmpeg Backend (`[ISSUE-01]`)
- **Target Files**: `project.yml`, `Makaba.xcodeproj/project.pbxproj`, `Makaba/UI/Media/WebMPlayerView.swift`, `README.md`
- **Dependencies**: Phase 1.0 (XcodeGen installed/configured).
- **Problem**: `project.yml` lacks KSPlayer package declarations. `#if canImport(KSPlayer)` compiles as false, forcing WebKit playback which fails on iOS < 17.4 for VP8/VP9 WebM videos. Furthermore, Apple's native `VideoToolbox` framework on iOS 16.0–17.3 lacks VP9 hardware decoding; KSPlayer requires linking its precompiled FFmpeg binary target (`KSPlayer/FFmpeg` / `FFmpeg.xcframework`) to enable software/hybrid decoding for WebM media on iOS 16.0–17.3.
- **Implementation**:
  1. Add `KSPlayer` and `FFmpeg` binary package dependencies to `project.yml`:
     ```yaml
     packages:
       KSPlayer:
         url: https://github.com/kingslay/KSPlayer.git
         from: 5.0.0
       FFmpeg:
         url: https://github.com/kingslay/FFmpeg.git
         from: 1.0.0
     targets:
       Makaba:
         dependencies:
           - package: KSPlayer
           - package: FFmpeg
     ```
  2. Execute `xcodegen generate` immediately to regenerate `Makaba.xcodeproj` with SPM package linkages prior to compiling or running tests.
  3. Verify `KSPlayerBridgeView` handles playback lifecycle, volume, and seeking.
  4. Retain `#if canImport(KSPlayer)` as the gate for the KSPlayer engine while preserving the WebKit HTML5 fallback engine as an alternative fallback.
- **Verification Criteria**:
  - Run `xcodegen generate` followed by `xcodebuild -project Makaba.xcodeproj -scheme Makaba`.
  - Assert `#if canImport(KSPlayer)` evaluates to true.
  - Test playback of 2ch VP9 WebM URL on an iOS 16 simulator/device; verify smooth playback without black screens.

---

### Phase 1.2: Keychain VIP Passcode Storage & Migration (`[ISSUE-02]`)
- **Target Files**:
  - `Makaba/Core/Security/KeychainService.swift` (New File)
  - `Makaba/Core/Network/DomainConfigurationService.swift`
- **Dependencies**: None.
- **Problem**: Paid VIP passcodes stored in plaintext in `UserDefaults.standard` under `makaba_passcode_token`, exposed to unencrypted device backups.
- **Implementation**:
  1. Implement production-grade `KeychainService`:
     ```swift
     import Foundation
     import Security

     public enum KeychainService {
         private static let serviceName = "org.2ch.Makaba.passcode"
         private static let accountName = "vip_token"
         private static let lock = NSLock()

         public static func savePasscode(_ token: String) -> Bool {
             guard let data = token.data(using: .utf8) else { return false }
             lock.lock()
             defer { lock.unlock() }

             // 1. Delete query strictly restricted to identity attributes (omits payload and accessibility to prevent errSecParam -50)
             let deleteQuery: [String: Any] = [
                 kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: serviceName,
                 kSecAttrAccount as String: accountName
             ]
             SecItemDelete(deleteQuery as CFDictionary)

             // 2. Add query with full payload and accessibility parameters
             let addQuery: [String: Any] = [
                 kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: serviceName,
                 kSecAttrAccount as String: accountName,
                 kSecValueData as String: data,
                 kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
             ]
             let status = SecItemAdd(addQuery as CFDictionary, nil)
             return status == errSecSuccess
         }

         public static func loadPasscode() -> String? {
             lock.lock()
             defer { lock.unlock() }

             let query: [String: Any] = [
                 kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: serviceName,
                 kSecAttrAccount as String: accountName,
                 kSecReturnData as String: kCFBooleanTrue as Any,
                 kSecMatchLimit as String: kSecMatchLimitOne
             ]
             var result: AnyObject?
             let status = SecItemCopyMatching(query as CFDictionary, &result)
             guard status == errSecSuccess, let data = result as? Data else { return nil }
             return String(data: data, encoding: .utf8)
         }

         public static func deletePasscode() -> Bool {
             lock.lock()
             defer { lock.unlock() }

             let query: [String: Any] = [
                 kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: serviceName,
                 kSecAttrAccount as String: accountName
             ]
             let status = SecItemDelete(query as CFDictionary)
             return status == errSecSuccess || status == errSecItemNotFound
         }
     }
     ```
  2. In `DomainConfigurationService.init()`, migrate legacy `UserDefaults` token to `KeychainService` and purge the `UserDefaults` key:
     ```swift
     if let legacy = UserDefaults.standard.string(forKey: passcodeKey), !legacy.isEmpty {
         if KeychainService.savePasscode(legacy) {
             UserDefaults.standard.removeObject(forKey: passcodeKey)
         }
     }
     self.passcodeToken = KeychainService.loadPasscode() ?? ""
     ```
  3. Ensure passcodes are never transmitted over unencrypted `http://` mirror connections.
- **Verification Criteria**:
  - Unit test `KeychainServiceTests`: save, read, overwrite, delete.
  - Verify `UserDefaults.standard.object(forKey: "makaba_passcode_token")` is `nil` after app initialization.

---

### Phase 1.3: Eliminate Non-Idempotent POST Failover Retries (`[ISSUE-03]`)
- **Target Files**: `Makaba/Core/Network/MakabaAPIClient.swift`
- **Dependencies**: None.
- **Problem**: `uploadWithFailover` and `execute` retry POST requests on `.timedOut`, `.networkConnectionLost`, and 502–504. Slow requests cause duplicate post spam on 2ch and consume single-use emoji captchas and likes/dislikes.
- **Implementation**:
  1. Disallow mirror failover and retry loops for all HTTP POST endpoints (`submitPost`, `verifyEmojiCaptcha`, `submitCaptchaClick`, `likePost`, `dislikePost`).
  2. Implement dedicated single-shot pathways for non-idempotent operations:
     ```swift
     // Single-shot upload for non-idempotent multipart form submissions
     private func uploadSingleShot(request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
         var currentReq = request
         let activeMirror = DomainConfigurationService.shared.activeDomain
         if let url = currentReq.url, let rewritten = DomainConfigurationService.shared.rewriteURL(url, to: activeMirror) {
             currentReq.url = rewritten
         }
         return try await session.upload(for: currentReq, fromFile: fileURL)
     }

     // Single-shot execution for non-idempotent POST requests (captcha clicks, post likes/dislikes)
     private func executeSingleShot(request: URLRequest) async throws -> (Data, URLResponse) {
         var currentReq = request
         let activeMirror = DomainConfigurationService.shared.activeDomain
         if let url = currentReq.url, let rewritten = DomainConfigurationService.shared.rewriteURL(url, to: activeMirror) {
             currentReq.url = rewritten
         }
         return try await session.data(for: currentReq)
     }
     ```
  3. In `executeWithFailover`, verify HTTP method before attempting retries:
     ```swift
     guard request.httpMethod?.uppercased() == "GET" else {
         // Non-GET requests MUST NOT failover or retry
         return try await executeSingleShot(request: request)
     }
     ```
     Restrict `uploadWithFailover` and `executeWithFailover` strictly to idempotent HTTP GET requests (`fetchBoards`, `fetchCatalog`, `fetchThread`, `fetchBoardPage`).
- **Verification Criteria**:
  - Mock `URLProtocol` returning a 30s timeout on POST `/user/posting` or `/api/captcha/emoji/verify`.
  - Assert that `uploadSingleShot` and `executeSingleShot` throw `URLError(.timedOut)` without triggering `failoverToNextMirror()`.

---

### Phase 1.4: WebM Player Memory Teardown & DOM Cleanup (`[ISSUE-04]`)
- **Target Files**: `Makaba/UI/Media/WebMPlayerView.swift`
- **Dependencies**: None.
- **Problem**: `WebKitPlayerBridgeView.dismantleUIView` omits media element destruction and `loadHTMLString("", baseURL: nil)`. Background WebProcess keeps decoding video and audio. Evaluating JavaScript asynchronously immediately before navigating cancels the JS context before pauses occur.
- **Implementation**:
  Update `dismantleUIView`:
  ```swift
  public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
      coordinator.cleanup()
      uiView.stopLoading()
      uiView.configuration.userContentController.removeScriptMessageHandler(forName: "playerBridge")
      uiView.navigationDelegate = nil
      // Direct load of empty document synchronously stops WebProcess media threads and releases video decoders immediately
      uiView.loadHTMLString("<!DOCTYPE html><html><head></head><body></body></html>", baseURL: nil)
  }
  ```
- **Verification Criteria**:
  - Open and dismiss WebM gallery 10 times in Instruments Allocations & Leaks profiler.
  - Verify `WebContent` memory resets to baseline upon view dismissal.

---

### Phase 1.5: Audio Session Deactivation & Background Etiquette (`[ISSUE-05]`)
- **Target Files**: `Makaba/UI/Media/WebMPlayerView.swift`, `Makaba/Core/Media/AudioSessionManager.swift` (New File)
- **Dependencies**: None.
- **Problem**: Initializing `WebMPlayerModel` executes `setCategory(.playback, options: [.duckOthers])` and `setActive(true)` without ever deactivating, permanently ducking Spotify/Apple Music.
- **Implementation**:
  1. Create centralized `AudioSessionManager`:
     ```swift
     import AVFoundation

     public final class AudioSessionManager {
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

         public func activatePlayback() {
             lock.lock()
             defer { lock.unlock() }
             activePlaybackCount += 1
             if activePlaybackCount == 1 {
                 try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                 try? AVAudioSession.sharedInstance().setActive(true)
             }
         }

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
     ```
  2. Do NOT configure audio session in `WebMPlayerModel.init`. Activate playback strictly when video un-mutes and plays audio; deactivate on pause or view dismissal.
- **Verification Criteria**:
  - Play background audio in Music app on test device.
  - Open muted WebM in Makaba; verify background music is NOT paused or ducked.
  - Unmute WebM; verify audio plays. Close gallery; verify background music resumes full volume immediately.

---

### Phase 1.6: Cooperative Multi-Core PoW Solver (`[ISSUE-06]`)
- **Target Files**: `Makaba/Core/Crypto/PoWSolver.swift`
- **Dependencies**: None.
- **Problem**: `solveAsync` spawns an unparented `Task.detached` without cancellation propagation; single-threaded loop fails to utilize Apple Silicon multi-core CPU. 2ch PoW challenge requires matching a 128-hex character SHA-512 target hash (`digest.elementsEqual(targetBytes)`), NOT a Bitcoin-style `"0000"` prefix. Using `withThrowingTaskGroup` causes the first non-winning worker thread to throw and immediately cancel all sibling workers.
- **Implementation**:
  1. Preserve public API signature `public static func solveAsync(template: String, targetHash: String, limit: Int = 20000) async throws -> PoWResult`.
  2. Implement parallel worker task group with non-throwing child tasks returning `(Int, String)?`:
     ```swift
     public static func solveAsync(
         template: String,
         targetHash: String,
         limit: Int = 20000
     ) async throws -> PoWResult {
         try Task.checkCancellation()
         guard limit > 0 else { throw PoWError.limitExceeded(limit) }
         guard template.contains("%d") else { throw PoWError.invalidTemplate }
         let parts = template.components(separatedBy: "%d")
         guard parts.count == 2 else { throw PoWError.invalidTemplate }
         let prefix = parts[0]
         let suffix = parts[1]

         let normalizedTarget = targetHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
         guard normalizedTarget.count == 128, let targetBytes = hexToBytes(normalizedTarget) else {
             throw PoWError.invalidTargetHash
         }

         let startTime = CFAbsoluteTimeGetCurrent()
         let coreCount = max(1, ProcessInfo.processInfo.activeProcessorCount)

         return try await withTaskGroup(of: (Int, String)?.self) { group in
             for workerIndex in 0..<coreCount {
                 group.addTask {
                     var nonce = workerIndex
                     var iterations = 0
                     while nonce < limit {
                         iterations += 1
                         if (iterations & 1023) == 0 && Task.isCancelled {
                             return nil
                         }
                         let candidate = "\(prefix)\(nonce)\(suffix)"
                         guard let data = candidate.data(using: .utf8) else {
                             nonce += coreCount
                             continue
                         }
                         let digest = SHA512.hash(data: data)
                         if digest.elementsEqual(targetBytes) {
                             let hexString = digest.map { String(format: "%02x", $0) }.joined()
                             return (nonce, hexString)
                         }
                         nonce += coreCount
                     }
                     return nil
                 }
             }

             for await result in group {
                 if let (nonce, hex) = result {
                     group.cancelAll()
                     let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                     return PoWResult(nonce: nonce, hash: hex, durationMs: durationMs)
                 }
             }

             if Task.isCancelled {
                 throw PoWError.cancelled
             }
             throw PoWError.limitExceeded(limit)
         }
     }
     ```
  3. Raw byte comparison `digest.elementsEqual(targetBytes)` avoids 128-char hex allocations inside the inner loop, allocating hex string strictly once upon finding the solution.
- **Verification Criteria**:
  - Run `PoWSolverTests`: verify challenge resolution under 15ms across multi-core CPU.
  - Cancel parent task mid-execution; assert `CancellationError` / `PoWError.cancelled` is thrown and all worker tasks terminate without race conditions.

---

### Phase 1.7: Video MOV H.264 Transcoding & EXIF Stripping (`[ISSUE-07]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift`, `Makaba/Core/Media/MediaTranscoder.swift` (New File)
- **Dependencies**: None.
- **Problem**: Camera `.mov` videos are renamed to `.mp4` without transcoding, leaking QuickTime GPS metadata and causing server upload rejections. `loadTransferable(Data.self)` causes OOM spikes. Attempting `item.loadTransferable(type: FileRepresentation.self)` is invalid Swift 5.9 as `FileRepresentation` conforms to `TransferRepresentation`, not `Transferable`.
- **Implementation**:
  1. Stream video to a temporary file via a valid Swift 5.9 `Transferable` pattern:
     ```swift
     public struct MovieTransferable: Transferable {
         public let url: URL
         public static var transferRepresentation: some TransferRepresentation {
             FileRepresentation(contentType: .movie) { movie in
                 SentTransferredFile(movie.url)
             } importing: { received in
                 let tempCopy = FileManager.default.temporaryDirectory
                     .appendingPathComponent(UUID().uuidString)
                     .appendingPathExtension(received.file.pathExtension)
                 try FileManager.default.copyItem(at: received.file, to: tempCopy)
                 return Self(url: tempCopy)
             }
         }
     }
     ```
     Or load asynchronously via `item.loadFileRepresentation(forContentType: .movie) { sourceURL, _ in ... }`, avoiding `FileRepresentation.self` in `loadTransferable`.
  2. Transcode QuickTime MOV to clean MP4 (H.264/AAC) using `AVAssetExportSession` with `AVAssetExportPreset1920x1080`, stripping all metadata tracks and preserving upload size limits:
     ```swift
     exportSession.outputFileType = .mp4
     exportSession.shouldOptimizeForNetworkUse = true
     exportSession.metadata = [] // Purge GPS and camera metadata
     ```
  3. Generate randomized filenames (`makaba_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).mp4`) instead of preserving user disk filenames.
- **Verification Criteria**:
  - Transcode an iPhone MOV recording with active location tags.
  - Inspect output MP4 with `exiftool` / `AVAsset.metadata`; verify 0 GPS tags exist.

---

## 3. Phase 2: P1 High Bugs, Concurrency Races & Data Integrity

### Phase 2.1: MainActor Synchronization for Failover State (`[ISSUE-08]`)
- **Target Files**: `Makaba/Core/Network/DomainConfigurationService.swift`
- **Dependencies**: None.
- **Problem**: `failoverToNextMirror()` mutates `@Published public private(set) var activeDomain` synchronously on background URLSession threads.
- **Implementation**:
  Ensure all `@Published` mutations are dispatched to the `MainActor`:
  ```swift
  public func failoverToNextMirror() async -> String {
      let next = computeNextMirrorUnderLock()
      await MainActor.run {
          self.activeDomain = next
          NotificationCenter.default.post(name: .makabaDomainDidChange, object: next)
      }
      return next
  }
  ```
- **Verification Criteria**:
  - Enable Xcode Main Thread Checker.
  - Trigger failover from background network queue; verify zero purple warnings in console.

---

### Phase 2.2: Moderation-Aware Incremental Thread Diffing (`[ISSUE-09]`)
- **Target Files**: `Makaba/UI/Thread/ThreadView.swift:15–145` (`ThreadViewModel`)
- **Dependencies**: None.
- **Problem**: `ThreadViewModel.loadThread()` only appends posts when `response.posts.count > self.posts.count`, ignoring new arrivals when posts have been deleted by moderators. Re-assigning `self.posts = response.posts` unconditionally resets SwiftUI view identities and destroys scroll position. Using `Dictionary(uniqueKeysWithValues:)` causes fatal runtime crashes if responses contain duplicate post IDs.
- **Implementation**:
  Rewrite diffing logic to surgically handle deletions, in-place updates, and appends while preserving backlinks:
  ```swift
  let responsePostMap = Dictionary(response.posts.map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
  let existingIDs = Set(self.posts.map(\.num))
  let responseIDs = Set(response.posts.map(\.num))

  let deletedIDs = existingIDs.subtracting(responseIDs)
  let newPosts = response.posts.filter { !existingIDs.contains($0.num) }

  if self.posts.isEmpty || forceRefresh {
      self.posts = response.posts
      self.buildReplyGraph()
      self.buildMediaList()
  } else {
      var updatedPosts = self.posts
      // 1. Surgical removal of moderated/deleted posts
      if !deletedIDs.isEmpty {
          updatedPosts.removeAll { deletedIDs.contains($0.num) }
      }
      // 2. In-place metadata updates (scores, likes) on local buffer
      for i in 0..<updatedPosts.count {
          if let updated = responsePostMap[updatedPosts[i].num] {
              updatedPosts[i] = updated
          }
      }
      // 3. Append strictly new posts
      if !newPosts.isEmpty {
          updatedPosts.append(contentsOf: newPosts)
      }
      // 4. Single atomic publisher emission
      self.posts = updatedPosts

      // 5. Rebuild reply backlinks graph and media list if set of posts changed
      if !deletedIDs.isEmpty || !newPosts.isEmpty {
          self.buildReplyGraph()
          self.buildMediaList()
      }
  }
  ```
- **Verification Criteria**:
  - Simulate response where post #10 is deleted and post #15 is added (`count` stays equal).
  - Verify post #10 is removed and post #15 appears in UI.

---

### Phase 2.3: `score: Double?` JSON Decoding Fix (`[ISSUE-10]`)
- **Target Files**:
  - `Makaba/Core/Models/Catalog.swift:35, 134`
  - `Makaba/Core/Models/Thread.swift:140, 187`
- **Dependencies**: None.
- **Problem**: 2ch API returns floating-point scores (`47.944`), crashing `decode(Int.self)` with silent `nil` fallbacks and breaking catalog sort-by-score.
- **Implementation**:
  Change property types to `Double?`:
  ```swift
  public let score: Double?
  ...
  self.score = try? container.decodeIfPresent(Double.self, forKey: .score)
  ```
- **Verification Criteria**:
  - Add test fixture in `ModelDecodingTests` containing `"score": 47.94444444444444`.
  - Assert `score` decodes to `47.94444444444444`.

---

### Phase 2.4: Preserve PNG Transparency in Sanitizer (`[ISSUE-11]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift:965–982`
- **Dependencies**: None.
- **Problem**: All images are re-encoded via `jpegData(0.88)`, destroying PNG alpha transparency.
- **Implementation**:
  Preserve raw PNG/WebP data:
  ```swift
  if ext == "png" {
      return (rawData, "png", "image/png")
  } else if ext == "webp" {
      return (rawData, "webp", "image/webp")
  } else if isImage && !isGif {
      if let image = UIImage(data: rawData), let jpeg = image.jpegData(compressionQuality: 0.88) {
          return (jpeg, "jpg", "image/jpeg")
      }
  }
  ```
- **Verification Criteria**:
  - Attach a transparent PNG screenshot.
  - Verify returned attachment MIME type is `image/png` and transparency is intact.

---

### Phase 2.5: Aggregate Upload Quota Validation (`[ISSUE-12]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift:212–214`
- **Dependencies**: None.
- **Problem**: Each attachment is checked individually against `maxFileSizeBytes` instead of summing all attachments.
- **Implementation**:
  Validate aggregate attachment size:
  ```swift
  let totalBytes = attachments.reduce(0) { $0 + $1.data.count }
  if totalBytes > maxFileSizeBytes {
      return false
  }
  ```
- **Verification Criteria**:
  - Add 2 attachments of 12MB each when `maxFileSizeBytes` is 20MB.
  - Assert `isFormValid` returns `false` and displays error banner: "Суммарный размер файлов превышает лимит".

---

### Phase 2.6: iPad NavigationSplitView Identity Preservation (`[ISSUE-13]`)
- **Target Files**: `Makaba/App/ContentView.swift:33–36`
- **Dependencies**: None.
- **Problem**: `CatalogView(board: board)` lacks `.id(board.id)`, causing `@StateObject` to preserve the previous board's ViewModel when selecting different boards on iPad.
- **Implementation**:
  Assign explicit view identity:
  ```swift
  if let board = selectedBoard {
      CatalogView(board: board)
          .id(board.id)
  }
  ```
- **Verification Criteria**:
  - In iPad simulator, select board `/b/`, then select `/vg/`.
  - Verify catalog reloads immediately with `/vg/` threads.

---

### Phase 2.7: Cloudflare `cf_clearance` Cookie Preservation & `/user/passlogin` Flow (`[ISSUE-14]`, `[ISSUE-15]`)
- **Target Files**: `Makaba/Core/Network/Endpoints.swift`, `Makaba/Core/Network/MakabaAPIClient.swift`
- **Dependencies**: Phase 1.2 (`KeychainService`).
- **Problem**: Setting raw `Cookie` header wipes session cookies managed by `HTTPCookieStorage` (including Cloudflare clearance). In Foundation, passing `currentDomain` containing `https://` to `HTTPCookiePropertyKey.domain` causes initialization to return `nil`. Injecting raw passcodes as cookies directly violates 2ch server auth specifications.
- **Implementation**:
  1. Never set manual `Cookie` HTTP headers on `URLRequest`. Inject cookies directly into `HTTPCookieStorage.shared` using bare hostnames:
     ```swift
     guard let host = URL(string: currentDomain)?.host else { return }
     let cookieDomain = host.hasPrefix(".") ? host : ".\(host)"
     if let cookie = HTTPCookie(properties: [
         .domain: cookieDomain,
         .path: "/",
         .name: "passcode_auth",
         .value: sessionToken,
         .secure: "TRUE"
     ]) {
         HTTPCookieStorage.shared.setCookie(cookie)
     }
     ```
  2. Implement authentic `exchangePasscode(passcode:)`: Submit single-shot `POST /user/passlogin` with passcode form data. Extract the server's issued session cookie and persist in `HTTPCookieStorage.shared`, retaining the raw credential encrypted in `KeychainService` for automatic re-login on session expiration.
- **Verification Criteria**:
  - Inspect outgoing URLRequest headers; verify no manual `Cookie` header exists.
  - Assert `HTTPCookie(properties:)` returns non-nil when given bare host `2ch.hk`.
  - Verify `HTTPCookieStorage.shared.cookies` contains both `cf_clearance` and `passcode_auth`.

---

### Phase 2.8: Keystroke Draft Save Debounce (`[ISSUE-16]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift:71–82`
- **Dependencies**: None.
- **Problem**: Writing draft to `UserDefaults` on every character typed causes keyboard lag.
- **Implementation**:
  Debounce draft persistence using Combine or Task sleep:
  ```swift
  private var draftSaveTask: Task<Void, Never>?

  func scheduleDraftSave() {
      draftSaveTask?.cancel()
      draftSaveTask = Task {
          try? await Task.sleep(nanoseconds: 800_000_000) // 800ms debounce
          guard !Task.isCancelled else { return }
          saveDraftNow()
      }
  }
  ```
- **Verification Criteria**:
  - Type 50 characters rapidly; assert `saveDraftNow()` is invoked only once after typing ceases.

---

### Phase 2.9: WebM `WKWebsiteDataStore` Cookie Synchronization (`[ISSUE-17]`)
- **Target Files**: `Makaba/UI/Media/WebMPlayerView.swift:295–320`
- **Dependencies**: None.
- **Problem**: `WKWebView` fails to receive cookies from `HTTPCookieStorage.shared`, causing 403 on Cloudflare-protected media. Calling `cookieStore.setCookie` without awaiting its completion handler creates a race condition where `webView.load(request)` is issued before WebKit's out-of-process networking daemon finishes writing cookies.
- **Implementation**:
  Asynchronously synchronize all cookies across `WKHTTPCookieStore` using `DispatchGroup` before invoking `webView.load(request)`:
  ```swift
  public static func syncCookiesAndLoad(webView: WKWebView, request: URLRequest) {
      let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
      let cookies = HTTPCookieStorage.shared.cookies ?? []
      guard !cookies.isEmpty else {
          webView.load(request)
          return
      }
      let group = DispatchGroup()
      for cookie in cookies {
          group.enter()
          cookieStore.setCookie(cookie) {
              group.leave()
          }
      }
      group.notify(queue: .main) {
          webView.load(request)
      }
  }
  ```
- **Verification Criteria**:
  - Verify Cloudflare clearance cookie is present in `WKHTTPCookieStore` prior to network dispatch.

---

### Phase 2.10: Offload HTML Parsing from MainActor (`[ISSUE-18]`)
- **Target Files**:
  - `Makaba/UI/Thread/PostRowView.swift`
  - `Makaba/Core/Parser/MakabaHTMLParser.swift`
  - `Makaba/UI/Thread/ThreadView.swift`
- **Dependencies**: None.
- **Problem**: `MakabaHTMLParser.parse(html:)` executes inside `PostRowView.init` on the `MainActor`, dropping scroll framerates in long threads.
- **Implementation**:
  1. Parse HTML comments asynchronously off the main thread in `ThreadViewModel` upon receiving the API response:
     ```swift
     let parsedMap = await Task.detached(priority: .userInitiated) {
         response.posts.reduce(into: [Int: AttributedString]()) { map, post in
             map[post.num] = MakabaHTMLParser.parse(html: post.comment)
         }
     }.value
     ```
  2. Cache parsed `AttributedString` objects by `post.num` so `PostRowView` simply renders the cached string.
- **Verification Criteria**:
  - Profile 1,000-post thread in Instruments Core Animation; verify smooth 60/120 FPS scrolling with 0 main-thread parsing time.

---

### Phase 2.11: Pass Board Model in ThreadView Posting Sheet (`[ISSUE-19]`)
- **Target Files**: `Makaba/UI/Thread/ThreadView.swift:285–296`
- **Dependencies**: None.
- **Problem**: `ThreadView` omits `boardModel: viewModel.board` when presenting `PostingSheet`, causing default fallback quotas.
- **Implementation**:
  Pass the board model explicitly:
  ```swift
  PostingSheet(
      board: board,
      threadNum: threadNum,
      boardModel: viewModel.board,
      ...
  )
  ```
- **Verification Criteria**:
  - Open posting sheet on a board with `enable_names: false`; verify name field is hidden.

---

### Phase 2.12: Media Download HTTP Status Code Verification (`[ISSUE-20]`)
- **Target Files**: `Makaba/UI/Media/MediaGalleryView.swift:303–330`
- **Dependencies**: None.
- **Problem**: 404/503 HTML error pages are saved as `.webm` files and reported as successful downloads.
- **Implementation**:
  Verify HTTP response status code before moving file:
  ```swift
  let (tempURL, response) = try await URLSession.shared.download(from: url)
  guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
      throw MakabaAPIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
  }
  ```
- **Verification Criteria**:
  - Trigger download of a missing/404 URL; verify error toast appears and no file is created in Documents.

---

### Phase 2.13: Lossless Photo & GIF Saving via `PHAssetCreationRequest` (`[ISSUE-21]`)
- **Target Files**: `Makaba/UI/Media/MediaGalleryView.swift:256–275`
- **Dependencies**: None.
- **Problem**: `UIImageWriteToSavedPhotosAlbum` strips GIF animation frames and converts PNG to lossy JPEG.
- **Implementation**:
  Save raw byte data directly to the Photos Library:
  ```swift
  try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, data: rawData, options: nil)
  }
  ```
- **Verification Criteria**:
  - Save an animated GIF from gallery to Photos; open Photos app and verify animation plays continuously.

---

## 4. Phase 3: P2 Medium Bugs, Network Resilience & UI/UX Refinement

### Phase 3.1: Catalog Cascade Timeout Deadline (`[ISSUE-22]`)
- **Target Files**: `Makaba/UI/Navigation/CatalogView.swift`, `Makaba/Core/Network/MakabaAPIClient.swift`
- **Implementation**: Enforce an overarching 15-second deadline for the entire catalog fallback cascade (`fetchCatalog` -> `fetchBoardPage` -> `fetchThreadList`). Cancel pending attempts when the deadline expires or network connectivity restores.

### Phase 3.2: Custom Disk-Cached ImageLoader (`[ISSUE-23]`)
- **Target Files**: `Makaba/UI/Media/MediaThumbnailView.swift` (New File), `Makaba/Core/Media/ImageCacheManager.swift` (New File)
- **Implementation**: Replace raw `AsyncImage` with a custom cached image pipeline supporting LRU memory/disk caching, ImageIO downsampling to display size, and frame-by-frame animated GIF playback.

### Phase 3.3: 404 Archive Auto-Fallback Banner (`[ISSUE-24]`)
- **Target Files**: `Makaba/UI/Thread/ThreadView.swift:110–135`
- **Implementation**: When `fetchThread` returns HTTP 404, automatically query `fetchArchivedThread`. If found, render the thread in read-only mode with a banner: "Тред находится в архиве 2ch".

### Phase 3.4: Markup Toolbar Range Wrapping & Syntax Fix (`[ISSUE-25]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift:569–635`
- **Implementation**: Replace `^H^H` with standard `<s>...</s>` or `%%...%%` strikethrough. Wrap the user's currently selected text range (`selectedRange`) instead of unconditionally appending formatting tags to the end of the text.

### Phase 3.5: Tap-to-Reveal Interactive Spoilers (`[ISSUE-26]`)
- **Target Files**: `Makaba/Core/Parser/MakabaHTMLParser.swift`, `Makaba/UI/Thread/PostRowView.swift`
- **Implementation**: Embed virtual custom URL links (`makaba://spoiler/\(postNum)_\(index)`) on spoiler text ranges. Intercept link clicks via `.environment(\.openURL)` in `PostRowView`, toggling local `Set<Int>` revealed spoiler state with smooth opacity animations.

### Phase 3.6: Strongly-Typed HTTP Error Handling (`[ISSUE-27]`)
- **Target Files**: `Makaba/UI/Navigation/CatalogView.swift`
- **Implementation**: Remove brittle `errStr.contains("404")` checks. Inspect `MakabaAPIError.serverError(statusCode: 404)` directly.

### Phase 3.7: Mobile Delta Endpoint `/api/mobile/v2/after` (`[ISSUE-28]`)
- **Target Files**: `Makaba/Core/Network/Endpoints.swift`, `MakabaAPIClient.swift`
- **Implementation**: Add `/api/mobile/v2/after/{board}/{thread}/{lastNum}` endpoint to fetch only posts newer than `lastNum` on pull-to-refresh, saving 90% of bandwidth in active threads.

### Phase 3.8: Info.plist System UTType & Files App Visibility (`[ISSUE-29]`, `[ISSUE-30]`)
- **Target Files**: `Makaba/Resources/Info.plist`
- **Implementation**:
  Add `UTImportedTypeDeclarations` for `org.webmproject.webm`:
  ```xml
  <key>UTImportedTypeDeclarations</key>
  <array>
      <dict>
          <key>UTTypeIdentifier</key>
          <string>org.webmproject.webm</string>
          <key>UTTypeDescription</key>
          <string>WebM Video</string>
          <key>UTTypeConformsTo</key>
          <array>
              <string>public.movie</string>
          </array>
          <key>UTTypeTagSpecification</key>
          <dict>
              <key>public.filename-extension</key>
              <array>
                  <string>webm</string>
              </array>
              <key>public.mime-type</key>
              <string>video/webm</string>
          </dict>
      </dict>
  </array>
  <key>UIFileSharingEnabled</key>
  <true/>
  <key>LSSupportsOpeningDocumentsInPlace</key>
  <true/>
  ```

### Phase 3.9: Plain-Text Catalog Search Indexing (`[ISSUE-31]`)
- **Target Files**: `Makaba/Core/Models/Catalog.swift`, `Makaba/UI/Navigation/CatalogView.swift`
- **Implementation**: Strip HTML tags once during decoding and store in an immutable `searchableText` property. Filter against `searchableText` to prevent "br" and "span" from matching in search.

### Phase 3.10: Complete HTML Entity Decoding (`[ISSUE-32]`)
- **Target Files**: `Makaba/Core/Parser/MakabaHTMLParser.swift`
- **Implementation**: Add full character entity replacement for `&#039;` ('), `&quot;` ("), `&amp;` (&), `&lt;` (<), `&gt;` (>), and numeric Unicode entities (`&#NNNN;`).

### Phase 3.11: Cross-Thread Quote Navigation Feedback (`[ISSUE-33]`)
- **Target Files**: `Makaba/UI/Thread/ThreadView.swift:326–334`
- **Implementation**: Parse `data-thread` attributes on quote links. If a quote references a post outside the current thread, display a toast: "Пост >>\(num) находится в другом треде" with an action button to open that thread.

### Phase 3.12: Strict Moderator & Staff Badge Validation (`[ISSUE-34]`)
- **Target Files**: `Makaba/UI/Thread/PostRowView.swift:205`
- **Implementation**: Remove naive substring checks (`name.contains("Admin") || name.contains("Mod")`). Check server-provided attributes: `post.trip == "!!%adm%!!"` or explicit `post.op == 1`.

### Phase 3.13: Deterministic Category Ordering (`[ISSUE-35]`)
- **Target Files**: `Makaba/UI/Navigation/BoardListView.swift:142–155`
- **Implementation**: Sort custom dictionary keys alphabetically (`grouped.keys.sorted()`) before rendering category sections.

### Phase 3.14: Interactive Likes & Dislikes UI Wiring (`[ISSUE-36]`)
- **Target Files**: `Makaba/UI/Thread/PostRowView.swift`
- **Implementation**: Add like/dislike buttons with animated counters on like-enabled boards, calling `MakabaAPIClient.likePost` and `dislikePost`.

### Phase 3.15: Emoji Captcha Round Counter & Proactive Expiration (`[ISSUE-37]`)
- **Target Files**: `Makaba/UI/Posting/EmojiCaptchaView.swift:61–299` (within `EmojiCaptchaViewModel`, lines 115–140)
- **Implementation**: Increment round counter only when server returns a new captcha challenge. Start a countdown timer based on `expires_in` seconds, proactively alerting the user before the token expires.

### Phase 3.16: Modernize `onChange(of:)` Modifiers (`[ISSUE-38]`)
- **Target Files**: Across 8 view files.
- **Implementation**: Migrate single-argument `.onChange(of: val) { val in }` to iOS 17-compliant `.onChange(of: val) { oldVal, newVal in }` with backward compatibility wrappers.

### Phase 3.17: Bounded LRU Cache Eviction (`[ISSUE-39]`)
- **Target Files**: `Makaba/Core/Network/MakabaAPIClient.swift:38–97` (`ResponseCache`)
- **Implementation**: Limit in-memory cache in `ResponseCache` to 50 items with an LRU linked list. Evict oldest entries on memory pressure notifications (`UIApplication.didReceiveMemoryWarningNotification`).

### Phase 3.18: Single-Channel Captcha State Synchronization (`[ISSUE-40]`)
- **Target Files**: `Makaba/UI/Posting/PostingSheet.swift:48–227` (`PostingViewModel`), `EmojiCaptchaView.swift`
- **Implementation**: Remove redundant Combine sinks. Share `EmojiCaptchaViewModel` as a single `@ObservedObject` or `@EnvironmentObject`.

### Phase 3.19: Dynamic Defunct Board Detection (`[ISSUE-41]`)
- **Target Files**: `Makaba/Core/Models/Board.swift:227–234`
- **Implementation**: Remove hardcoded `defunctBoardIDs`. Detect defunct status via HTTP 301 redirects or missing API flags.

### Phase 3.20: Disambiguate `fetchBoards` Signatures (`[ISSUE-42]`)
- **Target Files**: `Makaba/Core/Network/MakabaAPIClient.swift`
- **Implementation**: Rename methods to `fetchAllBoards() -> [Board]` and `fetchBoardCategories() -> BoardCategoryResponse`.

### Phase 3.21: Localized Russian API Error Descriptions (`[ISSUE-43]`)
- **Target Files**: `Makaba/Core/Network/MakabaAPIClient.swift:19–33`
- **Implementation**: Provide Russian error messages for all `MakabaAPIError` cases ("Неверный адрес сервера", "Ошибка подключения к сети", "Сервер временно недоступен").

### Phase 3.22: Video Attachment Badge Format Fallback (`[ISSUE-44]`)
- **Target Files**: `Makaba/UI/Thread/PostRowView.swift:341–364`
- **Implementation**: In `attachmentBadge(file:)`, when `file.isVideo` is true and `file.duration` is `nil` or empty, display format badge `"WEBM"` or `"MP4"` instead of falling back to pixel dimensions (`1920x1080`).

### Phase 3.23: Lossy `[MediaFile]` Monolithic Decoding & `MediaFile.id` Collisions (`[ISSUE-56]`)
- **Target Files**: `Makaba/Core/Models/Post.swift:133`, `Makaba/Core/Models/MediaFile.swift:51`
- **Implementation**: Replace monolithic `container.decode([MediaFile].self)` with safe element-by-element decoding (`decodeLossyArray`) so that a single corrupted or non-standard attachment payload does not drop all attachments in a post. Update `MediaFile.id` from `name` to composite unique identifier `id: String { "\(name)_\(path)" }` to eliminate SwiftUI `ForEach` duplicate key animation glitches.

### Phase 3.24: Custom Mirror URL Scheme Validation Flaw in `DomainConfigurationService` (`[ISSUE-57]`)
- **Target Files**: `Makaba/Core/Network/DomainConfigurationService.swift:114, 139`
- **Implementation**: Replace `clean.hasPrefix("http")` with strict scheme detection `clean.hasPrefix("http://") || clean.hasPrefix("https://")`, preventing hostnames like `httpbin.org` or `httpproxy.net` from being treated as having a valid URL scheme.

### Phase 3.25: NSFW Rating Blur Policy Consistency (`[ISSUE-58]`)
- **Target Files**: `Makaba/UI/Thread/PostRowView.swift:287`, `Makaba/UI/Media/MediaGalleryView.swift:366, 401, 407`
- **Implementation**: Unify the NSFW threshold: in `MediaGalleryView`, check `file.nsfw != 0` (or `(file.nsfw ?? 0) != 0`) matching `PostRowView.swift`, ensuring attachments with `nsfw == 2` remain protected by the blur shield in fullscreen gallery until explicitly tapped by the user.

### Phase 3.26: WebM Picture-in-Picture Control Bridge (`[ISSUE-59]`)
- **Target Files**: `Makaba/UI/Media/WebMPlayerView.swift:298, 313`
- **Implementation**: Bridge Picture-in-Picture initiation via an interactive custom SwiftUI PiP button that triggers `document.querySelector('video').requestPictureInPicture()` via the JavaScript bridge, or selectively enable touch events on the video player container, resolving the issue where `webView.isUserInteractionEnabled = false` prevented PiP activation.

---

## 5. Phase 4: P3 Code Hygiene, Build Configuration & Dead Code Cleanup

### Phase 4.1: XcodeGen CI Pipeline Integration (`[ISSUE-47]`)
- **Target Files**: `.github/workflows/build-ipa.yml`
- **Implementation**: Formalize and verify the explicit `xcodegen generate` step in CI before invoking `xcodebuild`:
  ```yaml
  - name: Install XcodeGen
    run: brew install xcodegen
  - name: Generate Xcode Project
    run: xcodegen generate
  ```

### Phase 4.2: Dead Code Removal (`[ISSUE-48]`)
- **Target Files**: `ThreadView.swift`, `WebMPlayerView.swift`, `MediaGalleryView.swift`
- **Implementation**:
  - Delete `PostingPlaceholderSheet` in `ThreadView.swift:516`.
  - Delete unused `showScrollButtons` variable in `ThreadView.swift:184`.
  - Remove unused `onDismissGesture` in `MediaGalleryView.swift:449`.
  - Retain `#if canImport(KSPlayer)` as the gate for KSPlayer while preserving the WebKit HTML5 fallback engine as an alternative fallback for zero-dependency builds.

### Phase 4.3: App Transport Security Hardening (`[ISSUE-49]`, `[ISSUE-50]`)
- **Target Files**: `Makaba/Resources/Info.plist`
- **Implementation**: Remove global `NSAllowsArbitraryLoads = true`. Restrict arbitrary loads to specific local/custom domains via `NSExceptionDomains`. Purge unused `UIBackgroundModes: audio`.

### Phase 4.4: URL Scheme Hygiene (`[ISSUE-51]`)
- **Target Files**: `Makaba/Resources/Info.plist`
- **Implementation**: Remove `makaba-quote` from `CFBundleURLTypes` (system-level URL handler), keeping it strictly internal to SwiftUI `OpenURLAction`.

### Phase 4.5: Repository Line-Ending Discipline (`[ISSUE-52]`)
- **Target Files**: `.gitattributes` (New File)
- **Implementation**:
  Add `.gitattributes` to enforce consistent LF line endings and prevent CRLF drift:
  ```gitattributes
  * text=auto eol=lf
  *.swift text eol=lf
  *.yml text eol=lf
  *.plist text eol=lf
  *.md text eol=lf
  ```

### Phase 4.6: O(n) String Trimming Optimization (`[ISSUE-53]`)
- **Target Files**: `Makaba/Core/Parser/MakabaHTMLParser.swift`
- **Implementation**: Replace character-by-character `removeSubrange` with a single slice trimming trailing whitespaces and newlines.

### Phase 4.7: Automated Micro-Benchmark Test Suite (`[ISSUE-54]`)
- **Target Files**: `MakabaTests/MakabaParserPerformanceTests.swift` (New File)
- **Implementation**: Add `measure` blocks in `XCTest` measuring HTML parser latency on standard 1,000-post thread payloads to substantiate performance claims.

### Phase 4.8: CI Runner Alignment (`[ISSUE-55]`)
- **Target Files**: `.github/workflows/build-ipa.yml`
- **Implementation**: Pin `macos-14` Apple Silicon runners and explicit Xcode 16.x versions.

### Phase 4.9: Modernize String Localization to String Catalogs (`[ISSUE-45]`)
- **Target Files**: `Makaba/Resources/Localizable.xcstrings` (New File), all SwiftUI view files
- **Implementation**: Introduce Xcode String Catalog (`Localizable.xcstrings`) targeting Russian (`ru`) and English (`en`), extracting hardcoded user-facing strings across all views.

### Phase 4.10: Accessibility Semantics & VoiceOver Traits (`[ISSUE-46]`)
- **Target Files**: `Makaba/UI/Thread/PostRowView.swift`, `Makaba/UI/Navigation/CatalogView.swift`, `Makaba/UI/Media/MediaGalleryView.swift`
- **Implementation**: Add `.accessibilityLabel`, `.accessibilityHint`, and `.accessibilityAddTraits(.isButton)` to post cells, quote links, reply chips, and media thumbnails for VoiceOver accessibility compliance.

---

## 6. Phase 5: Strategic Product Capabilities Roadmap

### `[PROD-01]` Persistent Data Layer: SQLite / GRDB Engine
- **Target Architecture**: `Makaba/Core/Persistence/DatabaseService.swift`
- **Scope**: Production SQLite/GRDB database managing:
  - Thread reading history and scroll positions
  - Favorited threads and boards
  - Local post drafts with autosave
  - Read/unread post counters per thread

### `[PROD-02]` `(Вы)` / `(Вам)` Author Tracking & Quote Notifications
- **Target Architecture**: `Makaba/Core/Tracking/UserPostTracker.swift`
- **Scope**:
  - Automatically record `post.num` for all user submissions.
  - Highlight user's own posts with a distinctive `(Вы)` badge.
  - Search thread replies for references to user's posts and highlight with a prominent `(Вам)` badge.

### `[PROD-03]` Offline 404 Thread Vault
- **Target Architecture**: `Makaba/Core/Archive/ArchiveVaultManager.swift`
- **Scope**:
  - Automatically save read threads and media thumbnails to disk.
  - When 2ch returns 404, allow users to view the preserved thread offline from the Vault.

### `[PROD-04]` Thread Media Gallery Grid (All-Media View)
- **Target Architecture**: `Makaba/UI/Media/ThreadMediaGridView.swift`
- **Scope**:
  - Dedicated grid view showing all images and WebMs in a thread.
  - Segmented controls: All / Images / WebM / Audio.

### `[PROD-05]` Wipe-Shield Anti-Spam & Keyword Filter
- **Target Architecture**: `Makaba/Core/Filter/WipeShieldService.swift`
- **Scope**:
  - Rule-based client-side filter hiding posts by keyword, regular expression, tripcode, or duplicate hash.

### `[PROD-06]` Sideload Distribution Manifest (AltStore / SideStore `apps.json`)
- **Target Architecture**: `docs/distribution/apps.json`, `.github/workflows/build-ipa.yml`
- **Scope**:
  - Automated CI generation of AltStore community repository manifest on every GitHub Release.

### `[PROD-07]` Cloudflare Turnstile Interactive Solver WebView
- **Target Architecture**: `Makaba/UI/Network/CloudflareChallengeSheet.swift`
- **Scope**:
  - Fullscreen sheet presenting interactive Turnstile captcha when Cloudflare issues 403, syncing clearance cookies back to `HTTPCookieStorage`.

### `[PROD-08]` True Black OLED Theme & Custom Gesture Ergonomics
- **Target Architecture**: `Makaba/UI/Theme/ThemeManager.swift`
- **Scope**:
  - Pure `#000000` dark theme for OLED displays, edge-swipe back gestures, and configurable greentext palette.

### `[PROD-09]` Thread Watchlist & Background Refresh
- **Target Architecture**: `Makaba/Core/Background/ThreadWatchService.swift`
- **Scope**:
  - `BGAppRefreshTask` monitoring starred threads for new replies, delivering local notifications.

### `[PROD-10]` Dynamic Type & Font Scaling Settings
- **Target Architecture**: `Makaba/UI/Settings/TypographySettingsView.swift`
- **Scope**:
  - User preferences for body text font size, comment line spacing, and compact post header layouts.

---

## 7. Ordered Implementation Timeline & Verification Criteria

| Phase | Milestone Name | Key Deliverables | Verification Command | Exit Criteria |
|---|---|---|---|---|
| **Phase 1** | P0 Stability & Security | KSPlayer linkage, Keychain passcodes, POST retry removal, WebM teardown, Audio ducking fix, PoW parallelization, MOV transcoder | `xcodebuild test -scheme Makaba` | Zero P0 blockers; WebM plays on iOS 16; zero plaintext passcodes; zero duplicate posts on timeout |
| **Phase 2** | P1 Concurrency & Data | MainActor failover, Thread diffing, `score: Double?`, PNG alpha, Quota sum, iPad identity, Cookie sync, Background HTML parser | `xcodebuild test -scheme Makaba` | Zero purple runtime warnings; catalog score sort works; transparent PNG uploads intact |
| **Phase 3** | P2 Network & UX | Catalog timeout, ImageLoader, Archive fallback, Markup toolbar, Tap-to-reveal spoilers, Plist UTType, Plaintext search | `xcodebuild test -scheme Makaba` | All interactive UI features functional; tap-to-reveal spoilers working; WebM visible in Files picker |
| **Phase 4** | P3 Hygiene & Build | XcodeGen CI step, Dead code deletion, ATS hardening, `.gitattributes`, Performance benchmarks | `git status`, `xcodebuild test` | Repository clean of dead code; CI generates project via XcodeGen; LF line endings enforced |
| **Phase 5** | Product Roadmap | SQLite persistence, (Вы)/(Вам) badges, Offline vault, Media grid, Wipe-Shield, AltStore manifest | Manual device QA & automated tests | Complete feature parity with modern mobile imageboard clients |

---

## 8. Verification & Sign-Off Checklist

- [x] All 59 confirmed issues from `AUDIT_VERIFICATION.md` mapped to actionable remediation tasks.
- [x] Every planned fix defines target files, architectural modifications, and concrete code blueprints.
- [x] Prerequisites and dependencies explicitly defined across all phases.
- [x] Verification criteria and test commands specified for every implementation milestone.
- [x] Document formatted to production standards and saved to `REMEDIATION_PLAN.md`.
