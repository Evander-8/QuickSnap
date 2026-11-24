/**
 * [INPUT]: 依赖 Foundation、CoreGraphics、AppKit、SwiftUI（颜色映射）
 * [OUTPUT]: 提供 AnnotationTool、AnnotationColor、StrokeWidth、AnnotationItem、AnnotationHistory 与 SelectionMath
 * [POS]: QuickSnapCore 的标注数据模型、历史栈与选区几何计算模块，供画布与导出器共用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

public enum AnnotationTool: String, CaseIterable, Sendable {
    case none
    case rectangle
    case ellipse
    case arrow
    case brush
    case highlighter
    case mosaic
    case text
    case stepNumber

    public var displayName: String {
        switch self {
        case .none: return "选择"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .brush: return "画笔"
        case .highlighter: return "荧光笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        case .stepNumber: return "序号"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .brush: return "scribble.variable"
        case .highlighter: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        case .text: return "textformat"
        case .stepNumber: return "1.circle"
        }
    }

    public static var drawableTools: [AnnotationTool] {
        [.rectangle, .ellipse, .arrow, .brush, .highlighter, .mosaic, .text, .stepNumber]
    }
}

public enum AnnotationColor: String, CaseIterable, Sendable {
    case red
    case yellow
    case green
    case blue
    case white
    case black

    public var nsColor: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 0.96, green: 0.24, blue: 0.24, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.99, green: 0.78, blue: 0.14, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.19, green: 0.80, blue: 0.36, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.15, green: 0.54, blue: 0.98, alpha: 1)
        case .white: return NSColor(calibratedWhite: 0.98, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.08, alpha: 1)
        }
    }

    public var cgColor: CGColor {
        nsColor.cgColor
    }

    public var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

public enum StrokeWidth: Double, CaseIterable, Sendable {
    case thin = 2.5
    case medium = 4.5
    case thick = 8.0

    public var label: String {
        switch self {
        case .thin: return "细"
        case .medium: return "中"
        case .thick: return "粗"
        }
    }
}

public struct AnnotationItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var tool: AnnotationTool
    public var color: AnnotationColor
    public var strokeWidth: CGFloat
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var points: [CGPoint]
    public var text: String
    public var fontSize: CGFloat
    public var stepNumber: Int

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        color: AnnotationColor,
        strokeWidth: CGFloat,
        startPoint: CGPoint = .zero,
        endPoint: CGPoint = .zero,
        points: [CGPoint] = [],
        text: String = "",
        fontSize: CGFloat = 18,
        stepNumber: Int = 1
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.strokeWidth = strokeWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.text = text
        self.fontSize = fontSize
        self.stepNumber = stepNumber
    }
}

public struct AnnotationHistory: Sendable {
    public private(set) var items: [AnnotationItem] = []
    private var redoStack: [AnnotationItem] = []

    public init() {}

    public var canUndo: Bool { !items.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var nextStepNumber: Int {
        (items.filter { $0.tool == .stepNumber }.map(\.stepNumber).max() ?? 0) + 1
    }

    public mutating func append(_ item: AnnotationItem) {
        items.append(item)
        redoStack.removeAll()
    }

    @discardableResult
    public mutating func undo() -> AnnotationItem? {
        guard let last = items.popLast() else { return nil }
        redoStack.append(last)
        return last
    }

    @discardableResult
    public mutating func redo() -> AnnotationItem? {
        guard let item = redoStack.popLast() else { return nil }
        items.append(item)
        return item
    }

    public mutating func clear() {
        items.removeAll()
        redoStack.removeAll()
    }
}

public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

public enum SelectionMath {
    public static func normalizedRect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        let minX = min(p1.x, p2.x)
        let minY = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    public static func clampedRect(_ rect: CGRect, to bounds: CGRect, minSize: CGFloat = 1) -> CGRect {
        let left = max(bounds.minX, min(rect.minX, bounds.maxX - minSize))
        let top = max(bounds.minY, min(rect.minY, bounds.maxY - minSize))
        let right = min(bounds.maxX, max(rect.maxX, left + minSize))
        let bottom = min(bounds.maxY, max(rect.maxY, top + minSize))
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    public static func movedRect(_ rect: CGRect, delta: CGSize, within bounds: CGRect) -> CGRect {
        let maxX = max(bounds.minX, bounds.maxX - rect.width)
        let maxY = max(bounds.minY, bounds.maxY - rect.height)
        let newX = min(max(rect.origin.x + delta.width, bounds.minX), maxX)
        let newY = min(max(rect.origin.y + delta.height, bounds.minY), maxY)
        return CGRect(origin: CGPoint(x: newX, y: newY), size: rect.size)
    }

    public static func resizedRect(
        _ rect: CGRect,
        handle: SelectionHandle,
        to point: CGPoint,
        within bounds: CGRect,
        minSize: CGFloat = 12
    ) -> CGRect {
        let clampedPoint = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )

        var left = rect.minX
        var right = rect.maxX
        var top = rect.minY
        var bottom = rect.maxY

        switch handle {
        case .topLeft:
            left = min(clampedPoint.x, right - minSize)
            top = min(clampedPoint.y, bottom - minSize)
        case .top:
            top = min(clampedPoint.y, bottom - minSize)
        case .topRight:
            right = max(clampedPoint.x, left + minSize)
            top = min(clampedPoint.y, bottom - minSize)
        case .right:
            right = max(clampedPoint.x, left + minSize)
        case .bottomRight:
            right = max(clampedPoint.x, left + minSize)
            bottom = max(clampedPoint.y, top + minSize)
        case .bottom:
            bottom = max(clampedPoint.y, top + minSize)
        case .bottomLeft:
            left = min(clampedPoint.x, right - minSize)
            bottom = max(clampedPoint.y, top + minSize)
        case .left:
            left = min(clampedPoint.x, right - minSize)
        }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    public static func handlePositions(for rect: CGRect) -> [(SelectionHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    public static func hitTestHandle(
        _ point: CGPoint,
        rect: CGRect,
        tolerance: CGFloat = 9
    ) -> SelectionHandle? {
        for (handle, center) in handlePositions(for: rect) {
            if abs(point.x - center.x) <= tolerance && abs(point.y - center.y) <= tolerance {
                return handle
            }
        }
        return nil
    }

    public static func pixelSize(for rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (
            width: max(0, Int((rect.width * scale).rounded())),
            height: max(0, Int((rect.height * scale).rounded()))
        )
    }

    /// 将翻转画布坐标系（左上角原点）的选区转换为 AppKit 全局屏幕坐标系（左下角原点）
    public static func appKitGlobalFrame(for selectionRect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + selectionRect.minX,
            y: screenFrame.maxY - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

    /// 将 CGWindowBounds（Quartz 全局左上角坐标系）映射到指定显示器翻转本地坐标系
    public static func quartzRectToDisplayLocal(
        _ quartzRect: CGRect,
        displayScreenFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect? {
        let displayQuartzMinX = displayScreenFrame.minX
        let displayQuartzMinY = primaryScreenHeight - displayScreenFrame.maxY
        let translated = CGRect(
            x: quartzRect.minX - displayQuartzMinX,
            y: quartzRect.minY - displayQuartzMinY,
            width: quartzRect.width,
            height: quartzRect.height
        )
        let displayBounds = CGRect(origin: .zero, size: displayScreenFrame.size)
        let clipped = translated.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 40, clipped.height >= 40 else {
            return nil
        }
        return clipped
    }
}
