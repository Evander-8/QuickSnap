/**
 * [INPUT]: 依赖 AppKit、QuickSnapCore（ScreenCaptureService、ImageExporter、OCRService、SettingsStore）与 Panels
 * [OUTPUT]: 提供 CaptureCoordinator（多屏截图会话协调、防重入保护、OCR 流程与严格内存清理）
 * [POS]: CaptureUI 的总控协调器，保证待机态零残留窗口或位图内存
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import QuickSnapCore

@MainActor
final class CaptureCoordinator {
    private let settings: SettingsStore
    private let pinManager = PinManager()
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var canvasViews: [CaptureCanvasView] = []
    private var ocrWindowController: OCRResultWindowController?
    private(set) var isCapturing = false

    var onPinCountChanged: ((Int) -> Void)? {
        get { pinManager.onCountChanged }
        set { pinManager.onCountChanged = newValue }
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func closeAllPins() {
        pinManager.closeAll()
    }

    func startRegionCapture(mode: CaptureMode = .standard) {
        guard !isCapturing else {
            overlayWindows.first?.makeKeyAndOrderFront(nil)
            return
        }
        isCapturing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let displays = try await ScreenCaptureService.captureAllDisplays()
                self.presentOverlays(for: displays, mode: mode)
            } catch {
                self.isCapturing = false
                self.handleCaptureError(error)
            }
        }
    }

    func captureFullscreen() {
        guard !isCapturing else { return }
        isCapturing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }

            do {
                let mouseLocation = NSEvent.mouseLocation
                let display = try await ScreenCaptureService.captureDisplay(containing: mouseLocation)
                ImageExporter.copyToPasteboard(display.image)

                if self.settings.autoSaveOnFullscreen {
                    let url = try ImageExporter.saveToFile(
                        display.image,
                        directory: self.settings.saveDirectoryURL,
                        format: self.settings.exportFormat,
                        jpegQuality: self.settings.jpegQuality,
                        filenameTemplate: self.settings.filenameTemplate
                    )
                    self.playShutterSoundIfEnabled()
                    ToastPresenter.shared.show(message: "已复制并保存 \(url.lastPathComponent)")
                } else {
                    self.playShutterSoundIfEnabled()
                    ToastPresenter.shared.show(message: "全屏截图已复制到剪贴板")
                }
            } catch {
                self.handleCaptureError(error)
            }
        }
    }

    func dismissAll() {
        for canvas in canvasViews {
            canvas.cleanup()
        }
        canvasViews.removeAll()

        for window in overlayWindows {
            window.contentView = nil
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        isCapturing = false
    }

    private func presentOverlays(for displays: [CapturedDisplay], mode: CaptureMode) {
        let mouseLocation = NSEvent.mouseLocation
        var primaryWindow: CaptureOverlayWindow?

        for display in displays {
            let window = CaptureOverlayWindow(screenFrame: display.screenFrame)
            let canvasBounds = CGRect(origin: .zero, size: display.screenFrame.size)
            let canvas = CaptureCanvasView(frame: canvasBounds, display: display, mode: mode)

            canvas.onSelectionBegan = { [weak self, weak canvas] in
                guard let self, let activeCanvas = canvas else { return }
                for sibling in self.canvasViews where sibling !== activeCanvas {
                    sibling.clearSelectionFromSibling()
                }
            }
            canvas.onCancel = { [weak self] in
                self?.dismissAll()
            }
            canvas.onRequestCopy = { [weak self, weak canvas] rect, annotations, mosaic in
                guard let self, let canvas else { return }
                self.handleCopy(canvas: canvas, rect: rect, annotations: annotations, mosaic: mosaic)
            }
            canvas.onRequestSave = { [weak self, weak canvas] rect, annotations, mosaic in
                guard let self, let canvas else { return }
                self.handleSave(canvas: canvas, rect: rect, annotations: annotations, mosaic: mosaic)
            }
            canvas.onRequestPin = { [weak self, weak canvas] rect, annotations, mosaic in
                guard let self, let canvas else { return }
                self.handlePin(canvas: canvas, rect: rect, annotations: annotations, mosaic: mosaic)
            }
            canvas.onRequestOCR = { [weak self, weak canvas] rect, annotations, mosaic in
                guard let self, let canvas else { return }
                self.handleOCR(canvas: canvas, rect: rect, annotations: annotations, mosaic: mosaic)
            }

            window.contentView = canvas
            window.orderFrontRegardless()
            overlayWindows.append(window)
            canvasViews.append(canvas)

            if display.screenFrame.contains(mouseLocation) {
                primaryWindow = window
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        (primaryWindow ?? overlayWindows.first)?.makeKeyAndOrderFront(nil)
    }

    private func handleCopy(
        canvas: CaptureCanvasView,
        rect: CGRect,
        annotations: [AnnotationItem],
        mosaic: CGImage?
    ) {
        do {
            let output = try ImageExporter.renderCroppedImage(
                sourceImage: canvas.display.image,
                canvasBounds: canvas.bounds,
                selectionRect: rect,
                annotations: annotations,
                mosaicThumbnail: mosaic
            )
            dismissAll()
            ImageExporter.copyToPasteboard(output)
            playShutterSoundIfEnabled()
            ToastPresenter.shared.show(message: "已复制到剪贴板")
        } catch {
            dismissAll()
            ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func handleSave(
        canvas: CaptureCanvasView,
        rect: CGRect,
        annotations: [AnnotationItem],
        mosaic: CGImage?
    ) {
        do {
            let output = try ImageExporter.renderCroppedImage(
                sourceImage: canvas.display.image,
                canvasBounds: canvas.bounds,
                selectionRect: rect,
                annotations: annotations,
                mosaicThumbnail: mosaic
            )
            dismissAll()
            InteractiveSaver.save(image: output, settings: settings)
        } catch {
            dismissAll()
            ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func handlePin(
        canvas: CaptureCanvasView,
        rect: CGRect,
        annotations: [AnnotationItem],
        mosaic: CGImage?
    ) {
        do {
            let clamped = SelectionMath.clampedRect(rect, to: canvas.bounds, minSize: 2)
            let output = try ImageExporter.renderCroppedImage(
                sourceImage: canvas.display.image,
                canvasBounds: canvas.bounds,
                selectionRect: clamped,
                annotations: annotations,
                mosaicThumbnail: mosaic
            )
            let globalFrame = SelectionMath.appKitGlobalFrame(
                for: clamped,
                in: canvas.display.screenFrame
            )
            dismissAll()
            pinManager.pin(
                image: output,
                initialFrame: globalFrame,
                settings: settings,
                onRequestOCR: { [weak self] pinnedImage in
                    self?.runOCR(on: pinnedImage)
                }
            )
            playShutterSoundIfEnabled()
            ToastPresenter.shared.show(message: "已固定到屏幕（滚轮可缩放）", systemImage: "pin.fill")
        } catch {
            dismissAll()
            ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func handleOCR(
        canvas: CaptureCanvasView,
        rect: CGRect,
        annotations: [AnnotationItem],
        mosaic: CGImage?
    ) {
        let croppedImage: CGImage
        do {
            croppedImage = try ImageExporter.renderCroppedImage(
                sourceImage: canvas.display.image,
                canvasBounds: canvas.bounds,
                selectionRect: rect,
                annotations: annotations,
                mosaicThumbnail: mosaic
            )
        } catch {
            dismissAll()
            ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
            return
        }

        // 先销毁所有全屏遮罩窗口与原图，仅保留裁出的小图给 Vision
        dismissAll()
        runOCR(on: croppedImage)
    }

    private func runOCR(on image: CGImage) {
        let controller = ensureOCRWindowController()
        controller.showLoading()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await OCRService.recognizeText(in: image)
                self.playShutterSoundIfEnabled()
                self.ocrWindowController?.showResult(text)
            } catch {
                self.ocrWindowController?.showError(error.localizedDescription)
            }
        }
    }

    private func ensureOCRWindowController() -> OCRResultWindowController {
        if let existing = ocrWindowController {
            return existing
        }
        let controller = OCRResultWindowController()
        controller.onDismissed = { [weak self] in
            self?.ocrWindowController = nil
        }
        ocrWindowController = controller
        return controller
    }

    private func playShutterSoundIfEnabled() {
        guard settings.playSound else { return }
        NSSound(named: "Tink")?.play()
    }

    private func handleCaptureError(_ error: Error) {
        if case ScreenCaptureError.permissionDenied = error {
            let alert = NSAlert()
            alert.messageText = "需要“屏幕录制”权限"
            alert.informativeText = "请前往“系统设置 → 隐私与安全性 → 屏幕录制”开启 QuickSnap 权限后重试。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后再说")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                ScreenCaptureService.openScreenRecordingSettings()
            }
            return
        }
        ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
    }
}
