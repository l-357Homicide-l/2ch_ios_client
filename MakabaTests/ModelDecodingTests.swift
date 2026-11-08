//
//  ModelDecodingTests.swift
//  MakabaTests
//
//  Automated unit test suite validating JSON deserialization, flexible type mapping,
//  and computed domain properties across all Makaba core models.
//

import XCTest
@testable import Makaba

final class ModelDecodingTests: XCTestCase {

    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - 1. Board & BoardCategory Decoding Tests

    func test_boardDecoding_withStandardPayload_decodesAllProperties() throws {
        let json = """
        {
            "id": "b",
            "name": "Бред",
            "category": "Разное",
            "bump_limit": 500,
            "default_name": "Аноним",
            "enable_dices": 0,
            "enable_flags": 0,
            "enable_icons": 1,
            "enable_likes": 1,
            "enable_names": 1,
            "enable_oekaki": 0,
            "enable_posting": 1,
            "enable_sage": 1,
            "enable_shield": 0,
            "enable_subject": 1,
            "enable_thread_tags": 0,
            "enable_trips": 1,
            "file_types": ["jpg", "png", "gif", "webm", "mp4"],
            "info": "Правила раздела /b/",
            "info_outer": "Главная доска",
            "max_comment": 15000,
            "max_files_size": 20480,
            "max_pages": 10,
            "threads_per_page": 20,
            "tags": ["b", "random"],
            "icons": [
                {
                    "id": 1,
                    "name": "Faction A",
                    "url": "/icons/faction_a.png"
                }
            ]
        }
        """.data(using: .utf8)!

        let board = try decoder.decode(Board.self, from: json)

        XCTAssertEqual(board.id, "b")
        XCTAssertEqual(board.name, "Бред")
        XCTAssertEqual(board.category, "Разное")
        XCTAssertEqual(board.bumpLimit, 500)
        XCTAssertEqual(board.defaultName, "Аноним")
        XCTAssertFalse(board.enableDices)
        XCTAssertFalse(board.enableFlags)
        XCTAssertTrue(board.enableIcons)
        XCTAssertTrue(board.enableLikes)
        XCTAssertTrue(board.enableNames)
        XCTAssertFalse(board.enableOekaki)
        XCTAssertTrue(board.enablePosting)
        XCTAssertTrue(board.enableSage)
        XCTAssertFalse(board.enableShield)
        XCTAssertTrue(board.enableSubject)
        XCTAssertFalse(board.enableThreadTags)
        XCTAssertTrue(board.enableTrips)
        XCTAssertEqual(board.fileTypes, ["jpg", "png", "gif", "webm", "mp4"])
        XCTAssertEqual(board.info, "Правила раздела /b/")
        XCTAssertEqual(board.infoOuter, "Главная доска")
        XCTAssertEqual(board.maxComment, 15000)
        XCTAssertEqual(board.maxFilesSize, 20480)
        XCTAssertEqual(board.maxPages, 10)
        XCTAssertEqual(board.threadsPerPage, 20)
        XCTAssertEqual(board.tags, ["b", "random"])

        XCTAssertEqual(board.icons?.count, 1)
        let icon = try XCTUnwrap(board.icons?.first)
        XCTAssertEqual(icon.id, 1)
        XCTAssertEqual(icon.name, "Faction A")
        XCTAssertEqual(icon.url, "/icons/faction_a.png")
        XCTAssertEqual(icon.iconURL?.absoluteString, "https://2ch.org/icons/faction_a.png")
    }

    func test_boardDecoding_flexibleBool_handlesAllRepresentations() throws {
        // Test Bools as true/false, ints 1/0, strings "1"/"0", strings "true"/"false"
        let json = """
        {
            "id": "vg",
            "name": "Видеоигры",
            "enable_dices": true,
            "enable_flags": false,
            "enable_icons": 1,
            "enable_likes": 0,
            "enable_names": "1",
            "enable_oekaki": "0",
            "enable_shield": "true",
            "enable_thread_tags": "false"
        }
        """.data(using: .utf8)!

        let board = try decoder.decode(Board.self, from: json)

        XCTAssertTrue(board.enableDices)
        XCTAssertFalse(board.enableFlags)
        XCTAssertTrue(board.enableIcons)
        XCTAssertFalse(board.enableLikes)
        XCTAssertTrue(board.enableNames)
        XCTAssertFalse(board.enableOekaki)
        XCTAssertTrue(board.enableShield)
        XCTAssertFalse(board.enableThreadTags)
        // Check defaults for missing keys
        XCTAssertTrue(board.enablePosting)
        XCTAssertTrue(board.enableSage)
        XCTAssertTrue(board.enableSubject)
        XCTAssertFalse(board.enableTrips)
    }

