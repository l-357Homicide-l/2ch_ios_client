# Makaba Engine API Reference (2ch.org)

**Target Host**: `https://2ch.org` (Dvach / Makaba Engine)  
**Platform Target**: Native iOS Client (Swift 5.9+, iOS 16.0+)  
**Document Status**: Authoritative Engineering Specification  

---

## 1. Executive Summary

The Makaba engine is the proprietary anonymous imageboard backend serving `2ch.org` (and mirror `2ch.hk`). This specification provides the complete reference for building an iOS networking client.

The API architecture is structured into four primary subsystems:
1. **Public Read Endpoints**: High-throughput JSON endpoints providing board catalogs, thread listings, board pagination, and individual thread trees.
2. **Media Distribution**: Static file routing separating full-resolution original assets (`/src/`) from normalized JPEG thumbnails (`/thumb/`).
3. **Security & Anti-Abuse Pipeline**: A two-stage gatekeeper combining a client-side SHA-512 Proof of Work (PoW) computation challenge with an interactive multi-step visual Emoji Captcha or Passcode bypass.
4. **Interactive Write Endpoints**: Multipart form-data endpoints (`/user/posting`) for thread creation, replying, and REST voting endpoints (`/api/like`, `/api/dislike`).

---

## 2. Global Endpoint Directory

| Endpoint | Method | Content-Type | Response Type | Description |
|---|---|---|---|---|
| `https://2ch.org/api/mobile/v2/boards` | `GET` | None | `application/json` | Enumerate all public boards, categories, limits, and features |
| `https://2ch.org/{board}/catalog.json` | `GET` | None | `application/json` | Complete board catalog with OP posts and statistics |
| `https://2ch.org/{board}/threads.json` | `GET` | None | `application/json` | Flat list of active threads with basic counters |
| `https://2ch.org/{board}/index.json` | `GET` | None | `application/json` | Page 0 index: threads with OP and preview replies |
| `https://2ch.org/{board}/{page}.json` | `GET` | None | `application/json` | Board page `{page}` (e.g. `1.json`, `2.json`) |
| `https://2ch.org/{board}/res/{thread_num}.json` | `GET` | None | `application/json` | Complete thread post tree, author info, and media |
| `https://2ch.org/arch/{board}/res/{thread_num}.json` | `GET` | None | `application/json` | Read-only archived thread history |
| `https://2ch.org/{board}/src/{thread_num}/{filename}` | `GET`, `HEAD` | None | `image/*`, `video/*` | Full-resolution media attachment |
| `https://2ch.org/{board}/thumb/{thread_num}/{filename}` | `GET`, `HEAD` | None | `image/jpeg` | Preview thumbnail (always `.jpg`) |
| `https://2ch.org/api/captcha/emoji/id` | `GET` | None | `application/json` | Acquire Captcha ID (JWE token) & SHA-512 PoW challenge |
| `https://2ch.org/api/captcha/emoji/show` | `GET` | None | `application/json` | Retrieve Emoji puzzle image and 8 button icons (Base64 PNG) |
| `https://2ch.org/api/captcha/emoji/click` | `POST` | `application/json` | `application/json` | Submit user emoji selection step |
| `https://2ch.org/user/posting?nc=1` | `POST` | `multipart/form-data` | `application/json` | Submit reply or create a new thread |
| `https://2ch.org/api/like` | `GET` | None | `application/json` | Upvote a post (`?board={board}&num={num}`) |
| `https://2ch.org/api/dislike` | `GET` | None | `application/json` | Downvote a post (`?board={board}&num={num}`) |
| `https://2ch.org/api/sticker/show/{id}` | `GET` | None | `application/json` | Sticker pack metadata |

---

## 3. Data Models & JSON Schemas

### 3.1 Board Model (`/api/mobile/v2/boards`)
The root endpoint returns a JSON array of board objects: `[ BoardObject, ... ]`.

