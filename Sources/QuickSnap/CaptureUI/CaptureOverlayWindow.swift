/**
 * [INPUT]: 依赖 AppKit
 * [OUTPUT]: 提供 CaptureOverlayWindow（跨全屏与多桌面空间的无边框遮罩窗口）
 * [POS]: CaptureUI 的屏幕遮罩承载窗口，提供键盘焦点能力而不驻留 Dock 或切换列表
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit

@MainActor
final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }
}
