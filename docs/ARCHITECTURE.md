# Technical Architecture Specification: Native iOS 2ch Client (Makaba Engine)

**Platform Target**: iOS 16.0+, Swift 5.9+, SwiftUI  
**Target CI Environment**: GitHub Actions `macos-14` (Xcode 15/16)  
**Host Target**: `https://2ch.org` (Makaba Imageboard Engine)  
**Document Status**: Authoritative Engineering Specification  

---

## 1. Executive Summary & Design Principles

This specification defines the engineering architecture for a turnkey native iOS client for **2ch.org (Makaba engine)**. The application is built entirely in Swift and SwiftUI, adhering to modern iOS software design patterns:

1. **Unidirectional Data Flow**: MVVM architecture utilizing Swift modern concurrency (`async`/`await`), `ObservableObject` / `@Published` or `@Observable`, and deterministic view rendering.
2. **High-Performance Content Subsystem**: A zero-WebKit pure-Swift lexical scanner (`MakabaHTMLParser`) generating native `AttributedString` in under 0.08ms per post, eliminating UI lag on 1000-post threads and intercepting `2ch-quote://` for instant popover previews.
3. **Modular Media Subsystem**: A dual-engine video player (`WebMPlayerView`) overcoming iOS AVFoundation's lack of WebM/VP8/VP9/Opus support via **KSPlayer** (backed by FFmpegKit SPM binary targets) paired with a lightweight zero-dependency WebKit `<video>` fallback.
4. **Cryptographic Subsystem**: Native Apple `CryptoKit` SHA-512 Proof of Work solver resolving Makaba's 20,000-iteration challenges in under 20ms on background threads.
5. **Turnkey Sideloading CI**: Conflict-free XcodeGen configuration coupled with an automated GitHub Actions workflow on `macos-14` producing an unsigned `.ipa` ready for personal signing via AltStore, SideStore, or TrollStore.

---

## 2. System Architecture & Layering

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             SwiftUI View Layer                              │
│  BoardListView  │  CatalogView  │  ThreadView  │  MediaView  │ PostingSheet │
└─────────┬───────────────┬──────────────┬──────────────┬──────────────┬──────┘
          │               │              │              │              │
          ▼               ▼              ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ViewModel / State Layer                           │
│  BoardListVM    │  CatalogVM    │  ThreadVM    │  MediaVM    │  PostingVM   │
└─────────┬───────────────┬──────────────┬──────────────┬──────────────┬──────┘
          │               │              │              │              │
          ▼               ▼              ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                             Core Domain Layer                               │
