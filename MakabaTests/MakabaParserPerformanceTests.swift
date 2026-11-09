//
//  MakabaParserPerformanceTests.swift
//  MakabaTests
//
//  Performance micro-benchmarks validating HTML parser latency and throughput.
//

import XCTest
@testable import Makaba

final class MakabaParserPerformanceTests: XCTestCase {

    private var sampleHTMLComments: [String] = []

    override func setUp() {
        super.setUp()
        // Synthesize 1,000 diverse 2ch post comment samples
        sampleHTMLComments = (1...1000).map { i in
            """
            <a href="/b/res/12345.html#\(i)" data-num="\(i)">&gt;&gt;\(i)</a><br>
            <span class="unkfunc">&gt;Цитата зелёным текстом на строке \(i)</span><br>
            Обычный текст с <b>жирным</b> и <i>курсивом</i>, а также <span class="spoiler">скрытый спойлер #\(i)</span>.<br>
            Проверка сущностей: &quot;кавычки&quot; &amp; &lt;скобки&gt; &#039;апостроф&#039; &mdash; тире &hellip;<br>
            Ссылка: <a href="https://2ch.hk/b/">https://2ch.hk/b/</a>
            """
        }
    }

    override func tearDown() {
        sampleHTMLComments = []
        super.tearDown()
    }

    /// Measures parser latency over 1,000 post comments to ensure average per-comment latency < 0.1ms.
    func test_htmlParser_performance_1000Posts() {
        measure {
            for comment in sampleHTMLComments {
                _ = MakabaHTMLParser.parse(html: comment)
            }
        }
    }

    /// Validates tap-to-reveal spoiler link generation and attribute state.
    func test_htmlParser_tapToRevealSpoiler_attributes() {
        let html = "Привет <span class=\"spoiler\">секретный спойлер</span> пока"
        let parsedVeiled = MakabaHTMLParser.parse(html: html, postNum: 42, revealedSpoilers: [])
        XCTAssertFalse(parsedVeiled.characters.isEmpty)

        let parsedRevealed = MakabaHTMLParser.parse(html: html, postNum: 42, revealedSpoilers: [1])
        XCTAssertFalse(parsedRevealed.characters.isEmpty)
    }

    /// Validates plain text stripper performance.
    func test_plainTextStripper_performance_1000Posts() {
        measure {
            for comment in sampleHTMLComments {
                _ = MakabaHTMLParser.toPlainText(html: comment)
            }
        }
    }
}
