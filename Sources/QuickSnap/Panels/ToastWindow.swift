/**
 * [INPUT]: 依赖 AppKit、SwiftUI
 * [OUTPUT]: 提供 ToastPresenter（轻量自动销毁浮动 HUD 提示）
 * [POS]: Panels 模块的即时反馈提示组件，用于复制、保存与错误提示
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import SwiftUI

@MainActor
public final class ToastPresenter {
    public static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    public func show(message: String, systemImage: String = "checkmark.circle.fill", duration: TimeInterval = 1.5) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let view = HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
        )

        let hosting = NSHostingView(rootView: view)
        let fittingSize = hosting.fittingSize
        let width = max(140, fittingSize.width)
        let height = max(36, fittingSize.height)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height - 48,
            width: width,
            height: height
        )

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .statusBar
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient]
        newPanel.contentView = hosting
        newPanel.alphaValue = 1
        newPanel.orderFrontRegardless()

        panel = newPanel

        let workItem = DispatchWorkItem { [weak self, weak newPanel] in
            guard let self, let target = newPanel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                target.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self, weak target] in
                    target?.orderOut(nil)
                    if self?.panel === target {
                        self?.panel = nil
                    }
                }
            })
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
