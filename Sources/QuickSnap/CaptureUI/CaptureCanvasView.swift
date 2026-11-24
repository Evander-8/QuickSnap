/**
 * [INPUT]: 依赖 AppKit、CoreGraphics、QuickSnapCore（CapturedDisplay、AnnotationModels、AnnotationRenderer）
 * [OUTPUT]: 提供 CaptureMode 与 CaptureCanvasView（冻结屏幕、选区调整、8 向手柄、标注绘制与惰性马赛克）
 * [POS]: CaptureUI 的核心交互画布，采用翻转坐标系与共享渲染器实现零卡顿所见即所得
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import QuickSnapCore

enum CaptureMode {
    case standard
    case ocr
}

@MainActor
final class CaptureCanvasView: NSView, NSTextViewDelegate {
    private enum Interaction {
        case idle
        case creatingSelection(origin: CGPoint)
        case movingSelection(lastPoint: CGPoint)
        case resizingSelection(handle: SelectionHandle)
        case drawingAnnotation(AnnotationItem)
    }

    let display: CapturedDisplay
    let mode: CaptureMode

    var onSelectionBegan: (() -> Void)?
    var onRequestCopy: ((CGRect, [AnnotationItem], CGImage?) -> Void)?
    var onRequestSave: ((CGRect, [AnnotationItem], CGImage?) -> Void)?
    var onRequestPin: ((CGRect, [AnnotationItem], CGImage?) -> Void)?
    var onRequestOCR: ((CGRect, [AnnotationItem], CGImage?) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var selectionRect: CGRect?
    private var interaction: Interaction = .idle
    private var activeTool: AnnotationTool = .none
    private var activeColor: AnnotationColor = .red
    private var activeWidth: StrokeWidth = .medium
    private var history = AnnotationHistory()
    private var inProgressItem: AnnotationItem?
    private var mosaicThumbnail: CGImage?
    private var pixelSampler: PixelSampler?
    private var hoveredWindow: DetectedWindow?
    private var pendingClickWindow: DetectedWindow?
    private var pointerLocation: CGPoint?
    private var useRGBFormat = false

    private let toolbarView = FloatingToolbarView()
    private var textContainer: NSView?
    private var textView: NSTextView?
    private var textOrigin: CGPoint = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, display: CapturedDisplay, mode: CaptureMode) {
        self.display = display
        self.mode = mode
        super.init(frame: frame)
        wantsLayer = true
        setupToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clearSelectionFromSibling() {
        commitPendingTextIfNeeded()
        selectionRect = nil
        interaction = .idle
        inProgressItem = nil
        history.clear()
        activeTool = .none
        toolbarView.isHidden = true
        syncToolbarState()
        needsDisplay = true
    }

    func cleanup() {
        commitPendingTextIfNeeded()
        removePendingTextEditor()
        toolbarView.removeFromSuperview()
        history.clear()
        inProgressItem = nil
        mosaicThumbnail = nil
        pixelSampler = nil
        hoveredWindow = nil
        pendingClickWindow = nil
        pointerLocation = nil
        selectionRect = nil
        onSelectionBegan = nil
        onRequestCopy = nil
        onRequestSave = nil
        onRequestPin = nil
        onRequestOCR = nil
        onCancel = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
        hoveredWindow = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. 正向绘制冻结屏幕底图
        AnnotationRenderer.drawImageUpright(display.image, in: bounds, context: ctx)

        // 2. 绘制半透明暗色遮罩，挖空选区或悬停识别到的窗口
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        if let rect = selectionRect, rect.width >= 1, rect.height >= 1 {
            ctx.addRect(bounds)
            ctx.addRect(rect)
            ctx.fillPath(using: .evenOdd)
        } else if let win = hoveredWindow {
            ctx.addRect(bounds)
            ctx.addRect(win.frameInDisplay)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }
        ctx.restoreGState()

        if let rect = selectionRect, rect.width >= 1, rect.height >= 1 {
            // 3. 在选区裁剪范围内绘制已提交标注与进行中标注
            ctx.saveGState()
            ctx.clip(to: rect)
            AnnotationRenderer.draw(
                annotations: history.items,
                in: ctx,
                mosaicThumbnail: mosaicThumbnail,
                canvasBounds: bounds
            )
            if let inProgressItem {
                AnnotationRenderer.draw(
                    item: inProgressItem,
                    in: ctx,
                    mosaicThumbnail: mosaicThumbnail,
                    canvasBounds: bounds
                )
            }
            ctx.restoreGState()

            // 4. 绘制选区边框、8 向调整手柄与实时像素尺寸标签
            drawSelectionChrome(rect: rect, in: ctx)
        } else {
            if let win = hoveredWindow {
                drawHoveredWindowChrome(win, in: ctx)
            }
            drawEmptyHint(in: ctx)
        }

        // 5. 框选与微调期间显示局部像素放大镜与取色器
        if shouldShowMagnifier(), let pointer = pointerLocation {
            drawMagnifierLoupe(at: pointer, in: ctx)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if textContainer != nil {
            commitPendingTextIfNeeded()
        }

        if let rect = selectionRect, event.clickCount == 2, activeTool == .none, rect.contains(point) {
            triggerCopy()
            return
        }

        if let rect = selectionRect {
            if let handle = SelectionMath.hitTestHandle(point, rect: rect) {
                interaction = .resizingSelection(handle: handle)
                toolbarView.isHidden = true
                return
            }

            if activeTool != .none, rect.contains(point) {
                if activeTool == .text {
                    openInlineTextEditor(at: point, inside: rect)
                    return
                }
                if activeTool == .stepNumber {
                    let item = AnnotationItem(
                        tool: .stepNumber,
                        color: activeColor,
                        strokeWidth: CGFloat(activeWidth.rawValue),
                        startPoint: point,
                        stepNumber: history.nextStepNumber
                    )
                    history.append(item)
                    syncToolbarState()
                    needsDisplay = true
                    return
                }
                let item = AnnotationItem(
                    tool: activeTool,
                    color: activeColor,
                    strokeWidth: CGFloat(activeWidth.rawValue),
                    startPoint: point,
                    endPoint: point,
                    points: (activeTool == .brush || activeTool == .highlighter || activeTool == .mosaic) ? [point] : []
                )
                if activeTool == .mosaic {
                    ensureMosaicThumbnail()
                }
                inProgressItem = item
                interaction = .drawingAnnotation(item)
                needsDisplay = true
                return
            }

            if rect.contains(point) {
                interaction = .movingSelection(lastPoint: point)
                toolbarView.isHidden = true
                return
            }
        }

        // 开始新选区（记录当前悬停窗口以便单击直接捕获整窗）
        pendingClickWindow = hoveredWindow
        onSelectionBegan?()
        history.clear()
        inProgressItem = nil
        activeTool = .none
        syncToolbarState()
        toolbarView.isHidden = true
        selectionRect = CGRect(origin: point, size: .zero)
        interaction = .creatingSelection(origin: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        pointerLocation = point

        switch interaction {
        case .idle:
            break

        case .creatingSelection(let origin):
            selectionRect = SelectionMath.normalizedRect(from: origin, to: point)
            needsDisplay = true

        case .movingSelection(let lastPoint):
            guard let current = selectionRect else { return }
            let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
            selectionRect = SelectionMath.movedRect(current, delta: delta, within: bounds)
            interaction = .movingSelection(lastPoint: point)
            needsDisplay = true

        case .resizingSelection(let handle):
            guard let current = selectionRect else { return }
            selectionRect = SelectionMath.resizedRect(current, handle: handle, to: point, within: bounds)
            needsDisplay = true

        case .drawingAnnotation(var item):
            switch item.tool {
            case .brush, .highlighter, .mosaic:
                if let last = item.points.last {
                    let dist = hypot(point.x - last.x, point.y - last.y)
                    if dist >= 2 {
                        item.points.append(point)
                    }
                } else {
                    item.points.append(point)
                }
            default:
                item.endPoint = point
            }
            inProgressItem = item
            interaction = .drawingAnnotation(item)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let releasePoint = clampToBounds(convert(event.locationInWindow, from: nil))
        switch interaction {
        case .creatingSelection(let origin):
            let dragDistance = hypot(releasePoint.x - origin.x, releasePoint.y - origin.y)
            if dragDistance < 6, let win = pendingClickWindow {
                selectionRect = win.frameInDisplay
                pendingClickWindow = nil
                hoveredWindow = nil
                if mode == .ocr {
                    interaction = .idle
                    onRequestOCR?(win.frameInDisplay, history.items, mosaicThumbnail)
                    return
                }
                showAndRepositionToolbar(for: win.frameInDisplay)
            } else if let rect = selectionRect, rect.width >= 10, rect.height >= 10 {
                pendingClickWindow = nil
                hoveredWindow = nil
                if mode == .ocr {
                    interaction = .idle
                    onRequestOCR?(rect, history.items, mosaicThumbnail)
                    return
                }
                showAndRepositionToolbar(for: rect)
            } else {
                pendingClickWindow = nil
                selectionRect = nil
                toolbarView.isHidden = true
            }

        case .movingSelection, .resizingSelection:
            if let rect = selectionRect, rect.width >= 10, rect.height >= 10 {
                showAndRepositionToolbar(for: rect)
            }

        case .drawingAnnotation(let item):
            inProgressItem = nil
            if isMeaningfulAnnotation(item) {
                history.append(item)
                syncToolbarState()
            }

        case .idle:
            break
        }

        interaction = .idle
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointerLocation = clampToBounds(point)
        if selectionRect == nil {
            hoveredWindow = display.windows.first(where: { $0.frameInDisplay.contains(point) })
        } else {
            hoveredWindow = nil
        }
        updateCursor(at: point)
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        if (event.keyCode == 56 || event.keyCode == 60),
           event.modifierFlags.contains(.shift),
           shouldShowMagnifier() {
            useRGBFormat.toggle()
            needsDisplay = true
        }
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.keyCode == 53 { // Esc
            if textContainer != nil {
                removePendingTextEditor()
                window?.makeFirstResponder(self)
                return
            }
            onCancel?()
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            if mode == .ocr {
                triggerOCR()
            } else {
                triggerCopy()
            }
            return
        }

        if flags.isEmpty,
           textContainer == nil,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           shouldShowMagnifier(),
           let pointer = pointerLocation {
            copySampledColor(at: pointer)
            return
        }

        if flags == [.command], let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "c":
                triggerCopy()
                return
            case "p":
                triggerPin()
                return
            case "s":
                triggerSave()
                return
            case "z":
                performUndo()
                return
            default:
                break
            }
        }

        if flags == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            performRedo()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if !isShift {
                commitPendingTextIfNeeded()
                window?.makeFirstResponder(self)
                return true
            }
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            removePendingTextEditor()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    // MARK: - Private Helpers

    private func setupToolbar() {
        toolbarView.isHidden = true
        toolbarView.onSelectTool = { [weak self] tool in
            guard let self else { return }
            self.commitPendingTextIfNeeded()
            self.activeTool = tool
            if tool == .mosaic {
                self.ensureMosaicThumbnail()
            }
            self.syncToolbarState()
            if let rect = self.selectionRect {
                self.toolbarView.reposition(for: rect, within: self.bounds)
            }
        }
        toolbarView.onSelectColor = { [weak self] color in
            guard let self else { return }
            self.activeColor = color
            self.textView?.textColor = color.nsColor
            self.syncToolbarState()
        }
        toolbarView.onSelectWidth = { [weak self] width in
            guard let self else { return }
            self.activeWidth = width
            self.syncToolbarState()
        }
        toolbarView.onUndo = { [weak self] in self?.performUndo() }
        toolbarView.onRedo = { [weak self] in self?.performRedo() }
        toolbarView.onPin = { [weak self] in self?.triggerPin() }
        toolbarView.onOCR = { [weak self] in self?.triggerOCR() }
        toolbarView.onSave = { [weak self] in self?.triggerSave() }
        toolbarView.onCopy = { [weak self] in self?.triggerCopy() }
        toolbarView.onCancel = { [weak self] in self?.onCancel?() }
        addSubview(toolbarView)
    }

    private func syncToolbarState() {
        toolbarView.updateState(
            tool: activeTool,
            color: activeColor,
            width: activeWidth,
            canUndo: history.canUndo,
            canRedo: history.canRedo
        )
    }

    private func showAndRepositionToolbar(for rect: CGRect) {
        syncToolbarState()
        toolbarView.reposition(for: rect, within: bounds)
        toolbarView.isHidden = false
    }

    private func ensureMosaicThumbnail() {
        if mosaicThumbnail == nil {
            mosaicThumbnail = AnnotationRenderer.makeMosaicThumbnail(from: display.image)
        }
    }

    private func performUndo() {
        commitPendingTextIfNeeded()
        history.undo()
        syncToolbarState()
        needsDisplay = true
    }

    private func performRedo() {
        commitPendingTextIfNeeded()
        history.redo()
        syncToolbarState()
        needsDisplay = true
    }

    private func triggerCopy() {
        commitPendingTextIfNeeded()
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else { return }
        onRequestCopy?(rect, history.items, mosaicThumbnail)
    }

    private func triggerSave() {
        commitPendingTextIfNeeded()
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else { return }
        onRequestSave?(rect, history.items, mosaicThumbnail)
    }

    private func triggerPin() {
        commitPendingTextIfNeeded()
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else { return }
        onRequestPin?(rect, history.items, mosaicThumbnail)
    }

    private func triggerOCR() {
        commitPendingTextIfNeeded()
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else { return }
        onRequestOCR?(rect, history.items, mosaicThumbnail)
    }

    private func openInlineTextEditor(at point: CGPoint, inside selection: CGRect) {
        removePendingTextEditor()

        let fontSize = max(14, CGFloat(activeWidth.rawValue) * 4.0)
        let boxWidth: CGFloat = min(260, max(120, selection.maxX - point.x - 6))
        let boxHeight: CGFloat = max(34, fontSize + 14)
        let clampedX = min(max(point.x, selection.minX + 2), max(selection.minX + 2, selection.maxX - boxWidth))
        let clampedY = min(max(point.y - fontSize * 0.5, selection.minY + 2), max(selection.minY + 2, selection.maxY - boxHeight))

        let container = NSView(frame: CGRect(x: clampedX, y: clampedY, width: boxWidth, height: boxHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        container.layer?.cornerRadius = 5
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor

        let editor = NSTextView(frame: NSRect(x: 4, y: 4, width: boxWidth - 8, height: boxHeight - 8))
        editor.drawsBackground = false
        editor.isRichText = false
        editor.font = .systemFont(ofSize: fontSize, weight: .semibold)
        editor.textColor = activeColor.nsColor
        editor.insertionPointColor = .white
        editor.delegate = self

        container.addSubview(editor)
        addSubview(container)
        window?.makeFirstResponder(editor)

        textContainer = container
        textView = editor
        textOrigin = CGPoint(x: clampedX + 4, y: clampedY + 4)
    }

    private func commitPendingTextIfNeeded() {
        guard let editor = textView else { return }
        let content = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = editor.font?.pointSize ?? 18
        removePendingTextEditor()
        if !content.isEmpty {
            let item = AnnotationItem(
                tool: .text,
                color: activeColor,
                strokeWidth: CGFloat(activeWidth.rawValue),
                startPoint: textOrigin,
                text: content,
                fontSize: fontSize
            )
            history.append(item)
            syncToolbarState()
            needsDisplay = true
        }
    }

    private func removePendingTextEditor() {
        textContainer?.removeFromSuperview()
        textContainer = nil
        textView = nil
    }

    private func isMeaningfulAnnotation(_ item: AnnotationItem) -> Bool {
        switch item.tool {
        case .none:
            return false
        case .rectangle, .ellipse, .arrow:
            return hypot(item.endPoint.x - item.startPoint.x, item.endPoint.y - item.startPoint.y) >= 4
        case .brush, .highlighter, .mosaic:
            return !item.points.isEmpty
        case .text:
            return !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stepNumber:
            return true
        }
    }

    private func ensurePixelSampler() -> PixelSampler? {
        if pixelSampler == nil {
            pixelSampler = PixelSampler(image: display.image)
        }
        return pixelSampler
    }

    private func shouldShowMagnifier() -> Bool {
        guard let pointer = pointerLocation, textContainer == nil else { return false }
        if !toolbarView.isHidden && toolbarView.frame.contains(pointer) {
            return false
        }
        if selectionRect == nil {
            return true
        }
        switch interaction {
        case .creatingSelection, .resizingSelection:
            return true
        default:
            return false
        }
    }

    private func copySampledColor(at point: CGPoint) {
        guard let sampled = ensurePixelSampler()?.sample(atCanvasPoint: point, canvasBounds: bounds) else {
            return
        }
        let value = useRGBFormat ? sampled.color.rgbString : sampled.color.hexString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        ToastPresenter.shared.show(message: "已复制色值 \(value)", systemImage: "eyedropper")
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func updateCursor(at point: CGPoint) {
        if !toolbarView.isHidden && toolbarView.frame.contains(point) {
            NSCursor.arrow.set()
            return
        }
        if let textContainer, textContainer.frame.contains(point) {
            NSCursor.iBeam.set()
            return
        }
        if let rect = selectionRect {
            if let handle = SelectionMath.hitTestHandle(point, rect: rect) {
                switch handle {
                case .left, .right:
                    NSCursor.resizeLeftRight.set()
                case .top, .bottom:
                    NSCursor.resizeUpDown.set()
                default:
                    NSCursor.crosshair.set()
                }
                return
            }
            if rect.contains(point) {
                switch activeTool {
                case .none:
                    NSCursor.openHand.set()
                case .text:
                    NSCursor.iBeam.set()
                default:
                    NSCursor.crosshair.set()
                }
                return
            }
        }
        NSCursor.crosshair.set()
    }

    private func drawEmptyHint(in ctx: CGContext) {
        let hint = mode == .ocr
            ? "点击窗口或拖拽框选文字进行离线 OCR · Esc 取消"
            : "点击捕获窗口 · 拖拽自由框选 · C 复制色值 · Esc 取消"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (hint as NSString).size(withAttributes: attributes)
        let pillWidth = textSize.width + 28
        let pillHeight: CGFloat = 34
        let pillRect = CGRect(
            x: (bounds.width - pillWidth) * 0.5,
            y: 44,
            width: pillWidth,
            height: pillHeight
        )

        ctx.saveGState()
        let path = CGPath(roundedRect: pillRect, cornerWidth: 17, cornerHeight: 17, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        ctx.fillPath()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (hint as NSString).draw(
            at: CGPoint(x: pillRect.minX + 14, y: pillRect.minY + (pillHeight - textSize.height) * 0.5),
            withAttributes: attributes
        )
        NSGraphicsContext.current = previous
        ctx.restoreGState()
    }

    private func drawSelectionChrome(rect: CGRect, in ctx: CGContext) {
        // 外框线条
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        // 8 个调整手柄
        for (_, center) in SelectionMath.handlePositions(for: rect) {
            let handleRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: handleRect)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: handleRect)
        }

        // 实时像素尺寸标签
        let pixels = SelectionMath.pixelSize(for: rect, scale: display.backingScaleFactor)
        let label = "\(pixels.width) × \(pixels.height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let badgeW = textSize.width + 14
        let badgeH: CGFloat = 22
        let badgeY = rect.minY >= badgeH + 6 ? rect.minY - badgeH - 6 : rect.minY + 6
        let badgeX = min(max(rect.minX, 4), bounds.width - badgeW - 4)
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(badgePath)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.76).cgColor)
        ctx.fillPath()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (label as NSString).draw(
            at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 3),
            withAttributes: attributes
        )
        NSGraphicsContext.current = previous
        ctx.restoreGState()
    }

    private func drawHoveredWindowChrome(_ win: DetectedWindow, in ctx: CGContext) {
        let rect = win.frameInDisplay
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(2.0)
        ctx.stroke(rect)

        let pixels = SelectionMath.pixelSize(for: rect, scale: display.backingScaleFactor)
        let label = "\(win.ownerName) · \(pixels.width) × \(pixels.height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let badgeW = textSize.width + 16
        let badgeH: CGFloat = 22
        let badgeY = rect.minY >= badgeH + 6 ? rect.minY - badgeH - 6 : rect.minY + 6
        let badgeX = min(max(rect.minX, 4), bounds.width - badgeW - 4)
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        let path = CGPath(roundedRect: badgeRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.92).cgColor)
        ctx.fillPath()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (label as NSString).draw(
            at: CGPoint(x: badgeRect.minX + 8, y: badgeRect.minY + 3.5),
            withAttributes: attributes
        )
        NSGraphicsContext.current = previous
        ctx.restoreGState()
    }

    private func drawMagnifierLoupe(at point: CGPoint, in ctx: CGContext) {
        guard let sampled = ensurePixelSampler()?.sample(atCanvasPoint: point, canvasBounds: bounds) else {
            return
        }

        let cols = 17
        let rows = 13
        let cellSize: CGFloat = 8
        let previewW = CGFloat(cols) * cellSize // 136
        let previewH = CGFloat(rows) * cellSize // 104
        let infoH: CGFloat = 52
        let cardW = previewW
        let cardH = previewH + infoH

        let offset: CGFloat = 18
        var cardX = point.x + offset
        if cardX + cardW > bounds.maxX - 8 {
            cardX = point.x - cardW - offset
        }
        var cardY = point.y + offset
        if cardY + cardH > bounds.maxY - 8 {
            cardY = point.y - cardH - offset
        }
        cardX = min(max(cardX, 8), bounds.maxX - cardW - 8)
        cardY = min(max(cardY, 8), bounds.maxY - cardH - 8)

        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        let previewRect = CGRect(x: cardX, y: cardY, width: previewW, height: previewH)
        let infoRect = CGRect(x: cardX, y: cardY + previewH, width: cardW, height: infoH)

        ctx.saveGState()
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.addPath(cardPath)
        ctx.clip()

        // 背景填充
        ctx.setFillColor(NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor)
        ctx.fill(cardRect)

        // 裁剪物理像素并按 8x 最近邻放大绘制
        let desiredCrop = CGRect(
            x: sampled.pixelX - cols / 2,
            y: sampled.pixelY - rows / 2,
            width: cols,
            height: rows
        )
        let imageBounds = CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height)
        let validCrop = desiredCrop.intersection(imageBounds)
        if !validCrop.isNull, let patch = display.image.cropping(to: validCrop) {
            let drawRect = CGRect(
                x: previewRect.minX + (validCrop.minX - desiredCrop.minX) * cellSize,
                y: previewRect.minY + (validCrop.minY - desiredCrop.minY) * cellSize,
                width: validCrop.width * cellSize,
                height: validCrop.height * cellSize
            )
            ctx.saveGState()
            ctx.clip(to: previewRect)
            ctx.interpolationQuality = .none
            AnnotationRenderer.drawImageUpright(patch, in: drawRect, context: ctx)
            ctx.restoreGState()
        }

        // 像素网格与中心准星
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        ctx.setLineWidth(0.5)
        for col in 1..<cols {
            let x = previewRect.minX + CGFloat(col) * cellSize
            ctx.move(to: CGPoint(x: x, y: previewRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: previewRect.maxY))
        }
        for row in 1..<rows {
            let y = previewRect.minY + CGFloat(row) * cellSize
            ctx.move(to: CGPoint(x: previewRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: previewRect.maxX, y: y))
        }
        ctx.strokePath()

        let centerCell = CGRect(
            x: previewRect.minX + CGFloat(cols / 2) * cellSize,
            y: previewRect.minY + CGFloat(rows / 2) * cellSize,
            width: cellSize,
            height: cellSize
        )
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(centerCell)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(0.75)
        ctx.stroke(centerCell.insetBy(dx: 1, dy: 1))

        // 底部分隔线
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(0.75)
        ctx.move(to: CGPoint(x: infoRect.minX, y: infoRect.minY))
        ctx.addLine(to: CGPoint(x: infoRect.maxX, y: infoRect.minY))
        ctx.strokePath()

        // 色块预览点
        let swatchRect = CGRect(x: infoRect.minX + 10, y: infoRect.minY + 9, width: 12, height: 12)
        ctx.setFillColor(
            NSColor(
                calibratedRed: CGFloat(sampled.color.r) / 255.0,
                green: CGFloat(sampled.color.g) / 255.0,
                blue: CGFloat(sampled.color.b) / 255.0,
                alpha: 1
            ).cgColor
        )
        ctx.fillEllipse(in: swatchRect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(0.75)
        ctx.strokeEllipse(in: swatchRect)

        // 色值与坐标文字
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        let colorText = useRGBFormat ? sampled.color.rgbString : sampled.color.hexString
        let primaryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (colorText as NSString).draw(
            at: CGPoint(x: infoRect.minX + 27, y: infoRect.minY + 8),
            withAttributes: primaryAttrs
        )

        let subText = "\(sampled.pixelX),\(sampled.pixelY) · C复制 ⇧切换"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.68)
        ]
        (subText as NSString).draw(
            at: CGPoint(x: infoRect.minX + 10, y: infoRect.minY + 29),
            withAttributes: subAttrs
        )

        NSGraphicsContext.current = previous
        ctx.restoreGState()

        // 卡片外边框
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
