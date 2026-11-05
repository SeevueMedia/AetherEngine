import AetherASS
import XCTest

final class ASSRendererTests: XCTestCase {
    func testCustomFontTimingPositionAndKaraoke() throws {
        let renderer = try ASSRenderer(limits: .init(fontBytes: 1 << 20, scriptBytes: 1 << 20, bitmapMegabytes: 4))
        try renderer.replaceFonts([.init(name: "synthetic.ttf", data: SubtitleFixture.font)])
        try renderer.load(script: SubtitleFixture.script)
        XCTAssertNil(try renderer.render(at: 0, width: 320, height: 180).image)
        let first = try XCTUnwrap(try renderer.render(at: 1.1, width: 320, height: 180).image)
        let second = try XCTUnwrap(try renderer.render(at: 2.8, width: 320, height: 180).image)
        XCTAssertNotEqual(first.dataProvider?.data as Data?, second.dataProvider?.data as Data?)
        XCTAssertNil(try renderer.render(at: 4.1, width: 320, height: 180).image)
    }

    func testLimitsAndMalformedInputs() throws {
        let renderer = try ASSRenderer(limits: .init(fontBytes: 2048, scriptBytes: 2048, bitmapMegabytes: 4))
        XCTAssertThrowsError(try renderer.replaceFonts([.init(name: "bad", data: Data([1, 2, 3]))]))
        XCTAssertThrowsError(try renderer.load(script: String(repeating: "x", count: 2049)))
        XCTAssertThrowsError(try renderer.render(at: .nan, width: 320, height: 180))
        XCTAssertThrowsError(try renderer.render(at: 0, width: 8192, height: 8192))
    }

    func testRedrawAfterClearingDestinationAndFontReplacement() throws {
        let renderer = try ASSRenderer(limits: .init(fontBytes: 1 << 20, scriptBytes: 1 << 20, bitmapMegabytes: 4))
        try renderer.replaceFonts([.init(name: "synthetic.ttf", data: SubtitleFixture.font)])
        try renderer.load(script: SubtitleFixture.script.replacingOccurrences(of: "\\kf200", with: ""))
        let first = try XCTUnwrap(try renderer.render(at: 1.5, width: 320, height: 180).image)
        XCTAssertFalse(try renderer.render(at: 1.6, width: 320, height: 180).changed)
        let restored = try renderer.render(at: 1.7, width: 320, height: 180, forceRedraw: true)
        XCTAssertTrue(restored.changed)
        XCTAssertEqual(first.dataProvider?.data as Data?, restored.image?.dataProvider?.data as Data?)
        // The library owns its font bytes, and replacing the set drops its old
        // faces/caches while retaining the script on the new library.
        try renderer.replaceFonts([])
        let fallback = try XCTUnwrap(try renderer.render(at: 1.7, width: 320, height: 180).image)
        XCTAssertNotEqual(first.dataProvider?.data as Data?, fallback.dataProvider?.data as Data?)
    }
}
