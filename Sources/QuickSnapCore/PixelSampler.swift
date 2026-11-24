/**
 * [INPUT]: 依赖 Foundation、CoreGraphics
 * [OUTPUT]: 提供 SampledColor（HEX/RGB 格式化）与 PixelSampler（O(1) 多字节序像素取色缓存器）
 * [POS]: QuickSnapCore 的取色引擎，缓存单帧位图数据避免悬停移动时重复分配内存
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import CoreGraphics
import Foundation

public struct SampledColor: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    public var rgbString: String {
        "RGB(\(r), \(g), \(b))"
    }
}

public final class PixelSampler {
    private enum Layout {
        case rgba
        case argb
        case bgra
        case abgr
    }

    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let bytesPerPixel: Int
    private let layout: Layout
    private let pixelData: CFData
    private let bytesPtr: UnsafePointer<UInt8>

    public init?(image: CGImage) {
        guard image.width > 0,
              image.height > 0,
              image.bitsPerPixel == 32,
              let provider = image.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return nil
        }

        self.width = image.width
        self.height = image.height
        self.bytesPerRow = image.bytesPerRow
        self.bytesPerPixel = 4

        let byteOrder = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let isLittle = (byteOrder == CGBitmapInfo.byteOrder32Little.rawValue)
        let alphaFirst: Bool
        switch image.alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst:
            alphaFirst = true
        default:
            alphaFirst = false
        }

        switch (isLittle, alphaFirst) {
        case (true, true): self.layout = .bgra
        case (true, false): self.layout = .abgr
        case (false, true): self.layout = .argb
        case (false, false): self.layout = .rgba
        }

        self.pixelData = data
        self.bytesPtr = ptr
    }

    public func samplePixel(x: Int, y: Int) -> SampledColor? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard offset + 3 < CFDataGetLength(pixelData) else { return nil }

        let c0 = bytesPtr[offset]
        let c1 = bytesPtr[offset + 1]
        let c2 = bytesPtr[offset + 2]
        let c3 = bytesPtr[offset + 3]

        switch layout {
        case .bgra: return SampledColor(r: c2, g: c1, b: c0)
        case .abgr: return SampledColor(r: c3, g: c2, b: c1)
        case .argb: return SampledColor(r: c1, g: c2, b: c3)
        case .rgba: return SampledColor(r: c0, g: c1, b: c2)
        }
    }

    public func sample(atCanvasPoint point: CGPoint, canvasBounds: CGRect) -> (pixelX: Int, pixelY: Int, color: SampledColor)? {
        guard canvasBounds.width > 0, canvasBounds.height > 0 else { return nil }
        let px = min(max(Int((point.x / canvasBounds.width) * CGFloat(width)), 0), width - 1)
        let py = min(max(Int((point.y / canvasBounds.height) * CGFloat(height)), 0), height - 1)
        guard let color = samplePixel(x: px, y: py) else { return nil }
        return (px, py, color)
    }
}