```typescript
interface BoardObject {
  id: string;                  // Board directory code (e.g. "b", "vg", "ai", "mobi")
  name: string;                // Board display name (e.g. "Бред", "Компьютерные игры")
  category: string;            // Category name ("Разное", "Тематика", "Игры", etc.)
  bump_limit: number;          // Maximum posts before bump ceases (typically 500 or 1000)
  default_name: string;        // Fallback author name (e.g. "Аноним")
  enable_dices: boolean;       // Board supports dice rolling tags
  enable_flags: boolean;       // Board displays country/custom flags
  enable_icons: boolean;       // Board displays faction/subgroup icon selector
  enable_likes: boolean;       // Board permits likes/dislikes
  enable_names: boolean;       // Board permits custom author names
  enable_oekaki: boolean;      // Board permits drawing canvas tool
  enable_posting: boolean;     // Whether board is open for posting
  enable_sage: boolean;        // Whether sage is active on board
  enable_shield: boolean;      // Moderation shield protection badge enabled
  enable_subject: boolean;     // Whether thread subject input is displayed/allowed
  enable_thread_tags: boolean; // Whether thread tags are supported
  enable_trips: boolean;       // Whether tripcodes (name#trip) are supported
  file_types: string[];        // Allowed file extensions: ["jpg", "png", "gif", "webm", "mp4", "webp", "sticker"]
  info: string;                // HTML board description / header banner rules
  info_outer: string;          // Short summary / keywords
  max_comment: number;         // Max post comment length in bytes (typically 15000)
  max_files_size: number;      // Max total upload size in kilobytes (e.g. 20480 = 20MB, 40960 = 40MB)
  max_pages: number;           // Max pagination depth (e.g. 10 to 25)
  threads_per_page: number;    // Number of threads per page (e.g. 15 to 25)
  tags?: string[];             // Supported thread tags (e.g. ["ai", "sd", "news"])
  icons?: Array<{              // Only present when enable_icons === true
    id: number;
    name: string;
    url: string;
  }>;
}
```

### 3.2 Catalog Model (`/{board}/catalog.json`)

```typescript
interface CatalogResponse {
  board: BoardObject;
  filter: string;              // Typically "standart"
  advert_top_image?: string;
  advert_top_link?: string;
  advert_bottom_image?: string;
  advert_bottom_link?: string;
  board_banner_image?: string;
  board_banner_link?: string;
  threads: CatalogThreadItem[];
}

interface CatalogThreadItem {
  num: number;                 // Thread number (root OP post number)
  parent: number;              // Always 0 for OP posts
  board: string;               // Board ID (e.g. "b")
  subject: string;             // Thread title / subject line
  comment: string;             // Formatted HTML body of the OP post
  date: string;                // Date string formatted "DD/MM/YY DOW HH:MM:SS"
  timestamp: number;           // Unix timestamp (seconds) of thread creation
  lasthit: number;             // Unix timestamp (seconds) of the most recent post
  views: number;               // Cumulative view counter
  posts_count: number;         // Total number of posts currently in thread
  files_count: number;         // Total number of media attachments in thread
  banned: number;              // 0 or 1
  closed: number;              // 0 or 1 (1 if thread is locked)
  endless: number;             // 0 or 1 (endless bump thread)
  sticky: number;              // Sticky weight (0 = normal, >0 = pinned)
  op: number;                  // OP indicator (0 or 1)
  name: string;                // Poster name (if used)
  trip: string;                // Tripcode or mod badge (e.g. "!!%adm%!!")
  email: string;               // Email or sage
  tags: string;                // Thread tag
  files: MediaFileObject[];    // Array of attachments on the OP post
}
```

### 3.3 Thread Post Tree Model (`/{board}/res/{thread_num}.json`)

```typescript
interface ThreadResponse {
  board: BoardObject;
  current_thread: string | number;
  files_count: number;
  posts_count: number;
  max_num: number;             // Highest post ID currently in thread
  title: string;               // Thread title
  unique_posters: string;      // Number of unique posting IPs/fingerprints (e.g. "82")
  is_board: number;
  is_closed: number;
  is_index: number;
  threads: [
    {
      posts: PostObject[];
    }
  ];
}

interface PostObject {
  num: number;                 // Post ID (unique within board)
  number: number;              // 1-based sequential post index within thread (1 = OP)
  parent: number;              // 0 for OP post, or thread root number for replies
  banned: number;              // 0 or 1
  closed: number;              // 0 or 1
  date: string;                // Formatted date string
  timestamp: number;           // Unix timestamp in seconds
  name: string;                // Author display name
  trip: string;                // Tripcode / admin status
  email: string;               // Email or sage
  subject: string;             // Subject line
  comment: string;             // Raw HTML post content
  op: number;                  // 1 if poster is original thread creator, else 0
  sticky: number;              // Sticky level
  endless: number;             // 0 or 1
  tags: string;                // Tag string
  views?: number;              // View count (present on OP)
  lasthit?: number;            // Timestamp of last hit (present on OP)
  likes?: number;              // Upvote count (when likes enabled)
  dislikes?: number;           // Downvote count (when likes enabled)
  files: MediaFileObject[];    // Attached files
  icon?: string | number;      // Custom board icon id (e.g. on /po/, /vg/)
}
```