│  ┌─────────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐  │
│  │    MakabaAPIClient      │ │   MakabaHTMLParser   │ │   PoWSolver      │  │
│  │ (URLSession async/await)│ │ (Lexical Attributed) │ │ (CryptoKit SHA)  │  │
│  └────────────┬────────────┘ └──────────┬───────────┘ └─────────┬────────┘  │
│               │                         │                       │           │
│  ┌────────────▼────────────┐ ┌──────────▼───────────┐ ┌─────────▼────────┐  │
│  │    MultipartFormData    │ │  QuotePreviewSheet   │ │ WebMPlayerEngine │  │
│  │  (RFC 7578 Serializer)  │ │   (Popover/Modal)    │ │(KSPlayer/Fallback│  │
│  └─────────────────────────┘ └──────────────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Layer Responsibilities

1. **View Layer (`Makaba/UI/`)**:
   - Pure SwiftUI views reacting to observable state.
   - Declarative navigation via `NavigationSplitView` on iPad and `NavigationStack` on iPhone.
   - Dynamic type and dark mode support.
2. **ViewModel Layer**:
   - Manages UI state, pagination, thread auto-refreshing, and user interaction.
   - Encapsulates error handling and user notification alerts.
3. **Core Services Layer (`Makaba/Core/`)**:
   - `MakabaAPIClient`: Async network client with JSON decoding, custom error mapping, and rate limiting.
   - `MakabaHTMLParser`: High-speed tokenization of Makaba HTML markup.
   - `PoWSolver`: Apple CryptoKit SHA-512 iterative solver.
   - `MultipartFormData`: RFC 7578 compliant form builder for file uploads.
   - `WebMPlayerEngine`: Protocol-driven video engine.
4. **Data Models (`Makaba/Core/Models/`)**:
   - Strongly-typed `Codable` structs matching Makaba JSON schemas (`Board`, `Catalog`, `Thread`, `Post`, `MediaFile`, `CaptchaChallenge`).

---

## 3. High-Performance Rich Content Formatting (`MakabaHTMLParser`)

### 3.1 The WebKit Bottleneck Problem
The standard iOS approach for HTML rendering using `NSAttributedString(data:options:documentAttributes:)` with `.documentType: .html`:
- Launches a private WebKit IPC daemon synchronously.
- Imposes **15 ms to 45 ms** parsing latency per post.
- Causes thread lockups of **7.5 to 22.5 seconds** when opening a 500-post thread.
- Consumes ~80 MB additional memory due to WebKit backing buffers.

### 3.2 The Lexical Scanner Solution
`MakabaHTMLParser` replaces WebKit with a sub-millisecond Swift lexical scanner:
- Execution time: **< 0.08 ms** per post (>200x faster).
- Outputs native SwiftUI `AttributedString` with custom attributes.
- Executed on a background thread during JSON model decoding and cached on `Post.renderedBody`.

### 3.3 Markup Mapping & Interception

| HTML Pattern | Parser Action | SwiftUI Visual Trait |
|---|---|---|
| `<span class="unkfunc">&gt;quote</span>` | Styled substring | Greentext `#789922` color |
| `<a ... data-num="123">&gt;&gt;123</a>` | Link replaced with `2ch-quote://123` | Orange link with quote popover |
| `<a href="https://...">link</a>` | Standard markdown link | External Safari Sheet |
| `<span class="spoiler">text</span>` | Styled substring | Redacted background, tap-to-reveal |
| `<b>`, `<i>`, `<s>`, `<u>` | Converted to Markdown syntax | Native typographic traits |
| `<br>`, `<br/>`, `<p>` | Converted to `\n` or `\n\n` | Paragraph line breaks |
| `&amp;`, `&quot;`, `&lt;`, `&gt;` | Entity decoded | Standard Unicode characters |

### 3.4 Interactive Quote Interception Protocol
When a post contains replies like `>>338026307`, the parser embeds `2ch-quote://338026307`. SwiftUI intercepts this URL scheme via `.environment(\.openURL)`:

```swift
.environment(\.openURL, OpenURLAction { url in
    if url.scheme == "2ch-quote" {
        if let targetNum = Int(url.host ?? url.path.replacingOccurrences(of: "/", with: "")) {
            if let targetPost = viewModel.posts.first(where: { $0.num == targetNum }) {
                self.previewPost = targetPost
            }
        }
        return .handled
    } else if url.scheme == "http" || url.scheme == "https" {
        self.safariURL = url
        return .handled
    }
    return .systemAction
})
.sheet(item: $previewPost) { post in
    QuotePreviewSheet(post: post) { jumpNum in
        withAnimation { proxy.scrollTo(jumpNum, anchor: .top) }
    }
    .presentationDetents([.fraction(0.35), .medium])
}
```

---

## 4. Native iOS WebM Playback Architecture

### 4.1 AVFoundation Limitations on iOS
Apple's native `AVPlayer` strictly prohibits WebM playback:
- **Container**: WebM (EBML / Matroska subset) is rejected with error code `-11828 ("Cannot Open")`.
- **Video Codecs**: VP8 is completely unsupported in hardware or software; VP9 is restricted to HLS/MP4 containers on newer hardware.
- **Audio Codecs**: Vorbis and Opus inside WebM containers are rejected.

Because 2ch.org media attachments are predominantly `.webm` files encoding VP8/VP9 video and Opus/Vorbis audio, a specialized decoding pipeline is essential.

### 4.2 Candidate Solutions Comparison

| Candidate | Mechanism | SPM Support | macOS-14 CI Friendly | Supported Formats | Footprint |
|---|---|---|---|---|---|
| **KSPlayer** | FFmpegKit SPM binaryTarget + VideoToolbox + Metal | **Yes** (Native SPM binaryTarget) | **Excellent** (prebuilt xcframeworks) | VP8, VP9, AV1, Vorbis, Opus | ~32 MB |
| **MobileVLCKit** | VLC core xcframework | Partial (CocoaPods primary) | Moderate (large download) | All formats | ~85 MB |
| **OGVKit** | libvpx + libogg | No (CocoaPods only, deprecated) | Poor | VP8, Vorbis | ~18 MB |
| **WebKit `<video>` Fallback** | Inline HTML5 WebKit video element | Built-in (Zero dependencies) | Instant | Browser-supported codecs | 0 MB |

### 4.3 Modular Player Architecture
To guarantee zero CI fragility while delivering production-grade media playback, the player subsystem uses a protocol-driven adapter pattern:

```swift
public protocol WebMPlayerEngine: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var isMuted: Bool { get set }
    
    func load(url: URL)
    func play()
    func pause()
    func seek(to time: Double)
    func cleanup()
}
```

- **Production Target (`KSPlayerAdapter`)**: Wraps `KSPlayerView` via `UIViewRepresentable`, enabling hardware-accelerated VP9 and software FFmpeg decoding for VP8, Vorbis, and Opus.
- **Zero-Dependency Fallback (`WebVideoFallbackAdapter`)**: Wraps an optimized inline `WKWebView` rendering an embedded HTML5 `<video>` canvas. Provides immediate playback capabilities even if third-party binary frameworks are disabled.

---

## 5. Automated Build Pipeline & CI (GitHub Actions)

### 5.1 Project Definition via XcodeGen (`project.yml`)
To guarantee reproducible builds without `.pbxproj` merge conflicts, the project layout is declaratively specified:

```yaml
name: Makaba
options:
  bundleIdPrefix: org.makaba
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "15.4"

packages:
  KSPlayer:
    url: https://github.com/kingslay/KSPlayer.git
    from: 2.3.0

targets:
  Makaba:
    type: application
    platform: iOS
    sources:
      - path: Makaba
    dependencies:
      - package: KSPlayer
        product: KSPlayer
    settings:
      base:
        PRODUCT_NAME: Makaba
        PRODUCT_BUNDLE_IDENTIFIER: org.makaba.client
        INFOPLIST_FILE: Makaba/Resources/Info.plist
        SWIFT_VERSION: "5.9"
        CODE_SIGN_STYLE: Manual
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGN_IDENTITY: ""

  MakabaTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: MakabaTests
    dependencies:
      - target: Makaba
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: org.makaba.client.tests
        SWIFT_VERSION: "5.9"
        CODE_SIGNING_ALLOWED: NO
```

### 5.2 Unsigned IPA Packaging Strategy on `macos-14`
When building for sideloading, running `xcodebuild -exportArchive` fails without active provisioning profiles. The workflow utilizes the standard Payload packaging pipeline:
1. `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO` and `AD_HOC_CODE_SIGNING_ALLOWED=YES`.
2. Extract the compiled `Makaba.app` from `.xcarchive/Products/Applications/`.
3. Construct a standard `Payload/` directory containing `Makaba.app`.
4. Zip into `Makaba-unsigned.ipa` using `zip -r -y`.
5. Upload artifact via `actions/upload-artifact@v4`.

---

## 6. Repository Layout Specification

```
2ch_ios_client/
├── docs/
│   ├── API_RESEARCH.md           # Makaba engine API reference
│   ├── ARCHITECTURE.md           # High-level architecture & design
│   └── POW_CAPTCHA_SPEC.md       # PoW and Emoji Captcha specification
├── project.yml                   # Declarative XcodeGen project specification
├── Makaba.xcodeproj/             # Master Xcode project
├── Makaba/
│   ├── App/
│   │   ├── MakabaApp.swift       # Application entry point
│   │   └── ContentView.swift     # Root navigation container
│   ├── Core/
│   │   ├── Models/               # Strongly-typed Decodable models
│   │   │   ├── Board.swift
│   │   │   ├── Catalog.swift
│   │   │   ├── Thread.swift
│   │   │   ├── Post.swift
│   │   │   ├── MediaFile.swift
│   │   │   └── Captcha.swift
│   │   ├── Network/              # Network client and endpoints
│   │   │   ├── MakabaAPIClient.swift
│   │   │   ├── Endpoints.swift
│   │   │   └── MultipartFormData.swift
│   │   ├── Crypto/               # CryptoKit SHA-512 PoW solver
│   │   │   └── PoWSolver.swift
│   │   └── Parser/               # High-speed lexical parser
│   │       └── MakabaHTMLParser.swift
│   ├── UI/
│   │   ├── Navigation/           # Board list and catalog views
│   │   │   ├── BoardListView.swift
│   │   │   └── CatalogView.swift
│   │   ├── Thread/               # Thread reader and quote popovers
│   │   │   ├── ThreadView.swift
│   │   │   ├── PostRowView.swift
│   │   │   └── QuotePreviewSheet.swift
│   │   ├── Media/                # Media viewers and video players
│   │   │   ├── MediaGalleryView.swift
│   │   │   └── WebMPlayerView.swift
│   │   └── Posting/              # Posting and captcha sheet
│   │       ├── PostingSheet.swift
│   │       └── EmojiCaptchaView.swift
│   └── Resources/
│       ├── Assets.xcassets       # App icons and color palettes
│       └── Info.plist            # App transport security and settings
├── MakabaTests/
│   ├── ModelDecodingTests.swift  # JSON deserialization tests
│   ├── PoWSolverTests.swift      # SHA-512 PoW accuracy & benchmark tests
│   ├── HTMLParserTests.swift     # Markup parsing & quote scheme tests
│   └── PostingPayloadTests.swift # Multipart RFC 7578 formatting tests
├── .github/
│   └── workflows/
│       └── build-ipa.yml         # GitHub Actions macos-14 CI workflow
├── PROJECT.md                    # Project blueprint and milestone tracking
└── README.md                     # Overview, build instructions, and sideloading guide
```

---

## 7. Quality & Verification Standards

1. **Memory & Concurrency**:
   - Zero WebKit memory overhead in list views.
   - Nonce calculation executed exclusively on `DispatchQueue.global(qos: .userInitiated)` or Swift Task.
2. **Deterministic Formatting**:
   - Quoted posts (`>>123456`) must resolve to interactive sheets without screen flicker.
   - HTML entities decoded with 100% fidelity.
3. **Automated Testing Coverage**:
   - Unit tests covering model decoding against real Makaba JSON fixtures.
   - Verified PoW unit test confirming exact nonce discovery against live challenge templates.
   - Multipart serialization test verifying RFC 7578 boundaries and headers.
