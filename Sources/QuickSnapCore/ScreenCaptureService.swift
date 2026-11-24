/**
 * [INPUT]: 依赖 ScreenCaptureKit、AppKit（NSScreen）、CoreGraphics（权限检测）
 * [OUTPUT]: 提供 CapturedDisplay 与 ScreenCaptureService（多屏 Retina 截图与屏幕录制权限管理）
 * [POS]: QuickSnapCore 的屏幕捕获边界，屏蔽 ScreenCaptureKit 异步细节与多显示器坐标映射
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct DetectedWindow: Equatable, Sendable {
    public let ownerName: String
    public let frameInDisplay: CGRect

    public init(ownerName: String, frameInDisplay: CGRect) {
        self.ownerName = ownerName
        self.frameInDisplay = frameInDisplay
    }
}

public struct CapturedDisplay: @unchecked Sendable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let backingScaleFactor: CGFloat
    public let image: CGImage
    public let windows: [DetectedWindow]

    public init(
        displayID: CGDirectDisplayID,
        screenFrame: CGRect,
        backingScaleFactor: CGFloat,
        image: CGImage,
        windows: [DetectedWindow] = []
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.backingScaleFactor = backingScaleFactor
        self.image = image
        self.windows = windows
    }
}

public enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplayFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得“屏幕录制”权限，请在系统设置中授权 QuickSnap。"
        case .noDisplayFound:
            return "未检测到可用的显示器。"
        case .captureFailed(let message):
            return "屏幕捕获失败：\(message)"
        }
    }
}

public enum ScreenCaptureService {
    public static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    public static func captureAllDisplays() async throws -> [CapturedDisplay] {
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
            throw ScreenCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }

        let screensByID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
                guard let id = displayID(for: screen) else { return nil }
                return (id, screen)
            }
        )

        let rawWindowInfos = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]) ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        let selfPID = ProcessInfo.processInfo.processIdentifier

        var captured: [CapturedDisplay] = []
        for display in content.displays {
            let screen = screensByID[display.displayID]
            let frame = screen?.frame ?? display.frame
            let scale = screen?.backingScaleFactor ?? 2.0
            let detectedWindows = extractDetectedWindows(
                from: rawWindowInfos,
                displayFrame: frame,
                primaryHeight: primaryHeight,
                excludingPID: selfPID
            )

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = max(1, Int((frame.width * scale).rounded()))
            config.height = max(1, Int((frame.height * scale).rounded()))
            config.showsCursor = false
            config.capturesAudio = false

            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                captured.append(
                    CapturedDisplay(
                        displayID: display.displayID,
                        screenFrame: frame,
                        backingScaleFactor: scale,
                        image: image,
                        windows: detectedWindows
                    )
                )
            } catch {
                throw ScreenCaptureError.captureFailed(error.localizedDescription)
            }
        }

        if captured.isEmpty {
            throw ScreenCaptureError.noDisplayFound
        }
        return captured
    }

    @MainActor
    public static func captureDisplay(containing point: CGPoint) async throws -> CapturedDisplay {
        guard hasScreenRecordingPermission() else {
            requestScreenRecordingPermission()
            throw ScreenCaptureError.permissionDenied
        }

        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        guard let screen = targetScreen, let targetID = displayID(for: screen) else {
            throw ScreenCaptureError.noDisplayFound
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }

        let scale = screen.backingScaleFactor
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(1, Int((screen.frame.width * scale).rounded()))
        config.height = max(1, Int((screen.frame.height * scale).rounded()))
        config.showsCursor = false
        config.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CapturedDisplay(
            displayID: display.displayID,
            screenFrame: screen.frame,
            backingScaleFactor: scale,
            image: image
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func extractDetectedWindows(
        from rawInfos: [[String: Any]],
        displayFrame: CGRect,
        primaryHeight: CGFloat,
        excludingPID: Int32
    ) -> [DetectedWindow] {
        var result: [DetectedWindow] = []
        for info in rawInfos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.01 else { continue }
            if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == excludingPID {
                continue
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let localFrame = SelectionMath.quartzRectToDisplayLocal(
                      bounds,
                      displayScreenFrame: displayFrame,
                      primaryScreenHeight: primaryHeight
                  ) else {
                continue
            }
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? "Window"
            result.append(DetectedWindow(ownerName: ownerName, frameInDisplay: localFrame))
        }
        return result
    }
}