### 3.4 Media File Model (`files` array)

```typescript
interface MediaFileObject {
  displayname: string;         // User's original upload file name (e.g. "clip.webm")
  fullname: string;            // Upload file name with extension
  name: string;                // Server disk file name (e.g. "17940112291560329633.webm")
  path: string;                // Absolute URL path to full file (e.g. "/b/src/338026248/17940112291560329633.webm")
  thumbnail: string;           // Absolute URL path to thumbnail preview (e.g. "/b/thumb/338026248/17940112291560329633s.jpg")
  size: number;                // File size in KILOBYTES (integer)
  width: number;               // Full width in pixels
  height: number;              // Full height in pixels
  tn_width: number;            // Thumbnail width in pixels (max 250px)
  tn_height: number;           // Thumbnail height in pixels (max 250px)
  type: number;                // Numeric file type identifier (see enum below)
  duration?: string;           // Video duration string "HH:MM:SS" (e.g. "00:01:15")
  duration_secs?: number;      // Video duration integer seconds (e.g. 75)
  md5: string;                 // Hexadecimal MD5 hash of original file
  nsfw?: number;               // 0 or 1
  install?: string;            // Special handler flag
}
```

#### Media Type Numeric Enum (`file.type`)
| Value | Format / MIME | Extension | Player / Handler |
|---|---|---|---|
| `1` | `image/jpeg` | `.jpg`, `.jpeg` | Native image viewer |
| `2` | `image/png` | `.png` | Native image viewer |
| `4` | `image/gif` | `.gif` | Animated GIF viewer |
| `6` | `video/webm` | `.webm` | WebM video decoder (VP8/VP9 + Opus/Vorbis) |
| `7` | External Video | YouTube/Coub/Vimeo | Embedded web/external link |
| `9` | `image/webp` | `.webp` | WebP image viewer |
| `10` | `video/mp4` | `.mp4` | Native AVPlayer (`video/mp4`) |
| `100` | Sticker | Sticker Pack PNG | Custom sticker renderer |

**URL Resolution Invariants**:
- Full media URL: `https://2ch.org` + `file.path`
- Thumbnail URL: `https://2ch.org` + `file.thumbnail`
- Thumbnail previews are **always JPEGs** ending with `s.jpg`, regardless of whether the source is PNG, GIF, WebM, or MP4.

---

## 4. Captcha & Proof of Work (PoW) Protocol

Makaba enforces a two-tier verification challenge: an algorithmic Proof of Work computation followed by an interactive multi-step visual Emoji Captcha.

### Phase 1: Acquiring Challenge & PoW Solution

1. **Request**:
   `GET https://2ch.org/api/captcha/emoji/id?board={board}&thread={thread}`
   - Parameters:
     - `board`: string board identifier (e.g. `b`)
     - `thread`: integer thread number (e.g. `338026248` for reply, or `0` for new thread)
   - Headers: include `Cookie: passcode_auth=...` if user holds a 2ch Passcode.

2. **Response Structure**:
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

3. **Status Codes (`result`)**:
   - `result == 1`: Captcha required. Both PoW challenge and Emoji Captcha must be solved.
   - `result == 2`: **VIP Passcode Valid**. Captcha is waived! User can post immediately using `usercode` field.
   - `result == 3`: Captcha disabled on board/thread (`nocaptcha`).
   - `result == 0`: VIP verification failed (expired or invalid passcode).
   - `result == -1` or `result == 4`: Request timeout / flood limit. Cooldown enforced.
   - `warning`: String warning message (e.g. warning to poster).
   - `banned`: String ban reason and ban ID.

4. **Solving the SHA-512 Proof of Work (PoW)**:
   - Challenge object parameters:
     - `limit`: Maximum iterations (always `20000`).
     - `template`: Format string containing `%d` (e.g. `7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv`).
     - `hash`: Target 128-character lowercase hexadecimal SHA-512 string.
   - Nonce candidate: `template.replacingOccurrences(of: "%d", with: "\(i)")` for $0 \le i < limit$.
   - The discovered integer $i$ is stored to be submitted as `2ch_challenge` in the posting form.

