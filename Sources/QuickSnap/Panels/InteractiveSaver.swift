/**
 * [INPUT]: 依赖 AppKit（NSSavePanel）、CoreGraphics、UniformTypeIdentifiers、QuickSnapCore（ImageExporter、SettingsStore）
 * [OUTPUT]: 提供 InteractiveSaver（弹出系统保存对话框选择路径并保存截图）
 * [POS]: Panels 模块的交互式保存助手，供截图画布与固定贴图共用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import QuickSnapCore
import UniformTypeIdentifiers

@MainActor
enum InteractiveSaver {
    @discardableResult
    static func save(image: CGImage, settings: SettingsStore) -> URL? {
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.directoryURL = settings.saveDirectoryURL
        panel.nameFieldStringValue = FilenameFormatter.makeFilename(
            template: settings.filenameTemplate,
            format: settings.exportFormat,
            pixelSize: (image.width, image.height)
        )
        panel.allowedContentTypes = settings.exportFormat == .jpeg ? [.jpeg, .png] : [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        let chosenFormat: ExportFormat = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
        let directory = url.deletingLastPathComponent()

        do {
            let savedURL = try ImageExporter.saveToFile(
                image,
                directory: directory,
                format: chosenFormat,
                jpegQuality: settings.jpegQuality,
                customURL: url
            )
            settings.saveDirectoryPath = directory.path
            if settings.playSound {
                NSSound(named: "Tink")?.play()
            }
            ToastPresenter.shared.show(message: "已保存 \(savedURL.lastPathComponent)")
            return savedURL
        } catch {
            ToastPresenter.shared.show(message: error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
            return nil
        }
    }
}
