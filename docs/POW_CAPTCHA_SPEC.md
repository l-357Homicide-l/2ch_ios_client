# Makaba Engine Captcha & Proof of Work (PoW) Specification

**Target Platform**: Native iOS Client (Swift 5.9+, iOS 16.0+, CryptoKit)  
**Host Target**: `https://2ch.org` / `https://2ch.hk` (Makaba Imageboard Engine)  
**Document Status**: Authoritative Engineering Specification  

---

## 1. Executive Summary & Security Model

To mitigate automated spam, flood attacks, and unauthorized bots, the Makaba engine enforces a multi-tier cryptographic and visual verification pipeline:
1. **SHA-512 Proof of Work (PoW) Challenge**: A deterministic cryptographic challenge delivered as a string template containing `%d`, a 128-character lowercase hexadecimal SHA-512 digest, and an upper iteration bound (typically 20,000). The client must compute SHA-512 hashes across nonces $i \in [0, 20000)$ until finding the matching pre-image.
2. **Stateless JWE Session Lifecycle**: The captcha session is identified by a compact JSON Web Encryption (`JWE`) token encoding an encrypted Protocol Buffers (`application/protobuf`) payload encrypted via AES-256-GCM (`A256GCM`).
3. **Emoji Captcha Visual Challenge**: An interactive puzzle where the client fetches a composite challenge image and an 8-icon keyboard, requiring the user to tap matching icons in one or more rounds.
4. **Multipart Post Submission Binding**: Verification parameters are bound into `POST /user/posting?nc=1` via fields `captcha_type=emoji_captcha`, `emoji_captcha_id=<verified_token>`, and `2ch_challenge=<pow_nonce>`.
5. **Passcode (VIP) Bypass**: Authenticated users holding a valid 2ch Passcode bypass both PoW and Emoji Captcha challenges entirely.

---

## 2. Captcha Challenge Acquisition Protocol

### 2.1 Endpoint Specification
- **URL**: `GET https://2ch.org/api/captcha/emoji/id`
- **Query Parameters**:
  - `board` (string, optional/recommended): Target board directory (e.g., `b`, `vg`, `mobi`).
  - `thread` (integer, optional): Target thread ID. Pass `0` or omit when creating a new thread.
- **Headers**:
  - `User-Agent`: Custom client identifier (e.g. `2ch-Browser/1.0 (iOS; CPU iPhone OS 17_5 like Mac OS X)`).
  - `Cookie`: May supply `passcode_auth=<token>` if VIP passcode is configured.

### 2.2 Response Schema
When verification is required, the server responds with HTTP 200:

```json
{
  "result": 1,
  "type": "emoji",
  "input": "emoji",
  "id": "eyJhbGciOiJkaXIiLCJjdHkiOiJhcHBsaWNhdGlvbi9wcm90b2J1ZiIsImVuYyI6IkEyNTZHQ00iLCJraWQiOiJ2NCIsInR5cCI6IkpXRSJ9..k1YLYHfFsG6mr81N.ROHH9EkMnAPtb9FVaz4xo4kUnaMHZV2VkOYYGjPCwiczaTI.6YunUGWhAa1FLODpZGVmRQ",
  "challenge": {
    "hash": "4014d34ffe01240df12aede0650bf7f1c35fdd2be915b8cd44f06922411095a30f764053ddee008be1e2b54750ba36997acfba96d0453d114043eb615cc5be98",
    "limit": 20000,
    "template": "7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv"
  }
}
```

#### Field Semantics:
- `result` (integer): Verification requirement status (see Status Codes Table).
- `type` (string): Captcha mechanism identifier (`"emoji"`).
- `input` (string): UI input classification (`"emoji"`).
- `id` (string): Compact 5-part JWE token (`header..iv.ciphertext.tag`). Header confirms direct encryption (`"alg":"dir"`), protobuf content (`"cty":"application/protobuf"`), AES-256-GCM cipher (`"enc":"A256GCM"`), and key identifier (`"kid":"v4"`).
- `challenge` (object): PoW parameters:
  - `hash` (string): 128-character lowercase hexadecimal target SHA-512 digest.
  - `limit` (integer): Maximum iteration count (typically `20000`).
  - `template` (string): Format string containing exactly one `%d` token.

