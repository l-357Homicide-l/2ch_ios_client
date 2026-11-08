# Project: Makaba Native iOS Client (2ch.org)

## Architecture
- **Language & UI**: Swift 5.9+ / SwiftUI (iOS 16.0+ minimum deployment target).
- **Network Layer**: `URLSession` async/await client with `JSONDecoder`, custom error mapping, rate limiting, and RFC 7578 multipart/form-data encoder.
- **Cryptographic Subsystem**: Apple `CryptoKit` SHA-512 engine solving 2ch.org PoW challenges up to 20,000 iterations in <20ms on background threads.
- **Media Subsystem**:
  - Images: Standard `AsyncImage` / `Kingfisher` with thumbnail preview caching and full-resolution interactive zoom viewer.
  - WebM Videos: Modular `WebMPlayerView` wrapping `KSPlayer` (SPM binaryTarget with VideoToolbox hardware acceleration for VP9 and FFmpeg audio decoding for Opus/Vorbis) with zero-dependency WebKit `<video>` fallback.
- **Content Subsystem**: `MakabaHTMLParser` — high-performance pure-Swift lexical scanner transforming Makaba markup (greentext `.unkfunc`, spoilers, quotes `>>123456`) into native `AttributedString` with `2ch-quote://` URL interception presenting popover quote preview sheets.
- **Build & CI Pipeline**:
  - Build System: Clean Xcode project structure / XcodeGen `project.yml`.
  - CI Workflow: `.github/workflows/build-ipa.yml` targeting `macos-14`, executing `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO`, packaging `Payload/`, and creating unsigned `.ipa` uploaded as a build artifact for manual on-device signing.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---|---|---|---|
| 1 | API & Architecture Reports | Markdown reports detailing endpoints, schemas, PoW, WebM, and architecture | M1 | R1 |
| 2 | Makaba Core Data Models | Decodable models for boards, catalog, thread list, posts, files, captcha | M2 | R2, R5 |
| 3 | Network Client Service | Async/await URLSession client covering all 2ch.org API endpoints | M2 | R2 |
| 4 | SHA-512 PoW Solver Engine | CryptoKit solver resolving template `%d` candidates under limit | M2 | R3, R5 |
| 5 | Board Navigation & Catalog UI | SwiftUI Views for board taxonomy, catalog grid, and thread lists | M3 | R2 |
| 6 | Thread View & Post Renderer | SwiftUI thread reader with post metadata, badges, and avatars | M3 | R2 |
| 7 | Makaba Rich Text & Quotes | High-performance HTML parser, greentext, quote previews (`QuotePreviewSheet`) | M3 | R2 |
| 8 | Media Gallery & Fullscreen Zoom | Image previews, high-res expansion, gesture zooming | M3 | R2 |
| 9 | WebM Player Integration | Modular video player with audio, seek bar, play/pause controls, loop mode | M4 | R2 |
| 10 | Emoji Captcha Verification UI | 3-endpoint captcha lifecycle (`/emoji/id` -> `/emoji/show` -> `/emoji/click`) | M5 | R3 |
| 11 | Posting Interface | Reply and new thread sheet, sage option, file attachment, multipart submission | M5 | R3 |
| 12 | Xcode Project Configuration | Deterministic Xcode project / project.yml ready for personal signing | M6 | R4 |
| 13 | GitHub Actions Unsigned IPA CI | `macos-14` workflow building unsigned `.ipa` artifact uploaded to Actions | M6 | R4 |
| 14 | Automated Unit Test Suite | XCTest suite for models, JSON decoding, PoW solver, posting builder | M7 | R5 |
| 15 | Forensic Integrity Audit | Systematic audit verifying genuine logic, clean build, zero cheating | M7 | Audit |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| M1 | API & Architecture Reports | Comprehensive research reports in `docs/` | none | COMPLETED |
| M2 | Core Models, Network & PoW | Swift Decodable models, 2ch API client, CryptoKit PoW solver | M1 | PLANNED |
| M3 | SwiftUI Views & Rich Formatting | Board list, Catalog, Thread view, MakabaHTMLParser, quote popups | M2 | PLANNED |
| M4 | WebM Player Integration | Modular WebM player (KSPlayer / VideoToolbox / fallback) | M3 | PLANNED |
| M5 | Posting & Emoji Captcha Flow | Captcha acquisition, puzzle UI, posting sheet, multipart `/user/posting` | M2, M3 | PLANNED |
| M6 | Xcode Setup & GitHub Actions CI | Xcode project, `.github/workflows/build-ipa.yml` on `macos-14` | M2, M3, M4, M5 | PLANNED |
| M7 | Test Suite & Final Audit | XCTest unit tests, verification, and forensic integrity audit | M1-M6 | PLANNED |

