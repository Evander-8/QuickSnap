/**
 * [INPUT]: 依赖 CoreGraphics、AppKit、AnnotationModels（AnnotationItem / SelectionMath）
 * [OUTPUT]: 提供 AnnotationRenderer（矢量标注统一绘制、翻转图像绘制与降采样马赛克缓存生成）
 * [POS]: 实时画布预览与离屏高清导出的唯一渲染引擎，消除两套渲染逻辑不一致
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation

public enum AnnotationRenderer {
    /// 生成低内存马赛克降采样底图（例如 5K 图缩小 12 倍仅占约 150 KB）
    public static func makeMosaicThumbnail(from image: CGImage, blockSize: CGFloat = 12) -> CGImage? {
        let targetWidth = max(1, Int(ceil(CGFloat(image.width) / blockSize)))
        let targetHeight = max(1, Int(ceil(CGFloat(image.height) / blockSize)))
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    /// 在左上角为原点的翻转坐标系（isFlipped=true）中正向绘制 CGImage
    public static func drawImageUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// 在左上角为原点的坐标系内绘制全部分组标注
    public static func draw(
        annotations: [AnnotationItem],
        in context: CGContext,
        mosaicThumbnail: CGImage?,
        canvasBounds: CGRect
    ) {
        for item in annotations {
            draw(item: item, in: context, mosaicThumbnail: mosaicThumbnail, canvasBounds: canvasBounds)
        }
    }

    public static func draw(
        item: AnnotationItem,
        in context: CGContext,
        mosaicThumbnail: CGImage?,
        canvasBounds: CGRect
    ) {
        switch item.tool {
        case .none:
            break
        case .rectangle:
            drawRectangle(item, in: context)
        case .ellipse:
            drawEllipse(item, in: context)
        case .arrow:
            drawArrow(item, in: context)
        case .brush:
            drawBrush(item, in: context)
        case .highlighter:
            drawHighlighter(item, in: context)
        case .mosaic:
            drawMosaic(item, in: context, mosaicThumbnail: mosaicThumbnail, canvasBounds: canvasBounds)
        case .text:
            drawText(item, in: context)
        case .stepNumber:
            drawStepNumber(item, in: context)
        }
    }

    private static func drawRectangle(_ item: AnnotationItem, in context: CGContext) {
        let rect = SelectionMath.normalizedRect(from: item.startPoint, to: item.endPoint)
        guard rect.width >= 1 || rect.height >= 1 else { return }
        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.strokeWidth)
        context.setLineJoin(.round)
        context.stroke(rect)
        context.restoreGState()
    }

    private static func drawEllipse(_ item: AnnotationItem, in context: CGContext) {
        let rect = SelectionMath.normalizedRect(from: item.startPoint, to: item.endPoint)
        guard rect.width >= 1 || rect.height >= 1 else { return }
        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.strokeWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    private static func drawArrow(_ item: AnnotationItem, in context: CGContext) {
        let start = item.startPoint
        let end = item.endPoint
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 4 else { return }

        let angle = atan2(dy, dx)
        let headLength = min(max(item.strokeWidth * 4.2, 14), length * 0.48)
        let headSpread: CGFloat = .pi / 6.5

        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * (headLength * 0.65),
            y: end.y - sin(angle) * (headLength * 0.65)
        )
        let wing1 = CGPoint(
            x: end.x - cos(angle - headSpread) * headLength,
            y: end.y - sin(angle - headSpread) * headLength
        )
        let wing2 = CGPoint(
            x: end.x - cos(angle + headSpread) * headLength,
            y: end.y - sin(angle + headSpread) * headLength
        )

        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setFillColor(item.color.cgColor)
        context.setLineWidth(item.strokeWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        context.beginPath()
        context.move(to: end)
        context.addLine(to: wing1)
        context.addLine(to: wing2)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private static func drawBrush(_ item: AnnotationItem, in context: CGContext) {
        guard !item.points.isEmpty else { return }
        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if item.points.count == 1 {
            let p = item.points[0]
            let r = item.strokeWidth * 0.5
            context.setFillColor(item.color.cgColor)
            context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        } else {
            addSmoothPolyline(item.points, to: context)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawHighlighter(_ item: AnnotationItem, in context: CGContext) {
        guard !item.points.isEmpty else { return }
        let width = max(14, item.strokeWidth * 4.0)
        let color = item.color.nsColor.withAlphaComponent(0.36).cgColor

        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if item.points.count == 1 {
            let p = item.points[0]
            let r = width * 0.5
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        } else {
            addSmoothPolyline(item.points, to: context)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawStepNumber(_ item: AnnotationItem, in context: CGContext) {
        let diameter = max(24, item.strokeWidth * 4.6)
        let rect = CGRect(
            x: item.startPoint.x - diameter * 0.5,
            y: item.startPoint.y - diameter * 0.5,
            width: diameter,
            height: diameter
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: 3,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        context.setFillColor(item.color.cgColor)
        context.fillEllipse(in: rect)

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect)

        let textColor: NSColor = (item.color == .white || item.color == .yellow)
            ? NSColor(calibratedWhite: 0.1, alpha: 1)
            : .white
        let label = "\(item.stepNumber)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: diameter * 0.52, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = label.size(withAttributes: attributes)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(
            at: CGPoint(
                x: rect.midX - textSize.width * 0.5,
                y: rect.midY - textSize.height * 0.5
            ),
            withAttributes: attributes
        )
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    private static func drawMosaic(
        _ item: AnnotationItem,
        in context: CGContext,
        mosaicThumbnail: CGImage?,
        canvasBounds: CGRect
    ) {
        guard !item.points.isEmpty else { return }
        let mosaicWidth = max(14, item.strokeWidth * 4.2)

        context.saveGState()
        context.setLineWidth(mosaicWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if item.points.count == 1 {
            let p = item.points[0]
            let r = mosaicWidth * 0.5
            context.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        } else {
            addSmoothPolyline(item.points, to: context)
            context.replacePathWithStrokedPath()
        }
        context.clip()

        if let mosaicThumbnail {
            context.interpolationQuality = .none
            drawImageUpright(mosaicThumbnail, in: canvasBounds, context: context)
        } else {
            context.setFillColor(NSColor.systemGray.withAlphaComponent(0.85).cgColor)
            context.fill(canvasBounds)
        }
        context.restoreGState()
    }

    private static func drawText(_ item: AnnotationItem, in context: CGContext) {
        let trimmed = item.text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        context.saveGState()
        let previous = NSGraphicsContext.current
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let shadow = NSShadow()
        shadow.shadowColor = item.color == .black
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.55)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: item.fontSize, weight: .semibold),
            .foregroundColor: item.color.nsColor,
            .shadow: shadow
        ]
        (item.text as NSString).draw(at: item.startPoint, withAttributes: attributes)

        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    private static func addSmoothPolyline(_ points: [CGPoint], to context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        if points.count == 2 {
            context.addLine(to: points[1])
            return
        }
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            context.addQuadCurve(to: mid, control: current)
        }
        if let last = points.last {
            context.addLine(to: last)
        }
    }
}