---

### Phase 2: Emoji Captcha Visual Interaction

1. **Retrieve Visual Assets**:
   `GET https://2ch.org/api/captcha/emoji/show?id={id}`
   - Parameter `id`: The JWE token string from Phase 1 (`response.id`).
   - Response:
     ```json
     {
       "image": "<base64_encoded_png_prompt_image>",
       "keyboard": [
         "<base64_png_icon_0>",
         "<base64_png_icon_1>",
         "<base64_png_icon_2>",
         "<base64_png_icon_3>",
         "<base64_png_icon_4>",
         "<base64_png_icon_5>",
         "<base64_png_icon_6>",
         "<base64_png_icon_7>"
       ]
     }
     ```
   - `image`: PNG image instructing the user which emoji or symbols to match.
   - `keyboard`: Array of exactly 8 clickable emoji buttons (base64 PNG images).

2. **Submit User Click**:
   `POST https://2ch.org/api/captcha/emoji/click`
   - Content-Type: `application/json`
   - Body:
     ```json
     {
       "captchaTokenID": "<initial_token_id>",
       "emojiNumber": 3
     }
     ```
   - `emojiNumber`: 0-indexed integer corresponding to the user's selection from `keyboard` (0 to 7).

3. **Click Response**:
   - **Case A: Multi-step challenge continues**:
     ```json
     {
       "image": "<next_base64_prompt_image>",
       "keyboard": [ ... 8 base64 icons ... ]
     }
     ```
     The UI updates the prompt image and keyboard for the next selection.
   - **Case B: Captcha verification successful**:
     ```json
     {
       "success": "<verified_captcha_key_token>"
     }
     ```
     The returned `response.success` token is saved. It MUST be submitted in the posting form as `emoji_captcha_id`!
   - **Case C: Error / Failed**:
     HTTP 500 or response with error message. Captcha must be re-requested from Phase 1.

---

## 5. Posting Protocol (`/user/posting`)

### 5.1 Request Specification
- **URL**: `POST https://2ch.org/user/posting?nc=1`
- **Content-Type**: `multipart/form-data; boundary=...`

#### Form Fields Specification:

| Field Name | Type | Required | Description | Example / Values |
|---|---|---|---|---|
| `task` | `text` | Yes | Task identifier | Always `"post"` |
| `board` | `text` | Yes | Target board code | `"b"`, `"vg"`, `"ai"` |
| `thread` | `text` | Yes | Target thread ID | `"338026248"` (reply), `"0"` (new thread) |
| `comment` | `text` | Conditional | Post body text | UTF-8 text (max `max_comment` bytes). Required if no file attached. |
| `2ch_challenge` | `text` | Yes (if no VIP) | SHA-512 PoW integer solution | `"18847"` |
| `captcha_type` | `text` | Yes (if no VIP) | Selected captcha engine | `"emoji_captcha"` (or `"passcode"`, `"nocaptcha"`) |
| `emoji_captcha_id` | `text` | Yes (if no VIP) | Token from emoji click success | Token from `response.success` |
| `usercode` | `text` | No | Passcode / VIP token | Stored passcode string |
| `email` | `text` | No | Email or sage | `"sage"` |
| `sage` | `text` | No | Alternative sage flag | `"1"` |
| `subject` | `text` | Conditional | Thread title / post subject | Required on `/news/` for new threads; optional elsewhere |
| `name` | `text` | No | Author display name | Optional (on boards with `enable_names: true`) |
| `op_mark` | `text` | No | Post with OP badge | `"1"` |
| `tags` | `text` | Conditional | Thread tag | Required on `/vg/`, `/tv/` for new threads |
| `icon` | `text` | No | Selected icon ID | Required only if board enforces custom icon selection |
| `file[]` | `file` (binary) | Conditional | Attached file upload | Required when creating new thread on boards with file uploads enabled. Can be repeated for multiple files. |

---

### 5.2 Response Schemas

#### Success Responses (HTTP 200 OK)

1. **Replying to an existing thread**:
   ```json
   {
     "result": 1,
     "num": 338059123
   }
   ```
   - `result`: `1` indicates success.
   - `num`: The newly created post ID (integer).

