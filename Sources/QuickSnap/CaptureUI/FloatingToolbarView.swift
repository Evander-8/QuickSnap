/**
 * [INPUT]: 依赖 AppKit、QuickSnapCore（AnnotationModels）与 Design（LiquidGlassBackdropView）
 * [OUTPUT]: 提供 FloatingToolbarView（全图标、悬停箭头指针、自定义悬停控件与 Liquid Glass 浮动工具栏）
 * [POS]: CaptureUI 的操作控制栏，位于选区下方或上方，路由标注切换、历史回退、固定贴图与导出动作
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import QuickSnapCore

// MARK: - 自定义全图标控件

@MainActor
private final class ToolbarIconButton: NSControl {
    private let imageView = NSImageView()
    private let isPrimary: Bool
    private var isHovered = false

    var isSelected = false {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    var onTap: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    init(
        image: NSImage?,
        tooltip: String,
        symbolPointSize: CGFloat = 13.5,
        isPrimary: Bool = false
    ) {
        self.isPrimary = isPrimary
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        toolTip = tooltip

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: symbolPointSize,
            weight: isPrimary ? .bold : .medium
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 18),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 18)
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        isHovered = true
        updateAppearance()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.opacity = 0.78
    }

    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateAppearance()
        if bounds.contains(point) {
            onTap?()
        }
    }

    private func updateAppearance() {
        alphaValue = isEnabled ? 1.0 : 0.34
        if isPrimary {
            let bg = isHovered ? NSColor.systemBlue : NSColor.systemBlue.withAlphaComponent(0.90)
            layer?.backgroundColor = bg.cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
            imageView.contentTintColor = .white
        } else if isSelected {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.88).cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor.white.withAlphaComponent(0.34).cgColor
            imageView.contentTintColor = .white
        } else if isHovered && isEnabled {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            imageView.contentTintColor = .white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            imageView.contentTintColor = NSColor.white.withAlphaComponent(0.88)
        }
    }
}

@MainActor
private final class ColorSwatchButton: NSControl {
    private let swatchLayer = CALayer()
    private let ringLayer = CALayer()
    private var isHovered = false

    var isSelected = false {
        didSet { updateAppearance() }
    }

    var onTap: (() -> Void)?

    init(color: AnnotationColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        toolTip = color.rawValue

        ringLayer.frame = CGRect(x: 1, y: 1, width: 20, height: 20)
        ringLayer.cornerRadius = 10
        ringLayer.borderWidth = 2
        layer?.addSublayer(ringLayer)

        swatchLayer.frame = CGRect(x: 4, y: 4, width: 14, height: 14)
        swatchLayer.cornerRadius = 7
        swatchLayer.backgroundColor = color.cgColor
        swatchLayer.borderWidth = 0.75
        swatchLayer.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        layer?.addSublayer(swatchLayer)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        isHovered = true
        updateAppearance()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.opacity = 0.78
    }

    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onTap?()
        }
    }

    private func updateAppearance() {
        if isSelected {
            ringLayer.borderColor = NSColor.white.cgColor
            ringLayer.opacity = 1
        } else if isHovered {
            ringLayer.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
            ringLayer.opacity = 1
        } else {
            ringLayer.opacity = 0
        }
    }
}

@MainActor
private final class StrokeDotButton: NSControl {
    private let dotLayer = CALayer()
    private var isHovered = false

    var isSelected = false {
        didSet { updateAppearance() }
    }

    var onTap: (() -> Void)?

    init(strokeWidth: StrokeWidth, dotDiameter: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = strokeWidth.label

        let origin = (24 - dotDiameter) * 0.5
        dotLayer.frame = CGRect(x: origin, y: origin, width: dotDiameter, height: dotDiameter)
        dotLayer.cornerRadius = dotDiameter * 0.5
        dotLayer.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(dotLayer)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        isHovered = true
        updateAppearance()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.opacity = 0.78
    }

    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onTap?()
        }
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.92).cgColor
            dotLayer.backgroundColor = NSColor.white.cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            dotLayer.backgroundColor = NSColor.white.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            dotLayer.backgroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
        }
    }
}

// MARK: - 浮动工具栏（全图标）

@MainActor
final class FloatingToolbarView: NSView {
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onSelectColor: ((AnnotationColor) -> Void)?
    var onSelectWidth: ((StrokeWidth) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onPin: (() -> Void)?
    var onOCR: (() -> Void)?
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?

    private let glassContainer = LiquidGlassBackdropView(
        material: .hudWindow,
        blendingMode: .withinWindow,
        preferredRadius: LiquidGlassTokens.preferredRadius,
        darkTintAlpha: 0.34,
        forceDarkAppearance: true
    )
    private let rootStack = NSStackView()
    private let mainRow = NSStackView()
    private let styleSeparator = NSView()
    private let styleRow = NSStackView()
    private let colorStack = NSStackView()
    private let styleDivider = NSView()
    private let widthStack = NSStackView()

    private var toolButtons: [AnnotationTool: ToolbarIconButton] = [:]
    private var colorButtons: [AnnotationColor: ColorSwatchButton] = [:]
    private var widthButtons: [StrokeWidth: StrokeDotButton] = [:]
    private var undoButton: ToolbarIconButton?
    private var redoButton: ToolbarIconButton?

    private var currentTool: AnnotationTool = .none
    private var currentColor: AnnotationColor = .red
    private var currentWidth: StrokeWidth = .medium
    private var forceShowStyle = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        refreshSelectionState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        // 吞掉工具栏空白处与分隔线点击，防止透传到下层画布重新框选
    }

    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {}

    func updateState(
        tool: AnnotationTool,
        color: AnnotationColor,
        width: StrokeWidth,
        canUndo: Bool,
        canRedo: Bool,
        forceShowStyle: Bool = false
    ) {
        currentTool = tool
        currentColor = color
        currentWidth = width
        self.forceShowStyle = forceShowStyle
        undoButton?.isEnabled = canUndo
        redoButton?.isEnabled = canRedo
        refreshSelectionState()
    }

    func reposition(for selectionRect: CGRect, within canvasBounds: CGRect) {
        rootStack.layoutSubtreeIfNeeded()
        let size = rootStack.fittingSize
        let margin: CGFloat = 8

        var x = selectionRect.maxX - size.width
        x = max(canvasBounds.minX + margin, min(x, canvasBounds.maxX - size.width - margin))

        var y = selectionRect.maxY + margin
        if y + size.height > canvasBounds.maxY - margin {
            let aboveY = selectionRect.minY - size.height - margin
            if aboveY >= canvasBounds.minY + margin {
                y = aboveY
            } else {
                y = max(canvasBounds.minY + margin, selectionRect.maxY - size.height - margin)
            }
        }

        frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.masksToBounds = false

        glassContainer.autoresizingMask = [.width, .height]
        glassContainer.frame = bounds
        addSubview(glassContainer)

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 6
        rootStack.detachesHiddenViews = true
        rootStack.edgeInsets = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.contentContainer.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: glassContainer.contentContainer.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: glassContainer.contentContainer.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: glassContainer.contentContainer.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: glassContainer.contentContainer.bottomAnchor)
        ])

        buildMainRow()
        buildStyleSeparator()
        buildStyleRow()

        rootStack.addArrangedSubview(mainRow)
        rootStack.addArrangedSubview(styleSeparator)
        rootStack.addArrangedSubview(styleRow)

        NSLayoutConstraint.activate([
            styleSeparator.widthAnchor.constraint(equalTo: mainRow.widthAnchor)
        ])
    }

    private func buildMainRow() {
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 3

        for tool in AnnotationTool.drawableTools {
            let iconImage: NSImage? = (tool == .text)
                ? Self.makeTextToolIcon()
                : NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: tool.displayName)
            let btn = ToolbarIconButton(image: iconImage, tooltip: tool.displayName)
            btn.onTap = { [weak self] in
                guard let self else { return }
                let nextTool: AnnotationTool = (tool == self.currentTool) ? .none : tool
                self.onSelectTool?(nextTool)
            }
            toolButtons[tool] = btn
            mainRow.addArrangedSubview(btn)
        }

        mainRow.addArrangedSubview(makeVerticalDivider())

        let undo = ToolbarIconButton(
            image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销"),
            tooltip: "撤销 (⌘Z)"
        )
        undo.isEnabled = false
        undo.onTap = { [weak self] in self?.onUndo?() }
        undoButton = undo

        let redo = ToolbarIconButton(
            image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "重做"),
            tooltip: "重做 (⌘⇧Z)"
        )
        redo.isEnabled = false
        redo.onTap = { [weak self] in self?.onRedo?() }
        redoButton = redo

        mainRow.addArrangedSubview(undo)
        mainRow.addArrangedSubview(redo)
        mainRow.addArrangedSubview(makeVerticalDivider())

        let pinBtn = ToolbarIconButton(
            image: NSImage(systemSymbolName: "pin", accessibilityDescription: "固定到屏幕"),
            tooltip: "固定到屏幕 (⌘P)"
        )
        pinBtn.onTap = { [weak self] in self?.onPin?() }

        let ocrBtn = ToolbarIconButton(
            image: NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "OCR 文字识别"),
            tooltip: "OCR 文字识别"
        )
        ocrBtn.onTap = { [weak self] in self?.onOCR?() }

        let saveBtn = ToolbarIconButton(
            image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "保存图片"),
            tooltip: "保存图片 (⌘S)"
        )
        saveBtn.onTap = { [weak self] in self?.onSave?() }

        let cancelBtn = ToolbarIconButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消"),
            tooltip: "取消 (Esc)"
        )
        cancelBtn.onTap = { [weak self] in self?.onCancel?() }

        let copyBtn = ToolbarIconButton(
            image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: "复制到剪贴板"),
            tooltip: "复制到剪贴板 (Enter)",
            symbolPointSize: 13.5,
            isPrimary: true
        )
        copyBtn.onTap = { [weak self] in self?.onCopy?() }

        mainRow.addArrangedSubview(pinBtn)
        mainRow.addArrangedSubview(ocrBtn)
        mainRow.addArrangedSubview(saveBtn)
        mainRow.addArrangedSubview(cancelBtn)
        mainRow.addArrangedSubview(copyBtn)
    }

    private func buildStyleSeparator() {
        styleSeparator.wantsLayer = true
        styleSeparator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        styleSeparator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            styleSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func buildStyleRow() {
        styleRow.orientation = .horizontal
        styleRow.alignment = .centerY
        styleRow.spacing = 8
        styleRow.detachesHiddenViews = true

        colorStack.orientation = .horizontal
        colorStack.alignment = .centerY
        colorStack.spacing = 4
        for color in AnnotationColor.allCases {
            let swatch = ColorSwatchButton(color: color)
            swatch.onTap = { [weak self] in self?.onSelectColor?(color) }
            colorButtons[color] = swatch
            colorStack.addArrangedSubview(swatch)
        }

        styleDivider.wantsLayer = true
        styleDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        styleDivider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            styleDivider.widthAnchor.constraint(equalToConstant: 1),
            styleDivider.heightAnchor.constraint(equalToConstant: 16)
        ])

        widthStack.orientation = .horizontal
        widthStack.alignment = .centerY
        widthStack.spacing = 4
        let diameters: [StrokeWidth: CGFloat] = [.thin: 5, .medium: 8.5, .thick: 12]
        for width in StrokeWidth.allCases {
            let dot = StrokeDotButton(strokeWidth: width, dotDiameter: diameters[width] ?? 8)
            dot.onTap = { [weak self] in self?.onSelectWidth?(width) }
            widthButtons[width] = dot
            widthStack.addArrangedSubview(dot)
        }

        styleRow.addArrangedSubview(colorStack)
        styleRow.addArrangedSubview(styleDivider)
        styleRow.addArrangedSubview(widthStack)
    }

    private func refreshSelectionState() {
        for (tool, btn) in toolButtons {
            btn.isSelected = (tool == currentTool)
        }
        for (color, btn) in colorButtons {
            btn.isSelected = (color == currentColor)
        }
        for (width, btn) in widthButtons {
            btn.isSelected = (width == currentWidth)
        }

        let showStyle = currentTool != .none || forceShowStyle
        styleSeparator.isHidden = !showStyle
        styleRow.isHidden = !showStyle

        let hideColors = (currentTool == .mosaic || currentTool == .magnifier || (currentTool == .none && forceShowStyle))
        colorStack.isHidden = hideColors
        styleDivider.isHidden = hideColors
    }

    private func makeVerticalDivider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 16)
        ])
        return line
    }

    /// 自定义几何 "T" 模板图标，避免 SF Symbol textformat 在中文系统上被本地化为“格式”
    private static func makeTextToolIcon() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.65
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 2.5, y: 11.2))
            path.line(to: NSPoint(x: 11.5, y: 11.2))
            path.move(to: NSPoint(x: 7.0, y: 11.2))
            path.line(to: NSPoint(x: 7.0, y: 2.6))
            path.move(to: NSPoint(x: 5.2, y: 2.6))
            path.line(to: NSPoint(x: 8.8, y: 2.6))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
