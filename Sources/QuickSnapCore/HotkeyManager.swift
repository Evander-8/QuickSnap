/**
 * [INPUT]: 依赖 Carbon.HIToolbox（RegisterEventHotKey/InstallEventHandler/GetEventDispatcherTarget）与 SettingsStore.HotkeyCombo
 * [OUTPUT]: 提供 HotkeyAction 枚举与高可靠 HotkeyManager 全局快捷键管理器（无需辅助功能权限，支持暂停与重注册）
 * [POS]: QuickSnapCore 的全局热键引擎，负责将系统快捷键事件路由至截图与 OCR 协调器
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Carbon
import Foundation

public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case regionCapture = 1
    case ocrCapture = 2
    case fullscreenCapture = 3

    public var title: String {
        switch self {
        case .regionCapture: return "区域截图"
        case .ocrCapture: return "OCR 文字识别"
        case .fullscreenCapture: return "全屏截图"
        }
    }
}

public final class HotkeyManager {
    private static let signature: OSType = 0x51534E50 // 'QSNP'

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var lastCombos: (region: HotkeyCombo, ocr: HotkeyCombo, fullscreen: HotkeyCombo)?
    private var isSuspended = false

    public var onTrigger: ((HotkeyAction) -> Void)?

    public init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    @discardableResult
    public func registerAll(
        region: HotkeyCombo,
        ocr: HotkeyCombo,
        fullscreen: HotkeyCombo
    ) -> [HotkeyAction] {
        lastCombos = (region, ocr, fullscreen)
        installHandlerIfNeeded()
        unregisterAll()

        guard !isSuspended else { return [] }

        var failed: [HotkeyAction] = []
        if !register(action: .regionCapture, combo: region) {
            failed.append(.regionCapture)
        }
        if !register(action: .ocrCapture, combo: ocr) {
            failed.append(.ocrCapture)
        }
        if !register(action: .fullscreenCapture, combo: fullscreen) {
            failed.append(.fullscreenCapture)
        }
        return failed
    }

    public func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            unregisterAll()
        } else if let combos = lastCombos {
            _ = registerAll(region: combos.region, ocr: combos.ocr, fullscreen: combos.fullscreen)
        }
    }

    public func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func register(action: HotkeyAction, combo: HotkeyCombo) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            return false
        }
        hotKeyRefs[action] = ref
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == HotkeyManager.signature,
                      let action = HotkeyAction(rawValue: hotKeyID.id) else {
                    return noErr
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onTrigger?(action)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )
        if status == noErr {
            eventHandlerRef = handler
        }
    }
}
