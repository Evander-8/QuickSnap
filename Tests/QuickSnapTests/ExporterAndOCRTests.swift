import AppKit
import CoreGraphics
import XCTest
@testable import QuickSnapCore

final class ExporterAndOCRTests: XCTestCase {
    private func makeTestImage(
        width: Int,
        height: Int,
        flippedDraw: (CGContext) -> Void
    ) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Unable to create CGContext")
        }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        flippedDraw(ctx)

        guard let image = ctx.makeImage() else {
            throw XCTSkip("Unable to make CGImage")
        }
        return image
    }

    func testRenderCroppedImageAtRetinaScaleAndSavePNGAndJPEG() throws {
        // 模拟 2x Retina 屏幕：逻辑 800x600，像素 1600x1200
        let source = try makeTestImage(width: 1600, height: 1200) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            ctx.setFillColor(NSColor.systemTeal.cgColor)
            ctx.fill(CGRect(x: 240, y: 200, width: 320, height: 220))
        }

        let canvasBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selectionRect = CGRect(x: 100, y: 80, width: 400, height: 300)
        let annotations: [AnnotationItem] = [
            AnnotationItem(
                tool: .rectangle,
                color: .red,
                strokeWidth: 4,
                startPoint: CGPoint(x: 120, y: 100),
                endPoint: CGPoint(x: 260, y: 200)
            ),
            AnnotationItem(
                tool: .ellipse,
                color: .blue,
                strokeWidth: 3,
                startPoint: CGPoint(x: 280, y: 110),
                endPoint: CGPoint(x: 420, y: 210)
            ),
            AnnotationItem(
                tool: .arrow,
                color: .green,
                strokeWidth: 5,
                startPoint: CGPoint(x: 140, y: 260),
                endPoint: CGPoint(x: 340, y: 260)
            ),
            AnnotationItem(
                tool: .brush,
                color: .yellow,
                strokeWidth: 4,
                points: [CGPoint(x: 150, y: 310), CGPoint(x: 220, y: 330), CGPoint(x: 300, y: 305)]
            ),
            AnnotationItem(
                tool: .mosaic,
                color: .black,
                strokeWidth: 5,
                points: [CGPoint(x: 140, y: 140), CGPoint(x: 240, y: 160)]
            ),
            AnnotationItem(
                tool: .text,
                color: .black,
                strokeWidth: 4,
                startPoint: CGPoint(x: 310, y: 290),
                text: "QuickSnap",
                fontSize: 20
            ),
            AnnotationItem(
                tool: .highlighter,
                color: .yellow,
                strokeWidth: 4,
                points: [CGPoint(x: 140, y: 210), CGPoint(x: 260, y: 210)]
            ),
            AnnotationItem(
                tool: .stepNumber,
                color: .red,
                strokeWidth: 5,
                startPoint: CGPoint(x: 360, y: 150),
                stepNumber: 1
            )
        ]

        let rendered = try ImageExporter.renderCroppedImage(
            sourceImage: source,
            canvasBounds: canvasBounds,
            selectionRect: selectionRect,
            annotations: annotations
        )

        XCTAssertEqual(rendered.width, 800)
        XCTAssertEqual(rendered.height, 600)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicksnap-export-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngURL = try ImageExporter.saveToFile(rendered, directory: tempDir, format: .png)
        let jpgURL = try ImageExporter.saveToFile(rendered, directory: tempDir, format: .jpeg, jpegQuality: 0.9)

        XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpgURL.path))
        XCTAssertGreaterThan(try Data(contentsOf: pngURL).count, 1000)
        XCTAssertGreaterThan(try Data(contentsOf: jpgURL).count, 1000)
    }

    func testOCRRecognizesEnglishAndChineseTextEndToEnd() async throws {
        let image = try makeTestImage(width: 900, height: 320) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 320))

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            ("QuickSnap OCR Test 2026" as NSString).draw(at: CGPoint(x: 60, y: 70), withAttributes: attrs)
            ("离线文字识别测试" as NSString).draw(at: CGPoint(x: 60, y: 170), withAttributes: attrs)
            NSGraphicsContext.current = previous
        }

        let recognized = try await OCRService.recognizeText(in: image)
        XCTAssertTrue(recognized.contains("QuickSnap"), "Recognized text was: \(recognized)")
        XCTAssertTrue(recognized.contains("2026"), "Recognized text was: \(recognized)")
        XCTAssertTrue(
            recognized.contains("识别") || recognized.contains("文字"),
            "Expected Chinese text in OCR output, got: \(recognized)"
        )
    }

    func testPixelSamplerReadsRGBAndHEXAccurately() throws {
        // 1. 测试标准 sRGB RGBA 布局
        let rgbaImage = try makeTestImage(width: 40, height: 40) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 51.0 / 255.0, green: 102.0 / 255.0, blue: 204.0 / 255.0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }

        let rgbaSampler = try XCTUnwrap(PixelSampler(image: rgbaImage))
        let result = try XCTUnwrap(rgbaSampler.sample(atCanvasPoint: CGPoint(x: 10, y: 10), canvasBounds: CGRect(x: 0, y: 0, width: 20, height: 20)))
        XCTAssertEqual(result.pixelX, 20)
        XCTAssertEqual(result.pixelY, 20)
        XCTAssertEqual(result.color, SampledColor(r: 51, g: 102, b: 204))
        XCTAssertEqual(result.color.hexString, "#3366CC")
        XCTAssertEqual(result.color.rgbString, "RGB(51, 102, 204)")

        // 2. 测试 macOS 屏幕捕获常用的 32-bit little-endian BGRA 布局
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bgraBitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let bgraCtx = try XCTUnwrap(CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: srgb,
            bitmapInfo: bgraBitmapInfo
        ))
        bgraCtx.setFillColor(CGColor(srgbRed: 220.0 / 255.0, green: 80.0 / 255.0, blue: 40.0 / 255.0, alpha: 1))
        bgraCtx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let bgraImage = try XCTUnwrap(bgraCtx.makeImage())
        let bgraSampler = try XCTUnwrap(PixelSampler(image: bgraImage))
        let bgraColor = try XCTUnwrap(bgraSampler.samplePixel(x: 5, y: 5))
        XCTAssertEqual(bgraColor, SampledColor(r: 220, g: 80, b: 40))
        XCTAssertEqual(bgraColor.hexString, "#DC5028")
    }
}
