/**
 * [INPUT]: 依赖 AppKit（NSVisualEffectView）、QuartzCore（CAGradientLayer / CAShapeLayer）、SwiftUI 与 CoreGraphics
 * [OUTPUT]: 提供 LiquidGlassTokens、LiquidGlassBackdropView、NativeVisualEffectBackground、liquidGlassSurface 修饰器与 LiquidGlassCG
 * [POS]: QuickSnap 应用级 Liquid Glass UI 视觉系统中心，统一工具栏、弹窗、悬浮贴图与画布 HUD 质感（不影响截图导出渲染）
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

// MARK: - 视觉令牌

enum LiquidGlassTokens {
    static let preferredRadius: CGFloat = 30

    static func continuousRadius(for size: CGSize, preferred: CGFloat = preferredRadius) -> CGFloat {
        let minEdge = min(size.width, size.height)
        guard minEdge > 0 else { return 0 }
        return min(preferred, minEdge * 0.5)
    }

    static func chromaticCGColors(alpha: CGFloat = 0.72) -> [CGColor] {
        [
            NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.98, alpha: alpha).cgColor, // cyan
            NSColor(calibratedRed: 0.38, green: 0.65, blue: 0.98, alpha: alpha).cgColor, // sky
            NSColor(calibratedRed: 0.75, green: 0.52, blue: 0.99, alpha: alpha).cgColor, // violet
            NSColor(calibratedRed: 0.96, green: 0.45, blue: 0.71, alpha: alpha).cgColor, // rose
            NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.28, alpha: alpha).cgColor, // amber
            NSColor(calibratedRed: 0.43, green: 0.91, blue: 0.72, alpha: alpha).cgColor, // mint
            NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.98, alpha: alpha).cgColor  // cyan loop
        ]
    }

    static func chromaticSwiftUIColors(for colorScheme: ColorScheme, opacity: Double? = nil) -> [Color] {
        let effectiveOpacity = opacity ?? (colorScheme == .dark ? 0.68 : 0.40)
        if colorScheme == .dark {
            return [
                Color(red: 0.40, green: 0.91, blue: 0.98).opacity(effectiveOpacity),
                Color(red: 0.38, green: 0.65, blue: 0.98).opacity(effectiveOpacity),
                Color(red: 0.75, green: 0.52, blue: 0.99).opacity(effectiveOpacity),
                Color(red: 0.96, green: 0.45, blue: 0.71).opacity(effectiveOpacity),
                Color(red: 0.99, green: 0.88, blue: 0.28).opacity(effectiveOpacity),
                Color(red: 0.43, green: 0.91, blue: 0.72).opacity(effectiveOpacity),
                Color(red: 0.40, green: 0.91, blue: 0.98).opacity(effectiveOpacity)
            ]
        }
        return [
            Color(red: 0.02, green: 0.71, blue: 0.83).opacity(effectiveOpacity), // #06B6D4
            Color(red: 0.23, green: 0.51, blue: 0.96).opacity(effectiveOpacity), // #3B82F6
            Color(red: 0.55, green: 0.36, blue: 0.96).opacity(effectiveOpacity), // #8B5CF6
            Color(red: 0.93, green: 0.28, blue: 0.60).opacity(effectiveOpacity), // #EC4899
            Color(red: 0.96, green: 0.62, blue: 0.04).opacity(effectiveOpacity), // #F59E0B
            Color(red: 0.06, green: 0.73, blue: 0.51).opacity(effectiveOpacity), // #10B981
            Color(red: 0.02, green: 0.71, blue: 0.83).opacity(effectiveOpacity)
        ]
    }
}

// MARK: - AppKit Liquid Glass 容器

@MainActor
final class LiquidGlassBackdropView: NSView {
    let contentContainer = NSView()

    private let clipView = NSView()
    private let effectView = NSVisualEffectView()
    private let tintLayer = CALayer()
    private let glossArcLayer = CAGradientLayer()
    private let glossArcMask = CAShapeLayer()
    private let insetTopHighlightLayer = CAGradientLayer()
    private let insetTopHighlightMask = CAShapeLayer()
    private let chromaticRimLayer = CAGradientLayer()
    private let chromaticRimMask = CAShapeLayer()

    private let preferredRadius: CGFloat
    private let acceptsFirstMouseClick: Bool

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        acceptsFirstMouseClick
    }

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        preferredRadius: CGFloat = LiquidGlassTokens.preferredRadius,
        darkTintAlpha: CGFloat = 0.34,
        forceDarkAppearance: Bool = true,
        acceptsFirstMouseClick: Bool = false
    ) {
        self.preferredRadius = preferredRadius
        self.acceptsFirstMouseClick = acceptsFirstMouseClick
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.44
        layer?.shadowRadius = 20
        layer?.shadowOffset = NSSize(width: 0, height: -9)

        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.layer?.cornerCurve = .continuous
        clipView.autoresizingMask = [.width, .height]
        addSubview(clipView)

        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = .active
        if forceDarkAppearance {
            effectView.appearance = NSAppearance(named: .darkAqua)
        }
        effectView.autoresizingMask = [.width, .height]
        clipView.addSubview(effectView)

        tintLayer.backgroundColor = NSColor(
            calibratedRed: 0.08,
            green: 0.10,
            blue: 0.14,
            alpha: darkTintAlpha
        ).cgColor
        clipView.layer?.addSublayer(tintLayer)

        // 顶部顺滑玻璃高光弧（AppKit 非翻转坐标系中 y=1.0 为顶边）
        glossArcLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        glossArcLayer.endPoint = CGPoint(x: 0.5, y: 0.48)
        glossArcLayer.colors = [
            NSColor.white.withAlphaComponent(0.36).cgColor,
            NSColor.white.withAlphaComponent(0.13).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        glossArcLayer.locations = [0.0, 0.46, 1.0]
        glossArcMask.fillColor = NSColor.white.cgColor
        glossArcLayer.mask = glossArcMask
        clipView.layer?.addSublayer(glossArcLayer)

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.autoresizingMask = [.width, .height]
        clipView.addSubview(contentContainer)

        // 内嵌 1px 顶部高光描边（inset 0 1px 1px rgba(255,255,255,.95)）
        insetTopHighlightLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        insetTopHighlightLayer.endPoint = CGPoint(x: 0.5, y: 0.42)
        insetTopHighlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor.white.withAlphaComponent(0.30).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        insetTopHighlightLayer.locations = [0.0, 0.24, 1.0]
        insetTopHighlightLayer.zPosition = 20
        insetTopHighlightMask.fillColor = nil
        insetTopHighlightMask.strokeColor = NSColor.white.cgColor
        insetTopHighlightMask.lineWidth = 1.1
        insetTopHighlightLayer.mask = insetTopHighlightMask
        clipView.layer?.addSublayer(insetTopHighlightLayer)

        // 1px 色散彩虹棱边（chromatic dispersion rim）
        chromaticRimLayer.type = .conic
        chromaticRimLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        chromaticRimLayer.endPoint = CGPoint(x: 1.0, y: 0.25)
        chromaticRimLayer.colors = LiquidGlassTokens.chromaticCGColors(alpha: 0.72)
        chromaticRimLayer.zPosition = 21
        chromaticRimMask.fillColor = nil
        chromaticRimMask.strokeColor = NSColor.white.cgColor
        chromaticRimMask.lineWidth = 1.0
        chromaticRimLayer.mask = chromaticRimMask
        clipView.layer?.addSublayer(chromaticRimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let radius = LiquidGlassTokens.continuousRadius(for: bounds.size, preferred: preferredRadius)
        clipView.frame = bounds
        clipView.layer?.cornerRadius = radius
        effectView.frame = clipView.bounds
        contentContainer.frame = clipView.bounds
        tintLayer.frame = clipView.bounds

        let w = bounds.width
        let h = bounds.height

        glossArcLayer.frame = clipView.bounds
        glossArcMask.frame = clipView.bounds
        glossArcMask.path = CGPath(
            ellipseIn: CGRect(x: -w * 0.14, y: h * 0.56, width: w * 1.28, height: h * 0.90),
            transform: nil
        )

        insetTopHighlightLayer.frame = clipView.bounds
        insetTopHighlightMask.frame = clipView.bounds
        let innerRect = bounds.insetBy(dx: 1.0, dy: 1.0)
        let innerR = max(0, radius - 1.0)
        insetTopHighlightMask.path = CGPath(
            roundedRect: innerRect,
            cornerWidth: innerR,
            cornerHeight: innerR,
            transform: nil
        )

        chromaticRimLayer.frame = clipView.bounds
        chromaticRimMask.frame = clipView.bounds
        let rimRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let rimR = max(0, radius - 0.5)
        chromaticRimMask.path = CGPath(
            roundedRect: rimRect,
            cornerWidth: rimR,
            cornerHeight: rimR,
            transform: nil
        )

        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }
}

// MARK: - SwiftUI Liquid Glass 视图与修饰器

struct NativeVisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var appearance: NSAppearance? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.appearance = appearance
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let darkTint: Color
    let lightTint: Color
    let withBehindWindowBlur: Bool
    let material: NSVisualEffectView.Material
    let showShadow: Bool

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let r = LiquidGlassTokens.continuousRadius(for: proxy.size, preferred: cornerRadius)
                    let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
                    ZStack {
                        if withBehindWindowBlur {
                            NativeVisualEffectBackground(material: material)
                        }

                        shape.fill(colorScheme == .dark ? darkTint : lightTint)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay(alignment: .top) {
                        // 顶部亮面高光弧（置于 overlay 防止撑宽父容器）
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65),
                                        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: proxy.size.width * 1.28, height: proxy.size.height * 0.90)
                            .offset(y: -proxy.size.height * 0.50)
                            .allowsHitTesting(false)
                    }
                    .clipShape(shape)
                    .overlay(
                        // inset 0 1px 1px rgba(255,255,255,.95) 顶部内嵌高光
                        RoundedRectangle(cornerRadius: max(0, r - 1), style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.95),
                                        Color.white.opacity(colorScheme == .dark ? 0.24 : 0.55),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1.0
                            )
                            .padding(0.75)
                    )
                    .overlay(
                        // 1px 色散彩虹棱边
                        shape.strokeBorder(
                            AngularGradient(
                                gradient: Gradient(
                                    colors: LiquidGlassTokens.chromaticSwiftUIColors(for: colorScheme)
                                ),
                                center: .center
                            ),
                            lineWidth: 1.0
                        )
                    )
                }
            }
            .shadow(
                color: Color.black.opacity(showShadow ? (colorScheme == .dark ? 0.42 : 0.08) : 0),
                radius: showShadow ? (colorScheme == .dark ? 18 : 14) : 0,
                y: showShadow ? (colorScheme == .dark ? 9 : 6) : 0
            )
            .shadow(
                color: Color.black.opacity(showShadow ? (colorScheme == .dark ? 0.22 : 0.04) : 0),
                radius: showShadow ? (colorScheme == .dark ? 5 : 3) : 0,
                y: showShadow ? (colorScheme == .dark ? 2 : 1) : 0
            )
    }
}

extension View {
    func liquidGlassSurface(
        cornerRadius: CGFloat = LiquidGlassTokens.preferredRadius,
        darkTint: Color = Color(red: 0.09, green: 0.11, blue: 0.15).opacity(0.56),
        lightTint: Color = Color.white.opacity(0.74),
        withBehindWindowBlur: Bool = false,
        material: NSVisualEffectView.Material = .hudWindow,
        showShadow: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                darkTint: darkTint,
                lightTint: lightTint,
                withBehindWindowBlur: withBehindWindowBlur,
                material: material,
                showShadow: showShadow
            )
        )
    }
}

// MARK: - CoreGraphics HUD 玻璃渲染（适用于 CaptureCanvasView 翻转坐标系）

enum LiquidGlassCG {
    /// 在翻转坐标系（isFlipped == true，rect.minY 为顶边）绘制 Liquid Glass 面板
    static func drawGlassPanel(
        in rect: CGRect,
        cornerRadius: CGFloat = LiquidGlassTokens.preferredRadius,
        context: CGContext,
        fillAlpha: CGFloat = 0.66
    ) {
        let radius = LiquidGlassTokens.continuousRadius(for: rect.size, preferred: cornerRadius)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // 1. 深邃柔和投影 + 玻璃半透明底色
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 18,
            color: NSColor.black.withAlphaComponent(0.42).cgColor
        )
        context.addPath(path)
        context.setFillColor(NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.15, alpha: fillAlpha).cgColor)
        context.fillPath()
        context.restoreGState()

        // 2. 顶部亮面高光弧（在翻转坐标系内 rect.minY 为顶边）
        context.saveGState()
        context.addPath(path)
        context.clip()

        let arcRect = CGRect(
            x: rect.minX - rect.width * 0.14,
            y: rect.minY - rect.height * 0.44,
            width: rect.width * 1.28,
            height: rect.height * 0.88
        )
        context.addEllipse(in: arcRect)
        context.clip()

        let glossColors = [
            NSColor.white.withAlphaComponent(0.32).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ] as CFArray
        let glossLocations: [CGFloat] = [0.0, 0.45, 1.0]
        if let glossGrad = CGGradient(colorsSpace: colorSpace, colors: glossColors, locations: glossLocations) {
            context.drawLinearGradient(
                glossGrad,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.48),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()

        // 3. inset 0 1px 1px rgba(255,255,255,.95) 内嵌顶部白高光边
        let innerRect = rect.insetBy(dx: 1.0, dy: 1.0)
        let innerR = max(0, radius - 1.0)
        if innerRect.width > 2, innerRect.height > 2 {
            context.saveGState()
            context.addPath(CGPath(roundedRect: innerRect, cornerWidth: innerR, cornerHeight: innerR, transform: nil))
            context.setLineWidth(1.1)
            context.replacePathWithStrokedPath()
            context.clip()

            let specularColors = [
                NSColor.white.withAlphaComponent(0.95).cgColor,
                NSColor.white.withAlphaComponent(0.28).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            let specularLocations: [CGFloat] = [0.0, 0.30, 1.0]
            if let specGrad = CGGradient(colorsSpace: colorSpace, colors: specularColors, locations: specularLocations) {
                context.drawLinearGradient(
                    specGrad,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.55),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            context.restoreGState()
        }

        // 4. 1px 色散彩虹棱边
        drawChromaticRim(in: rect, cornerRadius: radius, context: context)
    }

    static func drawChromaticRim(
        in rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext,
        alpha: CGFloat = 0.72
    ) {
        let rimRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let rimR = max(0, cornerRadius - 0.5)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        context.saveGState()
        context.addPath(CGPath(roundedRect: rimRect, cornerWidth: rimR, cornerHeight: rimR, transform: nil))
        context.setLineWidth(1.0)
        context.replacePathWithStrokedPath()
        context.clip()

        let colors = LiquidGlassTokens.chromaticCGColors(alpha: alpha) as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) {
            context.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.maxX, y: rect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }
}