    func test_boardIcon_iconURL_resolvesBothRelativeAndAbsoluteURLs() {
        let relativeIcon = BoardIcon(id: 10, name: "Rel", url: "icons/badge.png")
        XCTAssertEqual(relativeIcon.iconURL?.absoluteString, "https://2ch.org/icons/badge.png")

        let leadingSlashIcon = BoardIcon(id: 11, name: "Slash", url: "/icons/badge2.png")
        XCTAssertEqual(leadingSlashIcon.iconURL?.absoluteString, "https://2ch.org/icons/badge2.png")

        let absoluteIcon = BoardIcon(id: 12, name: "Abs", url: "https://static.2ch.org/icon.png")
        XCTAssertEqual(absoluteIcon.iconURL?.absoluteString, "https://static.2ch.org/icon.png")
    }

    func test_boardCategory_groupByCategory_preservesCanonicalOrder() {
        let boards = [
            Board(id: "vg", name: "Видеоигры", category: "Игры", bumpLimit: 500),
            Board(id: "b", name: "Бред", category: "Разное", bumpLimit: 500),
            Board(id: "a", name: "Аниме", category: "Японская культура", bumpLimit: 500),
            Board(id: "mobi", name: "Мобильные", category: "Техника и софт", bumpLimit: 500),
            Board(id: "soc", name: "Общение", category: "Разное", bumpLimit: 500),
            Board(id: "custom", name: "Своя доска", category: "Неизвестная", bumpLimit: 500)
        ]

        let categories = BoardCategory.groupByCategory(boards)

        // Categories must follow standard order first: Разное, Техника и софт, Игры, Японская культура, etc.
        let categoryNames = categories.map { $0.name }
        XCTAssertEqual(categoryNames.first, "Разное")
        XCTAssertTrue(categoryNames.contains("Техника и софт"))
        XCTAssertTrue(categoryNames.contains("Игры"))
        XCTAssertTrue(categoryNames.contains("Японская культура"))
        XCTAssertEqual(categoryNames.last, "Неизвестная")

        // Within "Разное", boards must be sorted alphabetically by id: "b", then "soc"
        let raznoe = categories.first(where: { $0.name == "Разное" })
        XCTAssertEqual(raznoe?.boards.map { $0.id }, ["b", "soc"])
    }

    // MARK: - 2. Catalog Response & CatalogThreadItem Tests

