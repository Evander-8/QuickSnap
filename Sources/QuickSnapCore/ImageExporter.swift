/**
 * [INPUT]: 依赖 CoreGraphics、ImageIO、AppKit（NSPasteboard）、AnnotationModels、AnnotationRenderer
 * [OUTPUT]: 提供 ImageExporter（Retina 原生分辨率裁剪、标注合成、剪贴板写入与文件保存）
 * [POS]: QuickSnapCore 的图像输出出口，将矢量标注与原图合成为高清位图
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExportError: Error, LocalizedError {
    case invalidSelection
    case cropFailed
    case encodeFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "截图选区过小或无效。"
        case .cropFailed:
            return "图像裁剪或合成失败。"
        case .encodeFailed:
            return "图像编码失败。"
        case .writeFailed(let message):
            return "写入文件失败：\(message)"
        }
    }
}

public enum ImageExporter {
    public static func renderCroppedImage(
        sourceImage: CGImage,
        canvasBounds: CGRect,
        selectionRect: CGRect,
        annotations: [AnnotationItem],
        mosaicThumbnail: CGImage? = nil
    ) throws -> CGImage {
        let clamped = SelectionMath.clampedRect(selectionRect, to: canvasBounds, minSize: 2)
        guard clamped.width >= 2, clamped.height >= 2,
              canvasBounds.width > 0, canvasBounds.height > 0 else {
            throw ImageExportError.invalidSelection
        }

        let scaleX = CGFloat(sourceImage.width) / canvasBounds.width
        let scaleY = CGFloat(sourceImage.height) / canvasBounds.height

        let pixelX = max(0, Int((clamped.minX * scaleX).rounded(.down)))
        let pixelY = max(0, Int((clamped.minY * scaleY).rounded(.down)))
        let pixelW = min(sourceImage.width - pixelX, max(1, Int((clamped.width * scaleX).rounded())))
        let pixelH = min(sourceImage.height - pixelY, max(1, Int((clamped.height * scaleY).rounded())))

        let pixelCropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)
        guard let cropped = sourceImage.cropping(to: pixelCropRect) else {
            throw ImageExportError.cropFailed
        }

        if annotations.isEmpty {
            return cropped
        }

        let colorSpace = sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageExportError.cropFailed
        }

        // 先在标准底原点下正向绘制裁剪背景
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        // 切换至与画布一致的左上角原点逻辑坐标系并按 Retina 缩放绘制矢量标注
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelH))
        context.scaleBy(x: scaleX, y: -scaleY)
        context.translateBy(x: -clamped.minX, y: -clamped.minY)

        let needsMosaic = annotations.contains(where: { $0.tool == .mosaic })
        let effectiveMosaic = mosaicThumbnail ?? (needsMosaic ? AnnotationRenderer.makeMosaicThumbnail(from: sourceImage) : nil)
        AnnotationRenderer.draw(
            annotations: annotations,
            in: context,
            mosaicThumbnail: effectiveMosaic,
            sourceImage: sourceImage,
            canvasBounds: canvasBounds
        )
        context.restoreGState()

        guard let composed = context.makeImage() else {
            throw ImageExportError.cropFailed
        }
        return composed
    }

    public static func copyToPasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let pngData = encodeImageData(image, format: .png) {
            let item = NSPasteboardItem()
            item.setData(pngData, forType: .png)
            if let tiffData = nsImage.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
            pasteboard.writeObjects([item])
        } else {
            pasteboard.writeObjects([nsImage])
        }
    }

    @discardableResult
    public static func saveToFile(
        _ image: CGImage,
        directory: URL,
        format: ExportFormat,
        jpegQuality: Double = 0.92,
        filenameTemplate: String = SettingsStore.defaultFilenameTemplate,
        customURL: URL? = nil
    ) throws -> URL {
        let destinationURL: URL
        if let customURL {
            destinationURL = customURL
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            destinationURL = uniqueFileURL(
                in: directory,
                format: format,
                filenameTemplate: filenameTemplate,
                pixelSize: (image.width, image.height)
            )
        }

        let targetType = format.utType.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            targetType,
            1,
            nil
        ) else {
            throw ImageExportError.writeFailed(destinationURL.path)
        }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0.1), 1.0)
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageExportError.encodeFailed
        }
        return destinationURL
    }

    public static func encodeImageData(
        _ image: CGImage,
        format: ExportFormat,
        jpegQuality: Double = 0.92
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0.1), 1.0)
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func uniqueFileURL(
        in directory: URL,
        format: ExportFormat,
        filenameTemplate: String,
        pixelSize: (width: Int, height: Int)
    ) -> URL {
        let baseName = FilenameFormatter.makeBaseName(
            template: filenameTemplate,
            date: Date(),
            pixelSize: pixelSize
        )
        let ext = format.fileExtension

        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}
