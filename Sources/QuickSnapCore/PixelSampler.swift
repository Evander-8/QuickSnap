/**
 * [INPUT]: 依赖 Foundation、CoreGraphics
 * [OUTPUT]: 提供 SampledColor（HEX/RGB 格式化）与兼容所有位深/色彩空间/IOSurface 的 PixelSampler
 * [POS]: QuickSnapCore 的取色引擎，32 位位图走 O(1) 指针直读，HDR/P3/IOSurface 自动走 1×1 sRGB 采样兜底
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

    private enum Mode {
        case direct(bytesPerRow: Int, layout: Layout, data: CFData, ptr: UnsafePointer<UInt8>)
        case fallback(image: CGImage, srgb: CGColorSpace)
    }

    private let width: Int
    private let height: Int
    private let mode: Mode

    public init?(image: CGImage) {
        guard image.width > 0, image.height > 0 else {
            return nil
        }

        self.width = image.width
        self.height = image.height

        let isFloat = image.bitmapInfo.contains(.floatComponents)
        if image.bitsPerPixel == 32,
           image.bitsPerComponent == 8,
           !isFloat,
           let provider = image.dataProvider,
           let data = provider.data,
           let ptr = CFDataGetBytePtr(data) {
            let byteOrder = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
            let isLittle = (byteOrder == CGBitmapInfo.byteOrder32Little.rawValue)
            let alphaFirst: Bool
            switch image.alphaInfo {
            case .first, .premultipliedFirst, .noneSkipFirst:
                alphaFirst = true
            default:
                alphaFirst = false
            }

            let layout: Layout
            switch (isLittle, alphaFirst) {
            case (true, true): layout = .bgra
            case (true, false): layout = .abgr
            case (false, true): layout = .argb
            case (false, false): layout = .rgba
            }

            self.mode = .direct(
                bytesPerRow: image.bytesPerRow,
                layout: layout,
                data: data,
                ptr: ptr
            )
        } else {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            self.mode = .fallback(image: image, srgb: srgb)
        }
    }

    public func samplePixel(x: Int, y: Int) -> SampledColor? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        switch mode {
        case .direct(let bytesPerRow, let layout, let data, let ptr):
            let offset = y * bytesPerRow + x * 4
            guard offset + 3 < CFDataGetLength(data) else { return nil }
            let c0 = ptr[offset]
            let c1 = ptr[offset + 1]
            let c2 = ptr[offset + 2]
            let c3 = ptr[offset + 3]

            switch layout {
            case .bgra: return SampledColor(r: c2, g: c1, b: c0)
            case .abgr: return SampledColor(r: c3, g: c2, b: c1)
            case .argb: return SampledColor(r: c1, g: c2, b: c3)
            case .rgba: return SampledColor(r: c0, g: c1, b: c2)
            }

        case .fallback(let image, let srgb):
            guard let pixelCrop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
                return nil
            }
            var rgba: [UInt8] = [0, 0, 0, 0]
            guard let ctx = CGContext(
                data: &rgba,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            ctx.draw(pixelCrop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return SampledColor(r: rgba[0], g: rgba[1], b: rgba[2])
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
