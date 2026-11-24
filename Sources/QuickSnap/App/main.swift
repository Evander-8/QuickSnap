/**
 * [INPUT]: 依赖 AppKit 与 AppDelegate
 * [OUTPUT]: QuickSnap 可执行入口，启动 NSApplication 事件循环
 * [POS]: App 模块唯一入口点，保持轻量级无 Storyboard 启动
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