### 2.3 Status Codes (`result`)
| Code | Enum | Semantic Meaning | Client Workflow |
|---|---|---|---|
| `1` | `SUCCESS` | Captcha required; challenge delivered | Solve PoW in background, request `/emoji/show`, render UI |
| `2` | `VIP` | Passcode validated (`passcode_auth`) | Bypass captcha; set `captcha_type=passcode`; skip PoW |
| `0` | `VIPFAIL` | Invalid or expired passcode | Clear passcode cookie; fallback to standard captcha flow |
| `3` | `DISABLED` | Captcha disabled on board (`nocaptcha`) | Post directly with `captcha_type=nocaptcha` |
| `-1`, `4` | `TIMEOUT` | Captcha flood rate-limited | Start 180-second cooldown timer |
| Non-null `banned` | `BANNED` | Poster IP/subnet is banned | Display ban notification and ban ID |
| Non-null `warning` | `WARNING` | Moderation warning | Display warning text to user |

---

## 3. SHA-512 Proof of Work (PoW) Cryptographic Specification

### 3.1 Mathematical Definition
Makaba's PoW is a bounded pre-image search over a finite integer space.
Given:
- `template`: A template string containing a single `%d` marker.
- `target_hash`: A 64-byte SHA-512 digest represented as a 128-character lowercase hex string.
- `limit`: An upper search bound (typically 20,000).

Find the integer nonce $i \in [0, \text{limit})$ satisfying:
$$\text{SHA-512}(\text{replace}(template, \text{"\%d"}, \text{str}(i))) == target\_hash$$

### 3.2 Invariants & Mechanics
1. **String Encoding**: Candidate strings must be encoded as UTF-8 bytes before hashing. Because the template and ASCII decimal digits are pure ASCII, byte-level ASCII encoding is identical to UTF-8.
2. **Integer Formatting**: Nonce $i$ is converted to a base-10 decimal string without leading zeros (`0`, `1`, `2`, ..., `19999`).
3. **Deterministic Solvability**: The Makaba server constructs the challenge by picking a random integer $N < limit$, computing $H = \text{SHA-512}(\text{replace}(template, \text{"\%d"}, N))$, and setting `hash = H`. Therefore, exactly one integer in $[0, limit)$ matches.
4. **Performance Benchmark**: In native Swift utilizing Apple's `CryptoKit` (`SHA512.hash(data:)`), searching 20,000 candidates takes between **10 ms and 18 ms** on modern Apple Silicon (A15/A16/A17/M-series).
5. **Form Field Parameter**: The solved integer nonce is submitted as a multipart text field named `2ch_challenge` with the string representation of $i$ (e.g. `"18847"`).

### 3.3 Verified Test Vectors

#### Vector 1 (Live Production Sample A)
- **Template**: `7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv`
- **Target Hash**: `4014d34ffe01240df12aede0650bf7f1c35fdd2be915b8cd44f06922411095a30f764053ddee008be1e2b54750ba36997acfba96d0453d114043eb615cc5be98`
- **Expected Solution Nonce**: `18847`
- **Verification Candidate**: `7d648FfGgpLIoJrF18847PKXqiENWI2m2AMVv`

#### Vector 2 (Live Production Sample B)
- **Template**: `qWIxksPn9V2oRLk5%d6grw3pvMHinm3uFf`
- **Target Hash**: `b73c8af810b9cfcd266cae6d2c140308b3d23c0addd807386cf161d06c535ee07b6f0f1368bac9b991817e8e7bc004b560fcaad75be269959c41540ee291a7eb`
- **Expected Solution Nonce**: `8214`
- **Verification Candidate**: `qWIxksPn9V2oRLk582146grw3pvMHinm3uFf`

