/**
 * [INPUT]: 依赖 AppKit、Combine、QuickSnapCore（SettingsStore、HotkeyManager、ScreenCaptureService）、CaptureUI、Panels
 * [OUTPUT]: 提供 AppDelegate（菜单栏常驻图标、菜单项同步、全局热键绑定与生命周期清理）
 * [POS]: QuickSnap 应用壳的入口控制器，连接系统菜单栏/热键与 CaptureCoordinator
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import Combine
import QuickSnapCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let hotkeyManager = HotkeyManager()
    private lazy var coordinator = CaptureCoordinator(settings: settings)

    private var statusItem: NSStatusItem?
    private var regionMenuItem: NSMenuItem?
    private var ocrMenuItem: NSMenuItem?
    private var fullscreenMenuItem: NSMenuItem?
    private var closePinsMenuItem: NSMenuItem?
    private var preferencesController: PreferencesWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var systemObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotkeys()
        observeSettings()
        observeSystemLifecycle()
        coordinator.onPinCountChanged = { [weak self] count in
            self?.updateClosePinsMenuItem(count: count)
        }

        // 开机自启时 WindowServer 可能尚未就绪，2.5 秒后静默补注册一次热键
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.reregisterHotkeys(silent: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeSystemObservers()
        coordinator.resetIfStuck()
        coordinator.closeAllPins()
        hotkeyManager.unregisterAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "QuickSnap")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "QuickSnap 截图与 OCR"
        }

        let menu = NSMenu()
        let regionItem = NSMenuItem(title: "", action: #selector(triggerRegionCapture), keyEquivalent: "")
        regionItem.target = self
        regionMenuItem = regionItem

        let ocrItem = NSMenuItem(title: "", action: #selector(triggerOCRCapture), keyEquivalent: "")
        ocrItem.target = self
        ocrMenuItem = ocrItem

        let fullscreenItem = NSMenuItem(title: "", action: #selector(triggerFullscreenCapture), keyEquivalent: "")
        fullscreenItem.target = self
        fullscreenMenuItem = fullscreenItem

        let closePinsItem = NSMenuItem(title: "关闭所有固定贴图", action: #selector(closeAllPins), keyEquivalent: "")
        closePinsItem.target = self
        closePinsItem.isHidden = true
        closePinsMenuItem = closePinsItem

        let prefsItem = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self

        let permissionItem = NSMenuItem(title: "检查屏幕录制权限", action: #selector(checkPermission), keyEquivalent: "")
        permissionItem.target = self

        let quitItem = NSMenuItem(title: "退出 QuickSnap", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(regionItem)
        menu.addItem(ocrItem)
        menu.addItem(fullscreenItem)
        menu.addItem(closePinsItem)
        menu.addItem(.separator())
        menu.addItem(prefsItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        refreshMenuTitles()
    }

    private func setupHotkeys() {
        hotkeyManager.onTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .regionCapture:
                self.coordinator.startRegionCapture(mode: .standard)
            case .ocrCapture:
                self.coordinator.startRegionCapture(mode: .ocr)
            case .fullscreenCapture:
                self.coordinator.captureFullscreen()
            }
        }
        reregisterHotkeys()
    }

    private func reregisterHotkeys(silent: Bool = false) {
        let failed = hotkeyManager.registerAll(
            region: settings.regionHotkey,
            ocr: settings.ocrHotkey,
            fullscreen: settings.fullscreenHotkey
        )
        refreshMenuTitles()
        if !silent && !failed.isEmpty {
            let names = failed.map(\.title).joined(separator: "、")
            ToastPresenter.shared.show(
                message: "快捷键被占用：\(names)",
                systemImage: "keyboard.badge.ellipsis"
            )
        }
    }

    private func observeSystemLifecycle() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        let distCenter = DistributedNotificationCenter.default()

        let wakeHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.coordinator.resetIfStuck()
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.reregisterHotkeys(silent: true)
            }
        }

        let resetHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.resetIfStuck()
            }
        }

        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: resetHandler))
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wakeHandler))
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wakeHandler))
        systemObservers.append(wsCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: wakeHandler))
        systemObservers.append(appCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: resetHandler))

        distributedObservers.append(
            distCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main,
                using: wakeHandler
            )
        )
    }

    private func removeSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        let distCenter = DistributedNotificationCenter.default()

        for token in systemObservers {
            wsCenter.removeObserver(token)
            appCenter.removeObserver(token)
        }
        systemObservers.removeAll()

        for token in distributedObservers {
            distCenter.removeObserver(token)
        }
        distributedObservers.removeAll()
    }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshMenuTitles()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshMenuTitles() {
        regionMenuItem?.title = "区域截图   \(settings.regionHotkey.displayString)"
        ocrMenuItem?.title = "OCR 文字识别   \(settings.ocrHotkey.displayString)"
        fullscreenMenuItem?.title = "全屏截图   \(settings.fullscreenHotkey.displayString)"
    }

    @objc private func triggerRegionCapture() {
        coordinator.startRegionCapture(mode: .standard)
    }

    @objc private func triggerOCRCapture() {
        coordinator.startRegionCapture(mode: .ocr)
    }

    @objc private func triggerFullscreenCapture() {
        coordinator.captureFullscreen()
    }

    @objc private func closeAllPins() {
        coordinator.closeAllPins()
    }

    private func updateClosePinsMenuItem(count: Int) {
        closePinsMenuItem?.isHidden = (count == 0)
        closePinsMenuItem?.title = "关闭所有固定贴图 (\(count))"
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            let controller = PreferencesWindowController(
                settings: settings,
                onHotkeysUpdated: { [weak self] in
                    self?.reregisterHotkeys()
                },
                onRecordingStateChanged: { [weak self] recording in
                    self?.hotkeyManager.setSuspended(recording)
                }
            )
            controller.onDismissed = { [weak self] in
                self?.hotkeyManager.setSuspended(false)
                self?.preferencesController = nil
            }
            preferencesController = controller
        }
        preferencesController?.show()
    }

    @objc private func checkPermission() {
        if ScreenCaptureService.hasScreenRecordingPermission() {
            ToastPresenter.shared.show(message: "屏幕录制权限已正常开启", systemImage: "checkmark.shield.fill")
        } else {
            ScreenCaptureService.requestScreenRecordingPermission()
            let alert = NSAlert()
            alert.messageText = "尚未授予“屏幕录制”权限"
            alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕录制”中勾选 QuickSnap。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                ScreenCaptureService.openScreenRecordingSettings()
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
