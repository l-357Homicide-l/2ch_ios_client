//
//  HTMLParserTests.swift
//  MakabaTests
//
//  Automated unit test suite validating the pure-Swift MakabaHTMLParser:
//  lexical scanning, greentext styling, quote link extraction, entity collision immunity,
//  comment filtering, scheme whitelisting, and inline typographic attributes.
//

import XCTest
import SwiftUI
@testable import Makaba

final class HTMLParserTests: XCTestCase {

    // MARK: - 1. Greentext Styling Tests

    func test_parse_greentext_appliesGreentextColor() {
        let html = "<span class=\"unkfunc\">&gt;цитируемый текст</span>"
        let attr = MakabaHTMLParser.parse(html: html)

        let plainString = String(attr.characters)
        XCTAssertEqual(plainString, ">цитируемый текст")

        // Inspect attributed runs
        var foundGreentext = false
        for run in attr.runs {
            if run.foregroundColor == MakabaHTMLParser.greentextColor {
                foundGreentext = true
            }
        }
        XCTAssertTrue(foundGreentext, "Run must have greentext foregroundColor #789922")
    }

    // MARK: - 2. Quote Link Parsing & Interception Scheme

    func test_parse_quoteLink_withDataNum_generates2chQuoteScheme() {
        let html = "<a href=\"/b/res/338026248.html#338026248\" data-num=\"338026248\">&gt;&gt;338026248</a>"
        let attr = MakabaHTMLParser.parse(html: html)

        XCTAssertEqual(String(attr.characters), ">>338026248")

        var quoteLinkFound = false
        for run in attr.runs {
            if let link = run.link {
                XCTAssertEqual(link.scheme, "2ch-quote")
                XCTAssertEqual(link.host, "338026248")
                quoteLinkFound = true
            }
        }
        XCTAssertTrue(quoteLinkFound, "Quote link must be transformed to 2ch-quote://338026248")
    }

    func test_parse_quoteLink_fallbackToAnchorInHref_whenDataNumAbsent() {
        let html = "<a href=\"/vg/res/12345.html#67890\">&gt;&gt;67890</a>"
        let attr = MakabaHTMLParser.parse(html: html)

        XCTAssertEqual(String(attr.characters), ">>67890")

        var quoteLinkFound = false
        for run in attr.runs {
            if let link = run.link, link.absoluteString == "2ch-quote://67890" {
                quoteLinkFound = true
            }
        }
        XCTAssertTrue(quoteLinkFound, "Anchor in href must fallback to 2ch-quote://67890")
    }

    // MARK: - 3. Entity Collision Immunity Tests

    func test_entityImmunity_apostropheDoesNotTriggerQuoteLink() {
        // &#39; is apostrophe (') and MUST NOT be parsed as post #39
        let html = "It&#39;s a great day &amp; rock &#39;n&#39; roll!"
        let attr = MakabaHTMLParser.parse(html: html)

        let plain = String(attr.characters)
        XCTAssertEqual(plain, "It's a great day & rock 'n' roll!")

        // Ensure no run has a link pointing to 2ch-quote://39
        for run in attr.runs {
            if let link = run.link {
                XCTAssertNotEqual(link.absoluteString, "2ch-quote://39")
            }
        }

        // Verify quote extraction logic also ignores &#39;
        let quoteNumbers = MakabaHTMLParser.extractQuoteNumbers(html: html)
        XCTAssertTrue(quoteNumbers.isEmpty, "Quote numbers must not contain 39 from &#39;")
    }

    func test_entityImmunity_hexColorCodesDoNotTriggerQuotes() {
        let html = "Color is #123456 and not a quote"
        let quoteNumbers = MakabaHTMLParser.extractQuoteNumbers(html: html)
        XCTAssertTrue(quoteNumbers.isEmpty, "Hex color #123456 must not be parsed as quote")
    }

    func test_htmlEntityDecoding_resolvesStandardEntities() {
        let raw = "&quot;Hello&quot; &amp; &lt;World&gt; &apos;test&#39; &#x27; &#65; &nbsp;"
        let decoded = MakabaHTMLParser.decodeHTMLEntities(raw)
        XCTAssertEqual(decoded, "\"Hello\" & <World> 'test' ' A  ")
    }

    // MARK: - 4. Comment Skipping Tests

    func test_parse_htmlComments_areSkippedWithoutCorruptingState() {
        let html = "Текст до<!-- скрытый комментарий <b>не должен</b> влиять --> и текст после"
        let attr = MakabaHTMLParser.parse(html: html)

        let plain = String(attr.characters)
        XCTAssertEqual(plain, "Текст до и текст после")
        XCTAssertFalse(plain.contains("скрытый комментарий"))

        // Ensure formatting stack was not corrupted by <b> inside comment
        for run in attr.runs {
            if let intent = run.inlinePresentationIntent {
                XCTAssertFalse(intent.contains(.stronglyEmphasized))
            }
        }
    }

    // MARK: - 5. Scheme Whitelist & Security Neutralization

    func test_parse_dangerousSchemesAreNeutralized() {
        // javascript:, file:, data: must have their links stripped
        let maliciousHtml = """
        <a href="javascript:alert(document.cookie)">Опасная ссылка</a>
        <a href="file:///etc/passwd">Локальный файл</a>
        <a href="data:text/html,<script>alert(1)</script>">Data URI</a>
        <a href="https://2ch.org/b/">Безопасная ссылка</a>
        """

        let attr = MakabaHTMLParser.parse(html: maliciousHtml)

        var safeLinks = [URL]()
        for run in attr.runs {
            if let link = run.link {
                safeLinks.append(link)
            }
        }

        // Only https://2ch.org/b/ is whitelisted and retained
        XCTAssertEqual(safeLinks.count, 1)
        XCTAssertEqual(safeLinks.first?.absoluteString, "https://2ch.org/b/")
    }

