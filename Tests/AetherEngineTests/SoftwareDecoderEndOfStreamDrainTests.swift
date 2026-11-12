import Foundation
import Testing
import AetherLibavcodec
import AetherLibavutil
@testable import AetherEngine

/// `SoftwareVideoDecoder.drainForEndOfStream()` used to be the protocol's empty default. At end of
/// media (and before a forward-only discontinuity fold) the demux loop drains and then flushes, so
/// the flush's `avcodec_flush_buffers` discarded whatever a reordering decoder still held. MPEG-2
/// always holds its newest reference picture (`low_delay` 0): a title's last picture never reached
/// the screen, and a source that is a single picture (a DVD menu still) showed nothing at all.
///
/// The fixtures are synthetic MPEG-2 elementary streams, so the real decoder runs over real bitstreams.
@Suite("SoftwareDecoderEndOfStreamDrain")
struct SoftwareDecoderEndOfStreamDrainTests {

    @Test("a single-picture source shows its picture once drained")
    func singleStillIsReleased() throws {
        let run = try Self.decode(Self.stillBase64)
        defer { run.decoder.close() }
        #expect(run.packets == 1)
        // The defect: the decoder holds the only picture, and the flush that follows would drop it.
        #expect(run.counter.value == 0)

        run.decoder.drainForEndOfStream()
        #expect(run.counter.value == 1)
    }

    @Test("a reordered stream delivers every picture, the held last one included")
    func lastPictureOfReorderedStreamIsReleased() throws {
        let run = try Self.decode(Self.reorderedBase64)
        defer { run.decoder.close() }
        #expect(run.packets == 6)
        #expect(run.counter.value < run.packets)

        run.decoder.drainForEndOfStream()
        #expect(run.counter.value == run.packets)
    }

    @Test("drain then flush leaves the decoder usable for packets after a fold")
    func decoderDecodesAgainAfterDrainAndFlush() throws {
        let run = try Self.decode(Self.stillBase64)
        defer { run.decoder.close() }
        run.decoder.drainForEndOfStream()
        run.decoder.flush()
        #expect(run.counter.value == 1)

        // The next generation of a forward-only source: same decoder, fresh packets.
        try Self.feed(Self.stillBase64, into: run.decoder)
        run.decoder.drainForEndOfStream()
        #expect(run.counter.value == 2)
    }

    @Test("draining twice or on a closed decoder is harmless")
    func repeatedAndClosedDrainsAreNoOps() throws {
        let run = try Self.decode(Self.stillBase64)
        run.decoder.drainForEndOfStream()
        run.decoder.drainForEndOfStream()
        #expect(run.counter.value == 1)
        run.decoder.close()
        run.decoder.drainForEndOfStream()
        #expect(run.counter.value == 1)
    }

    // MARK: - Support

    private struct Run {
        let decoder: SoftwareVideoDecoder
        let counter: FrameCounter
        let packets: Int
    }

    private static func decode(_ base64: String) throws -> Run {
        let counter = FrameCounter()
        let decoder = SoftwareVideoDecoder()
        let packets = try feed(base64, into: decoder, opening: counter)
        return Run(decoder: decoder, counter: counter, packets: packets)
    }

    /// Demuxes `base64` and sends every video packet to `decoder`, opening it first when `counter`
    /// is given. Returns the number of packets sent.
    @discardableResult
    private static func feed(_ base64: String, into decoder: SoftwareVideoDecoder,
                             opening counter: FrameCounter? = nil) throws -> Int {
        let data = try #require(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
        let demuxer = Demuxer()
        try demuxer.open(reader: DataIOReader(data: data), formatHint: "mpegvideo")
        defer { demuxer.close() }

        let videoIndex = demuxer.videoStreamIndex
        if let counter {
            let stream = try #require(demuxer.stream(at: videoIndex))
            try decoder.open(stream: stream) { _, _, _ in counter.increment() }
        }
        var packets = 0
        while let pkt = try? demuxer.readPacket() {
            if pkt.pointee.stream_index == videoIndex {
                packets += 1
                decoder.decode(packet: pkt)
            }
            var p: UnsafeMutablePointer<AVPacket>? = pkt
            trackedPacketFree(&p)
        }
        return packets
    }

    private final class FrameCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0
        func increment() {
            lock.lock()
            storage += 1
            lock.unlock()
        }
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// 64x48 MPEG-2, one intra picture. Regenerate:
    ///   ffmpeg -f lavfi -i "color=c=blue:s=64x48:r=25" -frames:v 1 -c:v mpeg2video -f mpeg2video still.m2v
    static let stillBase64 = """
        AAABswQAMCP//+AYAAABtRSKAAEAAAAAAbgACABAAAABAAAP//gAAAG1j//zQYAAAAEBE/lFKUv3C825SlIi5SlIi5SlIiAA
        AAECE/lFKUv3C825SlIi5SlIi5SlIiAAAAEDE/lFKUv3C825SlIi5SlIi5SlIiA=
        """

    /// 64x48 MPEG-2, six pictures, I and P with two B-frames between references. Regenerate:
    ///   ffmpeg -f lavfi -i "color=c=green:s=64x48:r=25" -frames:v 6 -c:v mpeg2video -g 6 -bf 2 \
    ///     -f mpeg2video run.m2v
    static let reorderedBase64 = """
        AAABswQAMCP//+AYAAABtRSKAAEAAAAAAbgACABAAAABAAAP//gAAAG1j//zQYAAAAEBE/IUpS+avkLlKUiLlKUiLlKUiIAA
        AAECE/IUpS+avkLlKUiLlKUiLlKUiIAAAAEDE/IUpS+avkLlKUiLlKUiLlKUiIAAAAEAANf/+4AAAAG1gR/zQYAAAAEBEnRw
        AAABAhJ0cAAAAQMSdHAAAAEAAF//+7gAAAG1gRETQYAAAAEBGlosAAABAhpaLAAAAQMaWiwAAAEAAJ//+7gAAAG1gRETQYAA
        AAEBGrSwAAABAhq0sAAAAQMatLAAAAEAAVf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHAAAAEAAR//+7gAAAG1
        gRETQYAAAAEBGrSwAAABAhq0sAAAAQMatLA=
        """
}
