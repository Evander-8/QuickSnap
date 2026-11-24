/**
 * [INPUT]: 依赖 AppKit、CoreGraphics、QuickSnapCore（ImageExporter、SettingsStore）与 InteractiveSaver
 * [OUTPUT]: 提供 PinnedImageWindowController 与 PinManager（桌面悬浮贴图生命周期与拖拽/缩放交互）
 * [POS]: Panels 模块的桌面置顶贴图窗口，直接绘制位图并支持拖动移动、四角缩放、滚轮/捏合缩放与保存导出
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import QuickSnapCore

@MainActor
private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class FirstMouseVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class PinnedImageContentView: NSView {
    private enum ResizeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private var cgImage: CGImage?
    private let initialSize: CGSize
    private let borderLayer = CALayer()
    private let hoverBar = FirstMouseVisualEffectView()
    private let scalePill = NSTextField(labelWithString: "100%")
    private var scaleHideWorkItem: DispatchWorkItem?

    private var activeResizeCorner: ResizeCorner?
    private var resizeAnchorScreen: CGPoint = .zero

    var onScrollScale: ((CGFloat) -> Void)?
    var onPinchScale: ((CGFloat) -> Void)?
    var onResizeToFrame: ((CGRect, CGFloat) -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onOCR: (() -> Void)?
    var onResetSize: (() -> Void)?
    var onSetOpacity: ((CGFloat) -> Void)?
    var onClose: (() -> Void)?
    var onCloseAll: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, cgImage: CGImage) {
        self.cgImage = cgImage
        self.initialSize = frame.size
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        borderLayer.frame = bounds
        borderLayer.cornerRadius = 6
        borderLayer.borderWidth = 1
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        borderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(borderLayer)

        setupHoverBar()
        setupScalePill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cleanup() {
        scaleHideWorkItem?.cancel()
        scaleHideWorkItem = nil
        cgImage = nil
        hoverBar.removeFromSuperview()
        scalePill.removeFromSuperview()
        onScrollScale = nil
        onPinchScale = nil
        onResizeToFrame = nil
        onCopy = nil
        onSave = nil
        onOCR = nil
        onResetSize = nil
        onSetOpacity = nil
        onClose = nil
        onCloseAll = nil
    }

    func showScaleBadge(_ scale: CGFloat) {
        scaleHideWorkItem?.cancel()
        scalePill.stringValue = "\(Int((scale * 100).rounded()))%"
        scalePill.alphaValue = 1

        let item = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self?.scalePill.animator().alphaValue = 0
            }
        }
        scaleHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: item)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let cgImage else { return }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: bounds)
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
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            hoverBar.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            hoverBar.animator().alphaValue = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hoverBar.alphaValue > 0.1, hoverBar.frame.contains(point) {
            return
        }

        window?.makeKeyAndOrderFront(nil)

        if let corner = hitTestCorner(point), let winFrame = window?.frame {
            activeResizeCorner = corner
            resizeAnchorScreen = anchorPoint(for: corner, in: winFrame)
            return
        }

        // 由 WindowServer 原生接管无边框悬浮窗拖拽，保证跨屏与全速率丝滑移动
        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let corner = activeResizeCorner, initialSize.height > 0 else { return }
        let pointer = NSEvent.mouseLocation
        let aspect = initialSize.width / initialSize.height

        let rawWidth: CGFloat
        switch corner {
        case .topLeft, .bottomLeft:
            rawWidth = resizeAnchorScreen.x - pointer.x
        case .topRight, .bottomRight:
            rawWidth = pointer.x - resizeAnchorScreen.x
        }

        let rawHeight: CGFloat
        switch corner {
        case .topLeft, .topRight:
            rawHeight = pointer.y - resizeAnchorScreen.y
        case .bottomLeft, .bottomRight:
            rawHeight = resizeAnchorScreen.y - pointer.y
        }

        let scaleFromW = rawWidth / initialSize.width
        let scaleFromH = rawHeight / initialSize.height
        let clampedScale = min(max(max(scaleFromW, scaleFromH), 0.25), 3.0)

        let newWidth = max(48, (initialSize.width * clampedScale).rounded())
        let newHeight = max(48 / aspect, (newWidth / aspect).rounded())

        let originX: CGFloat
        switch corner {
        case .topLeft, .bottomLeft:
            originX = resizeAnchorScreen.x - newWidth
        case .topRight, .bottomRight:
            originX = resizeAnchorScreen.x
        }

        let originY: CGFloat
        switch corner {
        case .topLeft, .topRight:
            originY = resizeAnchorScreen.y
        case .bottomLeft, .bottomRight:
            originY = resizeAnchorScreen.y - newHeight
        }

        onResizeToFrame?(CGRect(x: originX, y: originY, width: newWidth, height: newHeight), clampedScale)
    }

    override func mouseUp(with event: NSEvent) {
        activeResizeCorner = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let rawDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        guard abs(rawDelta) > 0.01 else { return }
        onScrollScale?(rawDelta)
    }

    override func magnify(with event: NSEvent) {
        guard abs(event.magnification) > 0.001 else { return }
        onPinchScale?(1.0 + event.magnification)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制图片   ⌘C", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        let saveItem = NSMenuItem(title: "保存图片   ⌘S", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        let ocrItem = NSMenuItem(title: "OCR 文字识别", action: #selector(handleOCR), keyEquivalent: "")
        ocrItem.target = self
        let resetItem = NSMenuItem(title: "还原原始大小   ⌘0", action: #selector(handleResetSize), keyEquivalent: "")
        resetItem.target = self

        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for (title, value) in [("100%", CGFloat(1.0)), ("80%", CGFloat(0.8)), ("60%", CGFloat(0.6))] {
            let item = NSMenuItem(title: title, action: #selector(handleOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int((value * 100).rounded())
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu

        let closeItem = NSMenuItem(title: "关闭贴图   Esc", action: #selector(handleClose), keyEquivalent: "")
        closeItem.target = self
        let closeAllItem = NSMenuItem(title: "关闭全部贴图", action: #selector(handleCloseAll), keyEquivalent: "")
        closeAllItem.target = self

        menu.addItem(copyItem)
        menu.addItem(saveItem)
        menu.addItem(ocrItem)
        menu.addItem(.separator())
        menu.addItem(resetItem)
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        menu.addItem(closeItem)
        menu.addItem(closeAllItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 53 { // Esc
            onClose?()
            return
        }
        if flags == [.command], let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "w":
                onClose?()
                return
            case "c":
                onCopy?()
                return
            case "s":
                onSave?()
                return
            case "0":
                onResetSize?()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Private Helpers

    private func hitTestCorner(_ point: CGPoint) -> ResizeCorner? {
        let edge: CGFloat = 14
        let isLeft = point.x <= edge
        let isRight = point.x >= bounds.width - edge
        let isBottom = point.y <= edge
        let isTop = point.y >= bounds.height - edge

        if isTop && isLeft { return .topLeft }
        if isTop && isRight { return .topRight }
        if isBottom && isLeft { return .bottomLeft }
        if isBottom && isRight { return .bottomRight }
        return nil
    }

    private func anchorPoint(for corner: ResizeCorner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: frame.maxX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.minX, y: frame.minY)
        case .bottomLeft: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.minX, y: frame.maxY)
        }
    }

    private func updateCursor(at point: CGPoint) {
        if hoverBar.alphaValue > 0.1 && hoverBar.frame.contains(point) {
            NSCursor.arrow.set()
            return
        }
        if hitTestCorner(point) != nil {
            NSCursor.crosshair.set()
            return
        }
        NSCursor.openHand.set()
    }

    private func setupHoverBar() {
        hoverBar.material = .hudWindow
        hoverBar.blendingMode = .withinWindow
        hoverBar.state = .active
        hoverBar.appearance = NSAppearance(named: .darkAqua)
        hoverBar.wantsLayer = true
        hoverBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        hoverBar.layer?.cornerRadius = 7
        hoverBar.layer?.borderWidth = 0.5
        hoverBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        hoverBar.alphaValue = 0
        hoverBar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeMiniButton(symbol: "doc.on.doc", tooltip: "复制图片 (⌘C)", action: #selector(handleCopy)))
        stack.addArrangedSubview(makeMiniButton(symbol: "square.and.arrow.down", tooltip: "保存图片 (⌘S)", action: #selector(handleSave)))
        stack.addArrangedSubview(makeMiniButton(symbol: "text.viewfinder", tooltip: "OCR 文字识别", action: #selector(handleOCR)))
        stack.addArrangedSubview(makeMiniButton(symbol: "xmark", tooltip: "关闭贴图 (Esc)", action: #selector(handleClose)))

        hoverBar.addSubview(stack)
        addSubview(hoverBar)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: hoverBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: hoverBar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: hoverBar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: hoverBar.bottomAnchor),

            hoverBar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            hoverBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    private func setupScalePill() {
        scalePill.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        scalePill.textColor = .white
        scalePill.alignment = .center
        scalePill.wantsLayer = true
        scalePill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        scalePill.layer?.cornerRadius = 9
        scalePill.alphaValue = 0
        scalePill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scalePill)

        NSLayoutConstraint.activate([
            scalePill.centerXAnchor.constraint(equalTo: centerXAnchor),
            scalePill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            scalePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            scalePill.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func makeMiniButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = FirstMouseButton()
        btn.isBordered = false
        btn.title = ""
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        btn.contentTintColor = .white
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22)
        ])
        return btn
    }

    @objc private func handleCopy() { onCopy?() }
    @objc private func handleSave() { onSave?() }
    @objc private func handleOCR() { onOCR?() }
    @objc private func handleResetSize() { onResetSize?() }
    @objc private func handleClose() { onClose?() }
    @objc private func handleCloseAll() { onCloseAll?() }
    @objc private func handleOpacity(_ sender: NSMenuItem) {
        onSetOpacity?(CGFloat(sender.tag) / 100.0)
    }
}

@MainActor
final class PinnedImageWindowController: NSObject, NSWindowDelegate {
    private var panel: PinnedPanel?
    private var contentView: PinnedImageContentView?
    private var cgImage: CGImage?
    private let initialLogicalSize: CGSize
    private var currentScale: CGFloat = 1.0
    private weak var settings: SettingsStore?
    private var onRequestOCR: ((CGImage) -> Void)?
    private var onCloseAll: (() -> Void)?
    var onClosed: ((PinnedImageWindowController) -> Void)?

    init(
        image: CGImage,
        initialFrame: CGRect,
        settings: SettingsStore,
        onRequestOCR: @escaping (CGImage) -> Void,
        onCloseAll: @escaping () -> Void
    ) {
        self.cgImage = image
        self.initialLogicalSize = initialFrame.size
        self.settings = settings
        self.onRequestOCR = onRequestOCR
        self.onCloseAll = onCloseAll
        super.init()
        setupPanel(frame: initialFrame, image: image)
    }

    func show() {
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard panel != nil else { return }
        contentView?.cleanup()
        contentView = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel = nil
        cgImage = nil
        onRequestOCR = nil
        onCloseAll = nil
        let callback = onClosed
        onClosed = nil
        callback?(self)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    private func setupPanel(frame: CGRect, image: CGImage) {
        let newPanel = PinnedPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isReleasedWhenClosed = false
        newPanel.isMovable = true
        newPanel.acceptsMouseMovedEvents = true
        newPanel.delegate = self

        let view = PinnedImageContentView(frame: CGRect(origin: .zero, size: frame.size), cgImage: image)
        view.onScrollScale = { [weak self] delta in
            self?.applyScrollDelta(delta)
        }
        view.onPinchScale = { [weak self] multiplier in
            self?.applyPinchMultiplier(multiplier)
        }
        view.onResizeToFrame = { [weak self] newFrame, scale in
            self?.applyExplicitResize(frame: newFrame, scale: scale)
        }
        view.onCopy = { [weak self] in
            self?.copyImage()
        }
        view.onSave = { [weak self] in
            self?.saveImage()
        }
        view.onOCR = { [weak self] in
            guard let self, let image = self.cgImage else { return }
            self.onRequestOCR?(image)
        }
        view.onResetSize = { [weak self] in
            self?.resetScale()
        }
        view.onSetOpacity = { [weak self] alpha in
            self?.panel?.alphaValue = alpha
        }
        view.onClose = { [weak self] in
            self?.close()
        }
        view.onCloseAll = { [weak self] in
            self?.onCloseAll?()
        }

        newPanel.contentView = view
        panel = newPanel
        contentView = view
    }

    private func applyScrollDelta(_ delta: CGFloat) {
        guard let panel else { return }
        let factor = max(0.85, min(1.15, 1.0 + delta * 0.004))
        let nextScale = min(max(currentScale * factor, 0.25), 3.0)
        setScale(nextScale, around: panel.frame)
    }

    private func applyPinchMultiplier(_ multiplier: CGFloat) {
        guard let panel else { return }
        let nextScale = min(max(currentScale * multiplier, 0.25), 3.0)
        setScale(nextScale, around: panel.frame)
    }

    private func applyExplicitResize(frame: CGRect, scale: CGFloat) {
        guard let panel else { return }
        currentScale = scale
        panel.setFrame(frame, display: true)
        contentView?.showScaleBadge(scale)
    }

    private func resetScale() {
        guard let panel else { return }
        setScale(1.0, around: panel.frame)
    }

    private func setScale(_ scale: CGFloat, around currentFrame: CGRect) {
        guard let panel else { return }
        currentScale = scale
        let newWidth = max(48, (initialLogicalSize.width * scale).rounded())
        let newHeight = max(48, (initialLogicalSize.height * scale).rounded())
        let newFrame = CGRect(
            x: currentFrame.midX - newWidth * 0.5,
            y: currentFrame.midY - newHeight * 0.5,
            width: newWidth,
            height: newHeight
        )
        panel.setFrame(newFrame, display: true)
        contentView?.showScaleBadge(scale)
    }

    private func copyImage() {
        guard let cgImage else { return }
        ImageExporter.copyToPasteboard(cgImage)
        ToastPresenter.shared.show(message: "贴图已复制到剪贴板")
    }

    private func saveImage() {
        guard let cgImage, let settings else { return }
        InteractiveSaver.save(image: cgImage, settings: settings)
    }
}

@MainActor
final class PinManager {
    private var controllers: [PinnedImageWindowController] = []

    var count: Int { controllers.count }
    var onCountChanged: ((Int) -> Void)?

    func pin(
        image: CGImage,
        initialFrame: CGRect,
        settings: SettingsStore,
        onRequestOCR: @escaping (CGImage) -> Void
    ) {
        let controller = PinnedImageWindowController(
            image: image,
            initialFrame: initialFrame,
            settings: settings,
            onRequestOCR: onRequestOCR,
            onCloseAll: { [weak self] in
                self?.closeAll()
            }
        )
        controller.onClosed = { [weak self] closed in
            self?.controllers.removeAll(where: { $0 === closed })
            self?.onCountChanged?(self?.controllers.count ?? 0)
        }
        controllers.append(controller)
        controller.show()
        onCountChanged?(controllers.count)
    }

    func closeAll() {
        let snapshot = controllers
        controllers.removeAll()
        for controller in snapshot {
            controller.onClosed = nil
            controller.close()
        }
        onCountChanged?(0)
    }
}
