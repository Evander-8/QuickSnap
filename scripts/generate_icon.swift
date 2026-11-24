#!/usr/bin/env swift
/**
 * [INPUT]: 依赖 AppKit、CoreGraphics
 * [OUTPUT]: 在指定输出目录生成符合 macOS 规范的 AppIcon.iconset 多分辨率 PNG 图标集
 * [POS]: scripts 的图标资产生成工具，为 build_app.sh 提供原生高清图标源
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let iconRect = canvas.insetBy(dx: inset, dy: inset)
    let cornerRadius = iconRect.width * 0.225

    // 1. 圆角矩形背景渐变
    let bgPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [
        NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.26, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.14, green: 0.25, blue: 0.45, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: iconRect.minX, y: iconRect.minY),
            end: CGPoint(x: iconRect.maxX, y: iconRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()

    // 2. 轻微内描边高光
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(max(1, size * 0.014))
    ctx.strokePath()
    ctx.restoreGState()

    // 3. 截图取景框四角括号（亮青蓝色）
    let frameRect = iconRect.insetBy(dx: iconRect.width * 0.21, dy: iconRect.height * 0.21)
    let arm = frameRect.width * 0.28
    let stroke = max(1.5, size * 0.055)

    ctx.saveGState()
    ctx.setStrokeColor(NSColor(calibratedRed: 0.30, green: 0.78, blue: 1.0, alpha: 1).cgColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // 左上
    ctx.move(to: CGPoint(x: frameRect.minX, y: frameRect.maxY - arm))
    ctx.addLine(to: CGPoint(x: frameRect.minX, y: frameRect.maxY))
    ctx.addLine(to: CGPoint(x: frameRect.minX + arm, y: frameRect.maxY))
    // 右上
    ctx.move(to: CGPoint(x: frameRect.maxX - arm, y: frameRect.maxY))
    ctx.addLine(to: CGPoint(x: frameRect.maxX, y: frameRect.maxY))
    ctx.addLine(to: CGPoint(x: frameRect.maxX, y: frameRect.maxY - arm))
    // 右下
    ctx.move(to: CGPoint(x: frameRect.maxX, y: frameRect.minY + arm))
    ctx.addLine(to: CGPoint(x: frameRect.maxX, y: frameRect.minY))
    ctx.addLine(to: CGPoint(x: frameRect.maxX - arm, y: frameRect.minY))
    // 左下
    ctx.move(to: CGPoint(x: frameRect.minX + arm, y: frameRect.minY))
    ctx.addLine(to: CGPoint(x: frameRect.minX, y: frameRect.minY))
    ctx.addLine(to: CGPoint(x: frameRect.minX, y: frameRect.minY + arm))
    ctx.strokePath()

    // 4. 中心 OCR 文字线与扫描焦点点缀
    let lineInset = frameRect.width * 0.22
    let lineLeft = frameRect.minX + lineInset
    let lineRight = frameRect.maxX - lineInset
    let midY = frameRect.midY
    let lineOffset = frameRect.height * 0.14
    let lineStroke = max(1.2, size * 0.038)

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.setLineWidth(lineStroke)

    ctx.move(to: CGPoint(x: lineLeft, y: midY + lineOffset))
    ctx.addLine(to: CGPoint(x: lineRight, y: midY + lineOffset))

    ctx.move(to: CGPoint(x: lineLeft, y: midY))
    ctx.addLine(to: CGPoint(x: lineRight - lineInset * 0.35, y: midY))

    ctx.move(to: CGPoint(x: lineLeft, y: midY - lineOffset))
    ctx.addLine(to: CGPoint(x: lineLeft + (lineRight - lineLeft) * 0.55, y: midY - lineOffset))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

for spec in specs {
    guard let image = renderIcon(pixels: spec.pixels) else {
        fputs("Failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode \(spec.name)\n", stderr)
        exit(1)
    }
    try pngData.write(to: outputDir.appendingPathComponent(spec.name))
}
