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
}