    func test_catalogResponse_decoding_populatesAllMetadataAndThreads() throws {
        let json = """
        {
            "filter": "standart",
            "advert_top_image": "/adv/top.png",
            "advert_top_link": "https://adv.example.com",
            "threads": [
                {
                    "num": 338026248,
                    "parent": 0,
                    "board": "b",
                    "subject": "Тестовый тред в каталоге",
                    "comment": "Привет 2ch.org!",
                    "date": "08/11/26 Вск 11:00:00",
                    "timestamp": 1794135600,
                    "lasthit": 1794136000,
                    "views": 150,
                    "posts_count": 42,
                    "files_count": 5,
                    "banned": 0,
                    "closed": 0,
                    "endless": 1,
                    "sticky": 2,
                    "op": 1,
                    "name": "Аноним",
                    "trip": "!testTrip",
                    "score": 10,
                    "files": [
                        {
                            "name": "preview.jpg",
                            "path": "/b/src/338026248/preview.jpg",
                            "thumbnail": "/b/thumb/338026248/preview.jpg",
                            "size": 512,
                            "width": 1920,
                            "height": 1080,
                            "tn_width": 200,
                            "tn_height": 112,
                            "type": 1
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let catalog = try decoder.decode(CatalogResponse.self, from: json)

        XCTAssertEqual(catalog.filter, "standart")
        XCTAssertEqual(catalog.advertTopImage, "/adv/top.png")
        XCTAssertEqual(catalog.advertTopLink, "https://adv.example.com")
        XCTAssertEqual(catalog.threads.count, 1)

        let item = catalog.threads[0]
        XCTAssertEqual(item.id, 338026248)
        XCTAssertEqual(item.num, 338026248)
        XCTAssertEqual(item.board, "b")
        XCTAssertEqual(item.subject, "Тестовый тред в каталоге")
        XCTAssertEqual(item.comment, "Привет 2ch.org!")
        XCTAssertEqual(item.postsCount, 42)
        XCTAssertEqual(item.filesCount, 5)
        XCTAssertEqual(item.views, 150)
        XCTAssertEqual(item.trip, "!testTrip")
        XCTAssertEqual(item.score, 10)

        // Computed properties
        XCTAssertTrue(item.isPinned) // sticky == 2 > 0
        XCTAssertFalse(item.isLocked) // closed == 0
        XCTAssertTrue(item.isEndless) // endless == 1 != 0
        XCTAssertEqual(item.displayTitle, "Тестовый тред в каталоге")
        XCTAssertNotNil(item.primaryFile)
        XCTAssertEqual(item.primaryFile?.name, "preview.jpg")
    }

    func test_catalogThreadItem_displayTitle_fallbackToThreadNumWhenEmpty() {
        let itemEmptySubject = CatalogThreadItem(num: 123456, subject: "   ", comment: "Some comment")
        XCTAssertEqual(itemEmptySubject.displayTitle, "Тред #123456")

        let itemWithSubject = CatalogThreadItem(num: 123456, subject: "Название треда")
        XCTAssertEqual(itemWithSubject.displayTitle, "Название треда")
    }

    // MARK: - 3. Thread Response & ThreadListItem Tests

    func test_threadResponse_decoding_withStringCurrentThreadAndUniquePosters() throws {
        let json = """
        {
            "current_thread": "338026248",
            "files_count": 3,
            "posts_count": 10,
            "max_num": 338026257,
            "title": "Заголовок треда",
            "unique_posters": "7",
            "is_board": 0,
            "is_closed": 0,
            "is_index": 0,
            "threads": [
                {
                    "posts": [
                        {
                            "num": 338026248,
                            "parent": 0,
                            "date": "08/11/26 12:00:00",
                            "timestamp": 1794135600,
                            "name": "Аноним",
                            "comment": "OP пост",
                            "op": 1,
                            "files": []
                        },
                        {
                            "num": 338026249,
                            "parent": 338026248,
                            "date": "08/11/26 12:01:00",
                            "timestamp": 1794135660,
                            "name": "Аноним",
                            "comment": "Ответ >>338026248",
                            "op": 0,
                            "files": []
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let threadResponse = try decoder.decode(ThreadResponse.self, from: json)

        XCTAssertEqual(threadResponse.currentThread, "338026248")
        XCTAssertEqual(threadResponse.uniquePosters, "7")
        XCTAssertEqual(threadResponse.filesCount, 3)
        XCTAssertEqual(threadResponse.postsCount, 10)
        XCTAssertEqual(threadResponse.title, "Заголовок треда")
        XCTAssertEqual(threadResponse.threadNum, 338026248)
        XCTAssertFalse(threadResponse.isLocked)

        XCTAssertEqual(threadResponse.posts.count, 2)
        XCTAssertEqual(threadResponse.opPost?.num, 338026248)
        XCTAssertTrue(threadResponse.opPost?.isOP ?? false)
    }

    func test_threadResponse_decoding_withIntegerCurrentThreadAndUniquePosters() throws {
        // Some Makaba engines output current_thread and unique_posters as raw integers
        let json = """
        {
            "current_thread": 999888,
            "files_count": 1,
            "posts_count": 2,
            "unique_posters": 2,
            "is_closed": 1,
            "threads": [
                {
                    "posts": [
                        {
                            "num": 999888,
                            "parent": 0,
                            "comment": "Закрытый тред",
                            "op": 1,
                            "closed": 1,
                            "files": []
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let threadResponse = try decoder.decode(ThreadResponse.self, from: json)

        XCTAssertEqual(threadResponse.currentThread, "999888")
        XCTAssertEqual(threadResponse.uniquePosters, "2")
        XCTAssertEqual(threadResponse.threadNum, 999888)
        XCTAssertTrue(threadResponse.isLocked)
    }

    func test_threadListItem_decoding_populatesAllFields() throws {
        let json = """
        {
            "num": 100200,
            "subject": "Легкий список",
            "comment": "Превью комментария",
            "timestamp": 1794135600,
            "lasthit": 1794136000,
            "posts_count": 12,
            "files_count": 4,
            "views": 85,
            "score": 3
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ThreadListItem.self, from: json)

        XCTAssertEqual(item.id, 100200)
        XCTAssertEqual(item.num, 100200)
        XCTAssertEqual(item.subject, "Легкий список")
        XCTAssertEqual(item.comment, "Превью комментария")
        XCTAssertEqual(item.timestamp, 1794135600)
        XCTAssertEqual(item.lasthit, 1794136000)
        XCTAssertEqual(item.postsCount, 12)
        XCTAssertEqual(item.filesCount, 4)
        XCTAssertEqual(item.views, 85)
        XCTAssertEqual(item.score, 3)
    }

    // MARK: - 4. Post Model Tests

    func test_postDecoding_withAllPropertiesAndComputedLogic() throws {
        let json = """
        {
            "num": 338026307,
            "number": 5,
            "parent": 338026248,
            "banned": 1,
            "closed": 0,
            "date": "08/11/26 12:30:00",
            "timestamp": 1794137400,
            "name": "Модератор",
            "trip": "!adminTrip",
            "email": "sage",
            "subject": "Важное сообщение",
            "comment": "Ответ на <a href=\"/b/res/338026248.html#338026248\" data-num=\"338026248\">&gt;&gt;338026248</a> и &gt;&gt;338026249 с комментарием.",
            "op": 0,
            "likes": 20,
            "dislikes": 5,
            "icon": "42",
            "files": [
                {
                    "name": "image.png",
                    "path": "/b/src/338026248/image.png",
                    "thumbnail": "/b/thumb/338026248/image.png",
                    "size": 1024,
                    "width": 800,
                    "height": 600,
                    "tn_width": 200,
                    "tn_height": 150,
                    "type": 2
                }
            ]
        }
        """.data(using: .utf8)!

        let post = try decoder.decode(Post.self, from: json)

        XCTAssertEqual(post.id, 338026307)
        XCTAssertEqual(post.num, 338026307)
        XCTAssertEqual(post.number, 5)
        XCTAssertEqual(post.parent, 338026248)
        XCTAssertEqual(post.name, "Модератор")
        XCTAssertEqual(post.trip, "!adminTrip")
        XCTAssertEqual(post.subject, "Важное сообщение")
        XCTAssertEqual(post.displaySubject, "Важное сообщение")
        XCTAssertEqual(post.icon, "42")

        // Computed logic assertions
        XCTAssertFalse(post.isOP) // op == 0, parent != 0, number != 1
        XCTAssertTrue(post.isSage) // email == "sage"
        XCTAssertTrue(post.isBanned) // banned == 1
        XCTAssertEqual(post.score, 15) // 20 - 5 = 15
        XCTAssertTrue(post.hasFiles)
        XCTAssertEqual(post.files.count, 1)

        // Referenced post quote numbers extraction
        XCTAssertEqual(post.referencedPostNumbers, [338026248, 338026249])
    }

    func test_post_isOP_boundaryConditions() {
        // Condition 1: op == 1
        let opPost = Post(num: 1, comment: "OP", op: 1)
        XCTAssertTrue(opPost.isOP)

        // Condition 2: parent == 0
        let parentZeroPost = Post(num: 2, parent: 0, comment: "Parent Zero")
        XCTAssertTrue(parentZeroPost.isOP)

        // Condition 3: number == 1
        let numberOnePost = Post(num: 3, number: 1, comment: "Number One")
        XCTAssertTrue(numberOnePost.isOP)

        // Condition 4: Regular reply
        let replyPost = Post(num: 4, number: 2, parent: 1, comment: "Reply", op: 0)
        XCTAssertFalse(replyPost.isOP)
    }

    func test_post_isSage_caseInsensitiveAndSubstrings() {
        let sageLower = Post(num: 1, email: "sage", comment: "")
        XCTAssertTrue(sageLower.isSage)

        let sageUpper = Post(num: 2, email: "SAGE", comment: "")
        XCTAssertTrue(sageUpper.isSage)

        let sageCombined = Post(num: 3, email: "mailto:user@domain.com?subject=sage", comment: "")
        XCTAssertTrue(sageCombined.isSage)

        let regularMail = Post(num: 4, email: "user@domain.com", comment: "")
        XCTAssertFalse(regularMail.isSage)

        let nilMail = Post(num: 5, email: nil, comment: "")
        XCTAssertFalse(nilMail.isSage)
    }

    func test_post_iconFlexibleDecoding_handlesIntegerIcon() throws {
        let json = """
        {
            "num": 100,
            "comment": "Icon as integer",
            "icon": 7
        }
        """.data(using: .utf8)!

        let post = try decoder.decode(Post.self, from: json)
        XCTAssertEqual(post.icon, "7")
    }

    // MARK: - 5. MediaFile & MediaType Tests

    func test_mediaType_rawValuesAndMimeTypes() {
        XCTAssertEqual(MediaType.jpeg.rawValue, 1)
        XCTAssertEqual(MediaType.png.rawValue, 2)
        XCTAssertEqual(MediaType.gif.rawValue, 4)
        XCTAssertEqual(MediaType.webm.rawValue, 6)
        XCTAssertEqual(MediaType.externalVideo.rawValue, 7)
        XCTAssertEqual(MediaType.webp.rawValue, 9)
        XCTAssertEqual(MediaType.mp4.rawValue, 10)
        XCTAssertEqual(MediaType.sticker.rawValue, 100)
        XCTAssertEqual(MediaType.unknown.rawValue, -1)

        XCTAssertEqual(MediaType.jpeg.mimeType, "image/jpeg")
        XCTAssertEqual(MediaType.png.mimeType, "image/png")
        XCTAssertEqual(MediaType.gif.mimeType, "image/gif")
        XCTAssertEqual(MediaType.webm.mimeType, "video/webm")
        XCTAssertEqual(MediaType.mp4.mimeType, "video/mp4")
        XCTAssertEqual(MediaType.webp.mimeType, "image/webp")
        XCTAssertEqual(MediaType.sticker.mimeType, "image/png")
        XCTAssertEqual(MediaType.unknown.mimeType, "application/octet-stream")
    }

    func test_mediaType_unknownFallbackOnUnrecognizedCode() throws {
        let json = "9999".data(using: .utf8)!
        let type = try decoder.decode(MediaType.self, from: json)
        XCTAssertEqual(type, .unknown)
    }

    func test_mediaFile_propertiesAndAspectRatios() {
        let videoFile = MediaFile(
            name: "sample.webm",
            path: "/b/src/100/sample.webm",
            thumbnail: "/b/thumb/100/sample.jpg",
            size: 2048,
            width: 1920,
            height: 1080,
            tnWidth: 320,
            tnHeight: 180,
            type: .webm,
            duration: "00:00:15",
            durationSecs: 15
        )

        XCTAssertEqual(videoFile.id, "sample.webm")
        XCTAssertTrue(videoFile.isVideo)
        XCTAssertFalse(videoFile.isImage)
        XCTAssertEqual(videoFile.fullURL?.absoluteString, "https://2ch.org/b/src/100/sample.webm")
        XCTAssertEqual(videoFile.thumbnailURL?.absoluteString, "https://2ch.org/b/thumb/100/sample.jpg")
        XCTAssertEqual(videoFile.formattedSize, "2.0 MB")
        XCTAssertEqual(videoFile.aspectRatio, 1920.0 / 1080.0, accuracy: 0.001)
        XCTAssertEqual(videoFile.thumbnailAspectRatio, 320.0 / 180.0, accuracy: 0.001)
        XCTAssertEqual(videoFile.durationSecs, 15)

        let smallImage = MediaFile(
            name: "tiny.png",
            path: "https://external.2ch.org/tiny.png",
            thumbnail: "/thumb/tiny.jpg",
            size: 500,
            width: 400,
            height: 300,
            tnWidth: 200,
            tnHeight: 150,
            type: .png
        )

        XCTAssertFalse(smallImage.isVideo)
        XCTAssertTrue(smallImage.isImage)
        XCTAssertEqual(smallImage.fullURL?.absoluteString, "https://external.2ch.org/tiny.png")
        XCTAssertEqual(smallImage.formattedSize, "500 KB")
    }

    // MARK: - 6. Captcha & PoW Models Tests

    func test_captchaChallengeResponse_statusAndBooleans() throws {
        // 1. Required captcha with PoW challenge
        let requiredJson = """
        {
            "result": 1,
            "type": "emoji",
            "input": "emoji",
            "id": "jwe_token_sample",
            "challenge": {
                "hash": "4014d34ffe01240df12aede0650bf7f1c35fdd2be915b8cd44f06922411095a30f764053ddee008be1e2b54750ba36997acfba96d0453d114043eb615cc5be98",
                "limit": 20000,
                "template": "7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv"
            },
            "maxFiles": 4,
            "maxFilesSize": 20480
        }
        """.data(using: .utf8)!

        let challenge = try decoder.decode(CaptchaChallenge.self, from: requiredJson)

        XCTAssertEqual(challenge.result, 1)
        XCTAssertEqual(challenge.status, .required)
        XCTAssertTrue(challenge.isVerificationRequired)
        XCTAssertFalse(challenge.isVIPBypass)
        XCTAssertFalse(challenge.isCaptchaDisabled)
        XCTAssertEqual(challenge.id, "jwe_token_sample")
        XCTAssertEqual(challenge.challenge?.limit, 20000)
        XCTAssertEqual(challenge.challenge?.template, "7d648FfGgpLIoJrF%dPKXqiENWI2m2AMVv")

        // 2. VIP bypass (result == 2)
        let vipChallenge = CaptchaChallenge(result: 2)
        XCTAssertEqual(vipChallenge.status, .vip)
        XCTAssertTrue(vipChallenge.isVIPBypass)
        XCTAssertFalse(vipChallenge.isVerificationRequired)

        // 3. Captcha disabled (result == 3)
        let disabledChallenge = CaptchaChallenge(result: 3)
        XCTAssertEqual(disabledChallenge.status, .disabled)
        XCTAssertTrue(disabledChallenge.isCaptchaDisabled)

        // 4. Rate-limit timeout (result == 4 or -1)
        let timeoutChallenge = CaptchaChallenge(result: 4)
        XCTAssertEqual(timeoutChallenge.status, .timeout)

        // 5. Banned user
        let bannedChallenge = CaptchaChallenge(result: 1, banned: "IP заблокирован")
        XCTAssertEqual(bannedChallenge.status, .banned)
    }

    func test_captchaShowResponse_decodesBase64Images() throws {
        let sampleBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA="
        let json = """
        {
            "image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA=",
            "keyboard": [
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA=",
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAA="
            ]
        }
        """.data(using: .utf8)!

        let show = try decoder.decode(CaptchaImages.self, from: json)

        XCTAssertEqual(show.image, sampleBase64)
        XCTAssertEqual(show.keyboard.count, 2)
        XCTAssertNotNil(show.imageData)
        XCTAssertEqual(show.keyboardData.count, 2)
    }

    func test_captchaClickResponse_intermediateVsTerminal() throws {
        // Intermediate round with next puzzle
        let intermediateJson = """
        {
            "image": "base64prompt",
            "keyboard": ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8"]
        }
        """.data(using: .utf8)!

        let intermediate = try decoder.decode(CaptchaClickResult.self, from: intermediateJson)
        XCTAssertFalse(intermediate.isSuccess)
        XCTAssertTrue(intermediate.hasMoreRounds)
        XCTAssertNil(intermediate.verifiedToken)

        // Terminal success
        let successJson = """
        {
            "success": "verified_jwe_success_token"
        }
        """.data(using: .utf8)!

        let successResult = try decoder.decode(CaptchaClickResult.self, from: successJson)
        XCTAssertTrue(successResult.isSuccess)
        XCTAssertFalse(successResult.hasMoreRounds)
        XCTAssertEqual(successResult.verifiedToken, "verified_jwe_success_token")
    }

    // MARK: - 7. Posting Response Tests

    func test_postingResponse_successPayload() throws {
        let json = """
        {
            "result": 1,
            "num": 338026249,
            "thread": 338026248
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(PostResult.self, from: json)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.num, 338026249)
        XCTAssertEqual(result.thread, 338026248)
        XCTAssertEqual(result.targetID, 338026249)
        XCTAssertNil(result.errorMessage)
    }

    func test_postingResponse_errorPayload() throws {
        let json = """
        {
            "result": 0,
            "error": {
                "code": -5,
                "message": "Капча невалидна."
            }
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(PostResult.self, from: json)

        XCTAssertFalse(result.isSuccess)
        XCTAssertNil(result.targetID)
        XCTAssertEqual(result.error?.code, -5)
        XCTAssertEqual(result.errorMessage, "Капча невалидна.")
    }
}
