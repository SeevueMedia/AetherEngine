import CoreGraphics
import CoreText
import Foundation
import Libass

/// An optional libass host overlay. Confine an instance to one serial executor.
/// It owns every C handle and returns copied images; no libass pointer escapes.
/// Fonts come from the host (including AetherEngine.fontAttachments). No network,
/// process-wide font installation or dependency on a particular player surface.
public final class ASSRenderer {
    public struct Font: Sendable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data }
    }

    public struct Limits: Sendable {
        public let fontBytes: Int
        public let scriptBytes: Int
        public let bitmapMegabytes: Int32
        public init(fontBytes: Int, scriptBytes: Int, bitmapMegabytes: Int32) {
            self.fontBytes = fontBytes
            self.scriptBytes = scriptBytes
            self.bitmapMegabytes = bitmapMegabytes
        }
    }

    public enum Failure: Error { case initialization, invalidFont, limit, invalidScript }
    public struct Frame {
        public let image: CGImage?
        public let changed: Bool
    }

    private let limits: Limits
    private let defaultFamily: String
    private var library: OpaquePointer?
    private var renderer: OpaquePointer?
    private var track: UnsafeMutablePointer<ASS_Track>?
    private var script: String?
    private var forceChange = true

    public init(limits: Limits, defaultFamily: String = "Noto Sans") throws {
        guard limits.fontBytes > 0, limits.scriptBytes > 0, limits.bitmapMegabytes > 0 else {
            throw Failure.limit
        }
        self.limits = limits
        self.defaultFamily = defaultFamily
        try replaceFonts([])
    }

    deinit { close() }

    private func close() {
        if let track { ass_free_track(track) }
        if let renderer { ass_renderer_done(renderer) }
        if let library { ass_library_done(library) }
        track = nil; renderer = nil; library = nil
    }

    /// Replace the bounded font set and rebuild font selection/glyph caches.
    /// Call before rendering the first event needing a newly delivered font.
    /// libass copies the bytes and reads the fonts' internal family/style names.
    /// A rebuild also permits eviction without accumulating fonts for a long session.
    public func replaceFonts(_ fonts: [Font]) throws {
        guard fonts.count <= 256 else { throw Failure.limit }
        var bytes = 0
        for font in fonts {
            guard !font.data.isEmpty, font.data.count <= limits.fontBytes - bytes,
                  font.data.count <= Int(Int32.max), font.name.utf8.count <= 256,
                  !font.name.contains("\0") else { throw Failure.limit }
            let faces = CTFontManagerCreateFontDescriptorsFromData(font.data as CFData)
            guard CFArrayGetCount(faces) > 0 else { throw Failure.invalidFont }
            bytes += font.data.count
        }
        // Validate before destroying a working renderer.
        guard let nextLibrary = ass_library_init() else { throw Failure.initialization }
        // Font names and subtitle text can be private. Hosts own diagnostics.
        ass_set_message_cb(nextLibrary, { _, _, _, _ in }, nil)
        ass_set_extract_fonts(nextLibrary, 0)
        for font in fonts {
            font.data.withUnsafeBytes { buffer in
                font.name.withCString { name in
                    ass_add_font(nextLibrary, name,
                                 buffer.baseAddress?.assumingMemoryBound(to: CChar.self),
                                 Int32(buffer.count))
                }
            }
        }
        guard let nextRenderer = ass_renderer_init(nextLibrary) else {
            ass_library_done(nextLibrary)
            throw Failure.initialization
        }
        ass_set_fonts(nextRenderer, nil, defaultFamily,
                      Int32(ASS_FONTPROVIDER_CORETEXT.rawValue), nil, 1)
        ass_set_cache_limits(nextRenderer, 1000, limits.bitmapMegabytes)
        close()
        library = nextLibrary; renderer = nextRenderer
        forceChange = true
        if let script { try load(script: script) }
    }

    public func load(script: String) throws {
        guard let library else { throw Failure.initialization }
        guard script.utf8.count <= limits.scriptBytes, !script.contains("\0") else { throw Failure.limit }
        var bytes = Array(script.utf8CString)
        let next = bytes.withUnsafeMutableBufferPointer {
            ass_read_memory(library, $0.baseAddress, $0.count - 1, nil)
        }
        guard let next else { throw Failure.invalidScript }
        if let track { ass_free_track(track) }
        track = next
        self.script = script
        forceChange = true
    }

    /// Render on the source timeline (seconds), independently of HLS item offsets.
    /// Geometry is in output pixels. Hard safety bounds prevent hostile canvases
    /// and timestamps from overflowing C conversions or image allocations.
    public func render(at seconds: Double, width: Int, height: Int) throws -> Frame {
        guard seconds.isFinite, seconds >= 0, seconds <= 4_000_000_000,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216 else { throw Failure.limit }
        guard let renderer, let track else { return Frame(image: nil, changed: true) }
        ass_set_frame_size(renderer, Int32(width), Int32(height))
        var changed: Int32 = 0
        let first = ass_render_frame(renderer, track, Int64(seconds * 1000), &changed)
        let didChange = changed != 0 || forceChange
        forceChange = false
        guard didChange else { return Frame(image: nil, changed: false) }
        guard let first else { return Frame(image: nil, changed: true) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var node: UnsafeMutablePointer<ASS_Image>? = first
        while let current = node {
            let image = current.pointee
            node = image.next
            guard image.w > 0, image.h > 0, image.stride >= image.w,
                  let bitmap = image.bitmap else { continue }
            let left = max(0, Int(image.dst_x)), top = max(0, Int(image.dst_y))
            let right = min(width, Int(image.dst_x) + Int(image.w))
            let bottom = min(height, Int(image.dst_y) + Int(image.h))
            guard left < right, top < bottom else { continue }
            let opacity = 255 - Int(image.color & 255)
            let colors = [Int((image.color >> 24) & 255), Int((image.color >> 16) & 255),
                          Int((image.color >> 8) & 255)]
            for y in top..<bottom {
                for x in left..<right {
                    let coverage = Int(bitmap[(y - Int(image.dst_y)) * Int(image.stride) + x - Int(image.dst_x)])
                    let alpha = (coverage * opacity + 127) / 255
                    let index = (y * width + x) * 4
                    for channel in 0..<3 {
                        pixels[index + channel] = UInt8((colors[channel] * alpha + Int(pixels[index + channel]) * (255 - alpha) + 127) / 255)
                    }
                    pixels[index + 3] = UInt8(alpha + (Int(pixels[index + 3]) * (255 - alpha) + 127) / 255)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { throw Failure.initialization }
        return Frame(image: image, changed: true)
    }
}
