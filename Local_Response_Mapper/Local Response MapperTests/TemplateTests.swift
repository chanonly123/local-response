//
//  TemplateTests.swift
//  Local Response MapperTests
//

import XCTest

final class TemplateTests: XCTestCase {

    /// 2024-08-14 09:07:36 UTC
    private let fixedDate = Date(timeIntervalSince1970: 1_723_626_456)

    private func resolver(
        globals: [String: String] = [:],
        randomInt: @escaping (ClosedRange<Int>) -> Int = { $0.lowerBound },
        uuid: @escaping () -> String = { "UUID-1" }
    ) -> TemplateResolver {
        TemplateResolver(date: fixedDate, globals: globals, randomInt: randomInt, makeUUID: uuid)
    }

    func testTimestamps() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{timestamp}}"), "1723626456")
        XCTAssertEqual(sut.resolve("{{timestamp_ms}}"), "1723626456000")
    }

    func testIso8601IsUTC() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{iso8601}}"), "2024-08-14T09:07:36Z")
    }

    func testDateFormatArgument() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{date:yyyy-MM-dd}}"), "2024-08-14")
        XCTAssertEqual(sut.resolve("{{date:HH:mm:ss}}"), "09:07:36")
    }

    func testRandomIntUsesTheGivenRange() {
        var seen: ClosedRange<Int>?
        var sut = resolver(randomInt: { range in
            seen = range
            return 42
        })
        XCTAssertEqual(sut.resolve("{{random_int:1-100}}"), "42")
        XCTAssertEqual(seen, 1...100)
    }

    func testMalformedArgumentsAreLeftAsWritten() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{random_int:abc}}"), "{{random_int:abc}}")
        XCTAssertEqual(sut.resolve("{{date:}}"), "{{date:}}")
    }

    /// A header or body may contain braces of its own, and rules written before
    /// variables existed must keep sending exactly what they always sent.
    func testUnknownTokensAndStrayBracesSurvive() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{nope}}"), "{{nope}}")
        XCTAssertEqual(sut.resolve("{\"a\": {\"b\": 1}}"), "{\"a\": {\"b\": 1}}")
        XCTAssertEqual(sut.resolve("{{unclosed"), "{{unclosed")
        XCTAssertEqual(sut.resolve("plain text"), "plain text")
    }

    func testSubstitutionInsideSurroundingText() {
        var sut = resolver()
        XCTAssertEqual(
            sut.resolve("Bearer {{uuid}} at {{timestamp}}"),
            "Bearer UUID-1 at 1723626456"
        )
    }

    /// One value per request: an id sent in a header and in the body has to
    /// match, so the resolver caches what it computed.
    func testRepeatedTokenResolvesOnce() {
        var calls = 0
        var sut = resolver(uuid: {
            calls += 1
            return "UUID-\(calls)"
        })
        XCTAssertEqual(sut.resolve("{{uuid}}"), "UUID-1")
        XCTAssertEqual(sut.resolve("header {{uuid}}"), "header UUID-1")
        XCTAssertEqual(calls, 1)
    }

    func testWhitespaceInsideBracesIsIgnored() {
        var sut = resolver()
        XCTAssertEqual(sut.resolve("{{ timestamp }}"), "1723626456")
    }

    func testUserVariables() {
        var sut = resolver(globals: ["token": "abc123", "base_url": "https://staging.example.com"])
        XCTAssertEqual(sut.resolve("{{token}}"), "abc123")
        XCTAssertEqual(sut.resolve("{{base_url}}/v1"), "https://staging.example.com/v1")
    }

    /// Otherwise a variable could silently repoint a rule written against a
    /// built-in name.
    func testBuiltinWinsOverUserVariableOfTheSameName() {
        var sut = resolver(globals: ["uuid": "not-this"])
        XCTAssertEqual(sut.resolve("{{uuid}}"), "UUID-1")
    }
}
