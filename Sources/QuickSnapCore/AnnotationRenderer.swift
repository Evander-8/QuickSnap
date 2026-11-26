/**
 * [INPUT]: 依赖 CoreGraphics、AppKit、AnnotationModels（AnnotationItem / SelectionMath）
 * [OUTPUT]: 提供 AnnotationRenderer（矢量标注统一绘制、翻转图像绘制、局部分镜放大绘制与降采样马赛克缓存生成）
 * [POS]: 实时画布预览与离屏高清导出的唯一渲染引擎，消除两套渲染逻辑不一致
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation

public enum AnnotationRenderer {
    public enum MagnifierHitPart: Equatable, Sendable {
        case sizeHandle
        case zoomHandle
        case body
    }

    public static let minMagnifierRadius: CGFloat = 32
    public static let maxMagnifierRadius: CGFloat = 220
    public static let defaultMagnifierRadius: CGFloat = 68
    public static let minMagnifierZoom: CGFloat = 1.5
    public static let maxMagnifierZoom: CGFloat = 5.0

    public static func magnifierRadius(for item: AnnotationItem) -> CGFloat {
        let dragRadius = hypot(item.endPoint.x - item.startPoint.x, item.endPoint.y - item.startPoint.y)
        if dragRadius >= 12 {
            return min(maxMagnifierRadius, max(minMagnifierRadius, dragRadius))
        }
        if item.strokeWidth <= 3.0 {
            return 54
        } else if item.strokeWidth <= 5.5 {
            return defaultMagnifierRadius
        } else {
            return 86
        }
    }

    public static func scaledMagnifierRadius(current: CGFloat, scrollDelta: CGFloat) -> CGFloat {
        let factor = max(0.82, min(1.18, 1.0 + scrollDelta * 0.006))
        return min(maxMagnifierRadius, max(minMagnifierRadius, current * factor))
    }

    public static func scaledMagnifierZoom(current: CGFloat, scrollDelta: CGFloat) -> CGFloat {
        min(maxMagnifierZoom, max(minMagnifierZoom, current + scrollDelta * 0.015))
    }

    /// 蓝点手柄圆心（位于外环右下方 45° 位置，用于调节镜面半径）
    public static func magnifierSizeHandleCenter(for item: AnnotationItem) -> CGPoint {
        let r = magnifierRadius(for: item)
        return CGPoint(
            x: item.startPoint.x + cos(CGFloat.pi * 0.25) * r,
            y: item.startPoint.y + sin(CGFloat.pi * 0.25) * r
        )
    }

    /// 绿点手柄圆心（沿顶部圆弧 [-150°, -30°] 映射倍率 [1.5×, 5.0×]）
    public static func magnifierZoomHandleCenter(for item: AnnotationItem) -> CGPoint {
        let r = magnifierRadius(for: item)
        let clampedZoom = min(maxMagnifierZoom, max(minMagnifierZoom, item.magnification))
        let t = (clampedZoom - minMagnifierZoom) / (maxMagnifierZoom - minMagnifierZoom)
        let angle = -CGFloat.pi * 5.0 / 6.0 + t * (CGFloat.pi * 2.0 / 3.0)
        return CGPoint(
            x: item.startPoint.x + cos(angle) * r,
            y: item.startPoint.y + sin(angle) * r
        )
    }

    /// 根据绿点拖拽角度反算放大倍率
    public static func magnifierZoom(fromHandlePoint point: CGPoint, center: CGPoint) -> CGFloat {
        var angle = atan2(point.y - center.y, point.x - center.x)
        if angle > CGFloat.pi * 0.5 {
            angle -= CGFloat.pi * 2
        }
        let minAngle = -CGFloat.pi * 5.0 / 6.0
        let span = CGFloat.pi * 2.0 / 3.0
        let t = min(1, max(0, (angle - minAngle) / span))
        return minMagnifierZoom + t * (maxMagnifierZoom - minMagnifierZoom)
    }

    public static func hitTestMagnifier(at point: CGPoint, item: AnnotationItem) -> MagnifierHitPart? {
        guard item.tool == .magnifier else { return nil }
        let handleHitRadius: CGFloat = 11
        let sizeCenter = magnifierSizeHandleCenter(for: item)
        if hypot(point.x - sizeCenter.x, point.y - sizeCenter.y) <= handleHitRadius {
            return .sizeHandle
        }
        let zoomCenter = magnifierZoomHandleCenter(for: item)
        if hypot(point.x - zoomCenter.x, point.y - zoomCenter.y) <= handleHitRadius {
            return .zoomHandle
        }
        if hypot(point.x - item.startPoint.x, point.y - item.startPoint.y) <= magnifierRadius(for: item) + 4 {
            return .body
        }
        return nil
    }

    /// 仅在画布选中态绘制蓝/绿手柄，绝不写入离线导出图
    public static func drawMagnifierSelectionHandles(for item: AnnotationItem, in context: CGContext) {
        guard item.tool == .magnifier else { return }
        let handles: [(CGPoint, NSColor)] = [
            (magnifierSizeHandleCenter(for: item), .systemBlue),
            (magnifierZoomHandleCenter(for: item), .systemGreen)
        ]
        let diameter: CGFloat = 12
        for (center, fillColor) in handles {
            let handleRect = CGRect(
                x: center.x - diameter * 0.5,
                y: center.y - diameter * 0.5,
                width: diameter,
                height: diameter
            )
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 3,
                color: NSColor.black.withAlphaComponent(0.38).cgColor
            )
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: handleRect)

            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.8)
            context.strokeEllipse(in: handleRect)
            context.restoreGState()
        }
    }

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
        sourceImage: CGImage? = nil,
        canvasBounds: CGRect
    ) {
        for item in annotations {
            draw(
                item: item,
                in: context,
                mosaicThumbnail: mosaicThumbnail,
                sourceImage: sourceImage,
                canvasBounds: canvasBounds
            )
        }
    }

    public static func draw(
        item: AnnotationItem,
        in context: CGContext,
        mosaicThumbnail: CGImage?,
        sourceImage: CGImage? = nil,
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
        case .magnifier:
            drawMagnifier(item, in: context, sourceImage: sourceImage, canvasBounds: canvasBounds)
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

        withFlippedNSGraphicsContext(in: context) {
            label.draw(
                at: CGPoint(
                    x: rect.midX - textSize.width * 0.5,
                    y: rect.midY - textSize.height * 0.5
                ),
                withAttributes: attributes
            )
        }
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

    private static func drawMagnifier(
        _ item: AnnotationItem,
        in context: CGContext,
        sourceImage: CGImage?,
        canvasBounds: CGRect
    ) {
        let radius = magnifierRadius(for: item)
        let zoom = max(1.5, item.magnification)
        let center = item.startPoint
        let lensRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // 1. 放大镜外阴影
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -3),
            blur: 10,
            color: NSColor.black.withAlphaComponent(0.38).cgColor
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        context.fillEllipse(in: lensRect)
        context.restoreGState()

        // 2. 圆形镜面裁剪并按高倍率采样底图
        context.saveGState()
        context.addEllipse(in: lensRect)
        context.clip()

        if let sourceImage, canvasBounds.width > 0, canvasBounds.height > 0 {
            let scaleX = CGFloat(sourceImage.width) / canvasBounds.width
            let scaleY = CGFloat(sourceImage.height) / canvasBounds.height
            let sampleHalfSizePt = radius / zoom

            let sourceCropLogical = CGRect(
                x: center.x - sampleHalfSizePt,
                y: center.y - sampleHalfSizePt,
                width: sampleHalfSizePt * 2,
                height: sampleHalfSizePt * 2
            )
            let rawPixelCrop = CGRect(
                x: sourceCropLogical.minX * scaleX,
                y: sourceCropLogical.minY * scaleY,
                width: sourceCropLogical.width * scaleX,
                height: sourceCropLogical.height * scaleY
            )
            let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
            let clampedPixelCrop = rawPixelCrop.intersection(imageBounds)

            context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 1).cgColor)
            context.fill(lensRect)

            if !clampedPixelCrop.isNull, !clampedPixelCrop.isEmpty,
               let cropped = sourceImage.cropping(to: clampedPixelCrop) {
                let drawLogicalRect = CGRect(
                    x: center.x + (clampedPixelCrop.minX / scaleX - center.x) * zoom,
                    y: center.y + (clampedPixelCrop.minY / scaleY - center.y) * zoom,
                    width: (clampedPixelCrop.width / scaleX) * zoom,
                    height: (clampedPixelCrop.height / scaleY) * zoom
                )
                context.interpolationQuality = .high
                drawImageUpright(cropped, in: drawLogicalRect, context: context)
            }
        } else {
            context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor)
            context.fill(lensRect)
        }

        // 镜面内侧微弱高光边缘，增强光学玻璃质感
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: lensRect.insetBy(dx: 1.5, dy: 1.5))
        context.restoreGState()

        // 3. 纯中性光学玻璃镜框（外层 1pt 暗色发丝边 + 2pt 银白高光环，适配浅/深背景）
        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: lensRect.insetBy(dx: -0.5, dy: -0.5))

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: lensRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    private static func drawText(_ item: AnnotationItem, in context: CGContext) {
        let trimmed = item.text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        context.saveGState()
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
        withFlippedNSGraphicsContext(in: context) {
            (item.text as NSString).draw(at: item.startPoint, withAttributes: attributes)
        }
        context.restoreGState()
    }

    private static func withFlippedNSGraphicsContext(in context: CGContext, _ body: () -> Void) {
        if let current = NSGraphicsContext.current,
           current.isFlipped,
           current.cgContext === context {
            body()
            return
        }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.current = previous
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