    // MARK: - 6. Inline Formatting & Typographic Attributes

    func test_parse_boldStyling() {
        let bHtml = "Обычный <b>жирный</b> текст"
        let bAttr = MakabaHTMLParser.parse(html: bHtml)
        XCTAssertEqual(String(bAttr.characters), "Обычный жирный текст")

        var boldFound = false
        for run in bAttr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.stronglyEmphasized) {
                boldFound = true
            }
        }
        XCTAssertTrue(boldFound, "<b> must apply stronglyEmphasized intent")

        let strongHtml = "Обычный <strong>жирный</strong> текст"
        let strongAttr = MakabaHTMLParser.parse(html: strongHtml)
        var strongFound = false
        for run in strongAttr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.stronglyEmphasized) {
                strongFound = true
            }
        }
        XCTAssertTrue(strongFound, "<strong> must apply stronglyEmphasized intent")
    }

    func test_parse_italicStyling() {
        let iHtml = "Обычный <i>курсивный</i> текст"
        let iAttr = MakabaHTMLParser.parse(html: iHtml)
        XCTAssertEqual(String(iAttr.characters), "Обычный курсивный текст")

        var italicFound = false
        for run in iAttr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.emphasized) {
                italicFound = true
            }
        }
        XCTAssertTrue(italicFound, "<i> must apply emphasized intent")

        let emHtml = "<em>акцент</em>"
        let emAttr = MakabaHTMLParser.parse(html: emHtml)
        var emFound = false
        for run in emAttr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.emphasized) {
                emFound = true
            }
        }
        XCTAssertTrue(emFound, "<em> must apply emphasized intent")
    }

    func test_parse_underlineAndStrikethrough() {
        let html = "<u>Подчеркнутый</u> и <s>зачеркнутый</s> и <strike>устаревший</strike> и <del>удаленный</del>"
        let attr = MakabaHTMLParser.parse(html: html)

        var underlineFound = false
        var strikethroughFound = false

        for run in attr.runs {
            if run.underlineStyle == .single {
                underlineFound = true
            }
            if run.strikethroughStyle == .single {
                strikethroughFound = true
            }
        }

        XCTAssertTrue(underlineFound, "<u> must set underlineStyle")
        XCTAssertTrue(strikethroughFound, "<s>, <strike>, <del> must set strikethroughStyle")
    }

    func test_parse_spoilerStyling() {
        let html = "Перед <span class=\"spoiler\">секретный спойлер</span> после"
        let attr = MakabaHTMLParser.parse(html: html)

        var spoilerFound = false
        for run in attr.runs {
            if run.makabaSpoiler == true {
                spoilerFound = true
                XCTAssertNotNil(run.backgroundColor)
            }
        }

        XCTAssertTrue(spoilerFound, "<span class=\"spoiler\"> must set makabaSpoiler attribute")
    }

    func test_parse_codeStyling() {
        let html = "Используйте <code>let x = 10</code> в коде"
        let attr = MakabaHTMLParser.parse(html: html)

        var codeFound = false
        for run in attr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                codeFound = true
            }
        }
        XCTAssertTrue(codeFound, "<code> must set code presentation intent")
    }

    func test_parse_lineBreaksAndParagraphs() {
        let html = "Строка 1<br>Строка 2<br/>Строка 3<br />Строка 4<p>Параграф</p>"
        let attr = MakabaHTMLParser.parse(html: html)
        let plain = String(attr.characters)

        XCTAssertTrue(plain.contains("Строка 1\nСтрока 2\nСтрока 3\nСтрока 4\nПараграф"))
    }

    // MARK: - 7. Mathematical Inequality Preservation

    func test_parse_preservesMathematicalInequalities() {
        // Lexical scanner must not swallow '< 10' as a malformed HTML tag
        let html = "5 < 10 and 10 > 2 and x < y"
        let attr = MakabaHTMLParser.parse(html: html)
        let plain = String(attr.characters)

        XCTAssertEqual(plain, "5 < 10 and 10 > 2 and x < y")
    }

    // MARK: - 8. Plain Text & Quote Number Extraction Helpers

    func test_toPlainText_stripsAllFormatting() {
        let html = "<b>Жирный</b>, <i>курсив</i>, <span class=\"unkfunc\">&gt;цитата</span>, <a href=\"#1\">ссылка</a>"
        let plain = MakabaHTMLParser.toPlainText(html: html)

        XCTAssertEqual(plain, "Жирный, курсив, >цитата, ссылка")
    }

    func test_extractQuoteNumbers_returnsUniqueSortedList() {
        let html = """
        Ответ на &gt;&gt;100, а также <a href="/b/res/1.html#200" data-num="200">&gt;&gt;200</a>,
        и еще раз &gt;&gt;100, и по ссылке <a href="#300">&gt;&gt;300</a>.
        """
        let quoteNumbers = MakabaHTMLParser.extractQuoteNumbers(html: html)

        XCTAssertEqual(quoteNumbers.sorted(), [100, 200, 300])
    }
}