---

## Interface Contracts

### NetworkClient ↔ UI Views
- `func fetchBoards() async throws -> [BoardCategory]`
- `func fetchCatalog(board: String) async throws -> CatalogResponse`
- `func fetchThread(board: String, threadNum: Int) async throws -> ThreadResponse`
- `func fetchCaptcha(board: String, thread: Int) async throws -> CaptchaChallenge`
- `func fetchCaptchaImages(id: String) async throws -> CaptchaImages`
- `func submitCaptchaClick(tokenID: String, emojiNumber: Int) async throws -> CaptchaClickResult`
- `func submitPost(payload: PostPayload) async throws -> PostResult`

### PoWSolver ↔ NetworkClient / Posting
- `struct PoWResult: Equatable { let nonce: Int; let hash: String; let durationMs: Double }`
- `func solve(template: String, targetHash: String, limit: Int) throws -> PoWResult`

### MakabaHTMLParser ↔ PostView
- `func parse(html: String) -> AttributedString`
- Handles `.unkfunc` (greentext `#789922`), `.spoiler`, `<a href="..." data-num="...">` -> `2ch-quote://{post_num}`
- Environment `openURL` intercepts `2ch-quote://` to show `QuotePreviewSheet(post: Post)`

### WebMPlayer ↔ MediaView
- `struct WebMPlayerView: View`
- Parameters: `url: URL`, `autoPlay: Bool`, `isLooping: Bool`
- Plays video + audio with controls (play/pause, scrubber, mute/volume, fullscreen).

---

## Code Layout
```
2ch_ios_client/
├── docs/
│   ├── API_RESEARCH.md
│   ├── ARCHITECTURE.md
│   └── POW_CAPTCHA_SPEC.md
├── Makaba/
│   ├── App/
│   │   ├── MakabaApp.swift
│   │   └── ContentView.swift
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── Board.swift
│   │   │   ├── Catalog.swift
│   │   │   ├── Thread.swift
│   │   │   ├── Post.swift
│   │   │   ├── MediaFile.swift
│   │   │   └── Captcha.swift
│   │   ├── Network/
│   │   │   ├── MakabaAPIClient.swift
│   │   │   ├── Endpoints.swift
│   │   │   └── MultipartFormData.swift
│   │   ├── Crypto/
│   │   │   └── PoWSolver.swift
│   │   └── Parser/
│   │       └── MakabaHTMLParser.swift
│   ├── UI/
│   │   ├── Navigation/
│   │   │   ├── BoardListView.swift
│   │   │   └── CatalogView.swift
│   │   ├── Thread/
│   │   │   ├── ThreadView.swift
│   │   │   ├── PostRowView.swift
│   │   │   └── QuotePreviewSheet.swift
│   │   ├── Media/
│   │   │   ├── MediaGalleryView.swift
│   │   │   └── WebMPlayerView.swift
│   │   └── Posting/
│   │       ├── PostingSheet.swift
│   │       └── EmojiCaptchaView.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── MakabaTests/
│   ├── ModelDecodingTests.swift
│   ├── PoWSolverTests.swift
│   ├── HTMLParserTests.swift
│   └── PostingPayloadTests.swift
├── project.yml
├── Makaba.xcodeproj/
├── .github/
│   └── workflows/
│       └── build-ipa.yml
├── PROJECT.md
└── README.md
```