#### Vector 3 (Live Production Sample C)
- **Template**: `bFZchwAOHvAealh9%dq11tvQUk5MFSFxaD`
- **Target Hash**: `ed241cab9a1eff97e47e8d18f22f380bf02c58b39b5f7cc3e858de28b2556edc8e11304d0bfe7c900cac9cc112324a58e69e2226c22dc7ff1cedd5ecfb91945e`
- **Expected Solution Nonce**: `17949`
- **Verification Candidate**: `bFZchwAOHvAealh917949q11tvQUk5MFSFxaD`

### 3.4 Production Swift CryptoKit Implementation

```swift
import Foundation
import CryptoKit

public enum PoWError: Error, LocalizedError {
    case invalidTemplate
    case limitExceeded(Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            return "Challenge template missing '%d' substitution marker."
        case .limitExceeded(let limit):
            return "Exceeded maximum iteration limit of \(limit) without hash match."
        }
    }
}

public struct PoWResult: Equatable {
    public let nonce: Int
    public let hash: String
    public let durationMs: Double
}

public final class PoWSolver {
    /// Solves the Makaba SHA-512 Proof of Work challenge.
    /// - Parameters:
    ///   - template: Format string containing '%d'.
    ///   - targetHash: 128-character lowercase hexadecimal string.
    ///   - limit: Maximum iterations to probe (default 20,000).
    /// - Returns: A `PoWResult` containing the nonce and timing.
    public static func solve(template: String, targetHash: String, limit: Int = 20000) throws -> PoWResult {
        guard template.contains("%d") else {
            throw PoWError.invalidTemplate
        }
        
        let parts = template.components(separatedBy: "%d")
        guard parts.count == 2 else {
            throw PoWError.invalidTemplate
        }
        let prefix = parts[0]
        let suffix = parts[1]
        let target = targetHash.lowercased()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for nonce in 0..<limit {
            let candidate = "\(prefix)\(nonce)\(suffix)"
            guard let data = candidate.data(using: .utf8) else { continue }
            
            let digest = SHA512.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            
            if hex == target {
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                return PoWResult(nonce: nonce, hash: hex, durationMs: durationMs)
            }
        }
        
        throw PoWError.limitExceeded(limit)
    }
}
```

---

## 4. Emoji Captcha Interactive Selection Workflow

### 4.1 State Transition Diagram

```
                 [GET /api/captcha/emoji/id]
                             │
                             ▼
                 ┌───────────────────────┐
                 │ result == 1           │
                 │ Receive: id, challenge│
                 └───────────┬───────────┘
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   [Solve SHA-512 PoW]            [GET /api/captcha/emoji/show?id={id}]
   (Concurrent Background Task)              │
   Produces: 2ch_challenge                   ▼
            │                     ┌───────────────────────────────┐
            │                     │ Receive: image, keyboard[0..7]│
            │                     │ Render visual puzzle & icons  │
            │                     └───────────────┬───────────────┘
            │                                     │
            │                     ┌───────────────┴───────────────┐
            │                     ▼                               │
            │             User taps emoji (index i)               │
            │                     │                               │
            │                     ▼                               │
            │       [POST /api/captcha/emoji/click]               │
            │       Body: {"captchaTokenID": id, "emojiNumber": i}│
            │                     │                               │
            │                     ▼                               │
            │              Server Response:                       │
            │              /             \                        │
            │      (image + keyboard)   (success: token)          │
            │            /                 │                      │
            │           ▼                  ▼                      │
            │      Next Step Round   Captcha Solved!              │
            │      (Update UI)       Save token:                  │
            │      Loop back         -> emoji_captcha_id          │
            │                              │                      │
            └──────────────┬───────────────┘                      │
                           ▼                                      │
              [POST /user/posting?nc=1] ◄─────────────────────────┘
              Form Payload:
              - 2ch_challenge: "<nonce>"
              - captcha_type: "emoji_captcha"
              - emoji_captcha_id: "<success_token>"
```

### 4.2 Step-by-Step API Interaction

