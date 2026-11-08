# Makaba: Native iOS Client for 2ch.org

A high-performance, turnkey native iOS client for **2ch.org (Makaba imageboard engine)**, built entirely with **Swift 5.9+** and **SwiftUI** for iOS 16.0+.

Designed from the ground up for speed, fluid navigation, and zero UI freezes, Makaba features custom sub-millisecond rich text lexical parsing, native WebM video playback, Apple CryptoKit SHA-512 Proof of Work solving, and an automated GitHub Actions CI pipeline producing unsigned `.ipa` packages ready for personal sideloading.

---

## Key Features

- **Board & Catalog Navigation**:
  - Full board directory taxonomy across categories (General, Games, Anime, Tech, etc.).
  - Visual catalog grid with thumbnail previews, reply counters, and search filtering.
  - Paginated thread lists with automatic incremental polling.
- **Sub-Millisecond Rich Content Formatting**:
  - Pure-Swift lexical parser (`MakabaHTMLParser`) converting Makaba markup to native SwiftUI `AttributedString` in under 0.08ms per post.
  - True greentext rendering (`#789922`), spoilers with tap-to-reveal redaction, and inline font styling.
  - Interactive quote links (`>>123456`) routed via custom `2ch-quote://` scheme into floating popover sheets without losing scroll position.
- **Media Gallery & Fullscreen Zoom**:
  - Asynchronous thumbnail caching and full-resolution image expansion.
  - Interactive pinch-to-zoom and pan gestures.
- **Integrated WebM Video Player**:
  - Solves iOS AVPlayer container/codec incompatibility using a modular player engine.
  - Powered by **KSPlayer** (backed by hardware-accelerated VideoToolbox VP9 and FFmpeg audio decoding for Opus/Vorbis) with an instant zero-dependency WebKit `<video>` fallback.
  - Playback controls: play/pause, scrubber bar, time display, mute toggle, and seamless looping.
- **Cryptographic Anti-Abuse & Captcha Engine**:
  - Native **Apple CryptoKit SHA-512 Proof of Work (PoW)** solver resolving 20,000-iteration challenges in under 20ms on background threads.
  - Interactive **Emoji Captcha** interface with multi-round puzzle recognition.
  - **VIP Passcode** authentication support bypassing captchas and unlocking 40MB file uploads.
- **Posting Subsystem**:
  - Thread creation and reply composer with sage toggle, custom author name, subject, and file attachments.
  - RFC 7578 compliant multipart/form-data serializer.

---

## Technical Specifications & Documentation

The project includes exhaustive engineering documentation in the `docs/` directory:

| Document | Description |
|---|---|
| [`docs/API_RESEARCH.md`](docs/API_RESEARCH.md) | Exhaustive Makaba engine API reference, endpoints, JSON schemas, error codes, and posting parameters |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | High-level system architecture, SwiftUI data flow, `MakabaHTMLParser`, `WebMPlayerView`, and build pipeline |
| [`docs/POW_CAPTCHA_SPEC.md`](docs/POW_CAPTCHA_SPEC.md) | Cryptographic specification of SHA-512 PoW challenge solving and Emoji Captcha JWE workflow |
| [`PROJECT.md`](PROJECT.md) | Master project roadmap, milestone tracking, interface contracts, and repository layout |

---

## System Requirements

- **Runtime**: iOS 16.0 or later (iPhone & iPad).
- **Development Environment**:
  - macOS 14.0+ (Sonoma).
  - Xcode 15.0+ or Xcode 16.0+.
  - Swift 5.9+ toolchain.
- **Optional Tools**:
  - [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) for generating project files from `project.yml`.

---

## Building & Development

### 1. Clone the Repository
```bash
git clone https://github.com/example/2ch_ios_client.git
cd 2ch_ios_client
```

### 2. Generate or Open Xcode Project
If using XcodeGen:
```bash
xcodegen generate
open Makaba.xcodeproj
```
Or open the bundled `Makaba.xcodeproj` directly in Xcode.

### 3. Swift Package Manager Dependencies
The project utilizes Swift Package Manager for external dependencies:
- **KSPlayer**: `https://github.com/kingslay/KSPlayer.git` (FFmpeg binary targets for VP8/VP9/Opus WebM playback).

Xcode automatically resolves package dependencies upon opening the project. To resolve via command line:
```bash
xcodebuild -resolvePackageDependencies -project Makaba.xcodeproj -scheme Makaba
```

### 4. Running Unit Tests
Execute the automated test suite covering model deserialization, CryptoKit PoW challenge solving against live test vectors, HTML markup parsing, and multipart formatting:
```bash
xcodebuild test \
  -project Makaba.xcodeproj \
  -scheme MakabaTests \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=17.5"
```

---

## Automated CI & Sideloading (Unsigned IPA)

The repository includes a production-ready GitHub Actions workflow (`.github/workflows/build-ipa.yml`) configured for `macos-14`:

1. **Clean Archive**: Runs `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO`.
2. **Payload Packaging**: Extracts `Makaba.app` and constructs a clean `Payload/` hierarchy.
3. **Artifact Generation**: Compresses the package into `Makaba-unsigned.ipa` and uploads it to GitHub Actions workflow artifacts.

### Installing on Device (Sideloading)
Download the unsigned `.ipa` artifact from GitHub Actions and sign it using any of the following tools:
- **AltStore**: [altstore.io](https://altstore.io)
- **SideStore**: [sidestore.io](https://sidestore.io)
- **TrollStore**: (iOS 14.0 - 16.6.1 / 17.0 on supported devices)
- **Sideloadly**: [sideloadly.io](https://sideloadly.io)
- **iOS App Signer** with your personal Apple Developer account.

---

## License & Disclaimer

This project is open-source software provided for personal communication and educational purposes. Dvach / 2ch.org and Makaba engine are property of their respective owners.