2. **Creating a new thread**:
   ```json
   {
     "result": 1,
     "thread": 338059123
   }
   ```
   - `result`: `1` indicates success.
   - `thread`: The newly created thread ID (integer).

---

#### Error Responses (HTTP 200 OK or HTTP 500)

```json
{
  "result": 0,
  "error": {
    "code": -5,
    "message": "Капча невалидна."
  }
}
```

#### Known Error Code Reference:
| Code | Russian Message | English Translation | Root Cause / Resolution |
|---|---|---|---|
| `-2` | Доска не существует. | Board does not exist. | Invalid `board` field submitted. |
| `-3` | Тред закрыт. / Тред не существует. | Thread is closed or does not exist. | Posting into locked or pruned thread. |
| `-4` | Постинг слишком частый. | Posting too fast (flood limit). | Rate limit exceeded. Wait 15–30s. |
| `-5` | Капча невалидна. | Captcha is invalid. | Missing, expired, or invalid `emoji_captcha_id` or wrong PoW `2ch_challenge`. Refresh captcha. |
| `-6` | Вы заблокированы. | You are banned. | Client IP or network range is banned. |
| `-7` | Вы ничего не написали. | Post body is empty. | Both `comment` and `file[]` were omitted. |
| `-8` | Слишком длинное сообщение. | Comment too long. | Comment exceeded `max_comment` byte count. |
| `-9` | Ошибка загрузки файла. | File upload error. | File size exceeds `max_files_size` or format not in `file_types`. |
| `-10` | Ошибка загрузки файла: похожий файл уже есть. | Similar file already exists. | Duplicate file hash on board. |
| `-11` | Тип файла не поддерживается. | File type unsupported. | Format prohibited on board. |
| `-12` | Файл слишком большой. | File too large. | Exceeds board max file size. |
| `-13` | Слишком много файлов. | Too many files. | Max 4 files allowed per post. |
| `-20` | Лимит тредов превышен. | Board thread limit reached. | Board has reached maximum capacity. |
| `-21` | Пасскод не существует. | Passcode does not exist. | Stored passcode is invalid or expired. |
| `-22` | Превышен лимит запросов. | Request rate limit exceeded. | Exponential backoff required. |
| `666` | Внутренняя ошибка сервера. | Internal server error. | Malformed JWE token or database timeout. Retry after delay. |
| `667` | Не найдено. | Endpoint not found. | Deprecated endpoint invoked. |

---

## 6. Passcode (VIP) Subsystem

2ch.org provides a paid "Passcode" feature.
- **Acquisition**: User purchases a passcode on 2ch.org.
- **Storage**: Passcode string is stored in client Keychain / UserDefaults and transmitted in:
  1. Cookie: `passcode_auth=<token>`
  2. Form field: `usercode=<token>` on `/user/posting`
- **Verification Flow**:
  1. Client sends `GET /api/captcha/emoji/id?board={board}&thread={thread}` with `Cookie: passcode_auth=<token>`.
  2. If valid, server responds with `{"result": 2, "type": "passcode", "maxFiles": 4, "maxFilesSize": 40960}`.
  3. Client completely skips PoW calculation and Emoji Captcha UI!
  4. Client sets `captcha_type = "passcode"` and `usercode = <token>` in the multipart post payload.
  5. File upload size limit expands up to 40MB.

---

## 7. Network Policies, Caching & Performance Recommendations

1. **User-Agent Requirement**:
   Always send a custom browser or mobile client User-Agent:
   `User-Agent: 2ch-Browser/1.0 (iOS; CPU iPhone OS 17_5 like Mac OS X)`
2. **Accept Header**:
   `Accept: application/json, text/plain, */*`
3. **Caching Headers**:
   - Board catalogs and thread posts respond with Cloudflare `CF-Cache-Status` (`DYNAMIC` or `HIT`).
   - Media attachments (`/src/` and `/thumb/`) should be aggressively cached locally in disk cache using `URLCache` or Kingfisher.
4. **Incremental Thread Polling**:
   - For auto-refreshing an active thread, client fetches `GET /{board}/res/{thread_num}.json`.
   - Client tracks `max_num` (highest post ID seen).
   - Only posts where `post.num > previous_max_num` need to be appended and rendered.
   - Recommended polling interval: **15 seconds** when active, **30–60 seconds** when backgrounded or blurred.