#### Step 1: Request Visual Challenge Assets
- **URL**: `GET https://2ch.org/api/captcha/emoji/show?id={id}`
- **Parameter**: `id` = the JWE token string acquired from `/api/captcha/emoji/id`.
- **Response**:
  ```json
  {
    "image": "iVBORw0KGgoAAAANSUhEUgAAASw...",
    "keyboard": [
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA...",
      "iVBORw0KGgoAAAANSUhEUgAAADIA..."
    ]
  }
  ```
- **Display Semantics**:
  - `image`: Base64 PNG challenge prompt showing target emoji symbols.
  - `keyboard`: Array of exactly 8 Base64 PNG buttons. The user taps icons present in the prompt image.

#### Step 2: Submit Emoji Selection
- **URL**: `POST https://2ch.org/api/captcha/emoji/click`
- **Content-Type**: `application/json`
- **Request Body**:
  ```json
  {
    "captchaTokenID": "eyJhbGciOiJkaXIiLCJjdHkiOiJhcHBsaWNhdGlvbi9wcm90b2J1Zi...",
    "emojiNumber": 3
  }
  ```
  - `captchaTokenID`: The original JWE token string.
  - `emojiNumber`: 0-indexed integer corresponding to the selected icon button (`0` to `7`).

#### Step 3: Handle Click Response
The response takes one of two shapes:
1. **Intermediate Round** (further selections required):
   ```json
   {
     "image": "<new_base64_PNG>",
     "keyboard": ["<base64_0>", ..., "<base64_7>"]
   }
   ```
   The client updates the prompt image and button array for the next round.
2. **Terminal Verification Success**:
   ```json
   {
     "success": "eyJhbGciOiJkaXIiLCJjdHkiOiJhcHBsaWNhdGlvbi9wcm90b2J1Zi..."
   }
   ```
   The `success` string contains the verified submission token. It must be stored and passed as `emoji_captcha_id` to `/user/posting`.

---

## 5. Post Submission Binding

When dispatching the multipart form data to `POST https://2ch.org/user/posting?nc=1`:

```http
POST /user/posting?nc=1 HTTP/1.1
Host: 2ch.org
User-Agent: 2ch-Browser/1.0 (iOS; CPU iPhone OS 17_5 like Mac OS X)
Content-Type: multipart/form-data; boundary=Boundary-7MA4YWxKOm1ZCeIV

--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="task"

post
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="board"

b
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="thread"

338026248
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="comment"

Test reply content
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="captcha_type"

emoji_captcha
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="emoji_captcha_id"

eyJhbGciOiJkaXIiLCJjdHkiOiJhcHBsaWNhdGlvbi9wcm90b2J1Zi...
--Boundary-7MA4YWxKOm1ZCeIV
Content-Disposition: form-data; name="2ch_challenge"

18847
--Boundary-7MA4YWxKOm1ZCeIV--
```

---

## 6. Error Handling, Expiration Timers & Edge Cases

### 6.1 Lifecycle Timers
- **Captcha Session TTL**: **300 seconds** (5 minutes). If the challenge is not solved within 300 seconds, the server rejects the token with error `-5` (`Капча невалидна`).
- **Cooldown Timeout**: **180 seconds** (3 minutes). Enforced when server returns `result: -1` or `result: 4`. The client UI must display a countdown timer.
- **HTTP Timeout**: **30 seconds** network request timeout.

### 6.2 Edge Cases & Resilience Rules
1. **Invalid JWE Token on `/emoji/show`**: Returns HTTP 404. Client must catch 404, discard the state, and restart with `/emoji/id`.
2. **Invalid Emoji Click**: If an incorrect emoji is clicked or index is out of bounds, server resets the puzzle sequence by returning a refreshed `image` and `keyboard`.
3. **PoW Limit Exceeded**: If the candidate space is exhausted without a match (theoretically impossible unless network corrupted template), throw `PoWError.limitExceeded` and request a fresh challenge.
4. **VIP Passcode Expiration**: If `result == 0` is returned from `/emoji/id`, clear stored passcode credentials and transition smoothly to the standard Emoji Captcha interface.
