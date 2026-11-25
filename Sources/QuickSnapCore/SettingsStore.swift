/**
 * [INPUT]: 依赖 Foundation、AppKit（NSEvent.ModifierFlags）、Carbon（修饰键与虚拟键码常量）
 * [OUTPUT]: 提供 ExportFormat、HotkeyCombo 与 SettingsStore 配置持久化类
 * [POS]: QuickSnapCore 的全局配置中心，为快捷键绑定、导出格式与默认保存路径提供唯一数据源
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import Carbon
import Foundation
import UniformTypeIdentifiers

public enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case png
    case jpeg

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
}

public struct HotkeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // ⌃1 (kVK_ANSI_1 = 0x12)
    public static let defaultRegionCapture = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_1),
        modifiers: UInt32(controlKey)
    )

    // ⌃2 (kVK_ANSI_2 = 0x13)
    public static let defaultOCRCapture = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(controlKey)
    )

    // ⌃3 (kVK_ANSI_3 = 0x14)
    public static let defaultFullscreenCapture = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_3),
        modifiers: UInt32(controlKey)
    )

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    public var displayString: String {
        var parts = ""
        if (modifiers & UInt32(controlKey)) != 0 { parts += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { parts += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { parts += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { parts += "⌘" }
        parts += Self.keyName(for: keyCode)
        return parts
    }

    public static func keyName(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        return map[keyCode] ?? "Key(\(keyCode))"
    }
}

public struct FilenamePreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let template: String

    public init(id: String, title: String, template: String) {
        self.id = id
        self.title = title
        self.template = template
    }

    public static let allPresets: [FilenamePreset] = [
        FilenamePreset(id: "default", title: "默认时间戳", template: "Screenshot_{yyyy}{MM}{dd}_{HH}{mm}{ss}"),
        FilenamePreset(id: "iso", title: "短横线日期", template: "QuickSnap_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}"),
        FilenamePreset(id: "chinese", title: "中文日期", template: "截图_{yyyy}-{MM}-{dd}_{HH}{mm}{ss}"),
        FilenamePreset(id: "dimensions", title: "含像素尺寸", template: "Snap_{yyyy}{MM}{dd}_{W}x{H}")
    ]
}

public enum FilenameFormatter {
    public static let supportedTokens: [(token: String, label: String)] = [
        ("{yyyy}", "年"),
        ("{MM}", "月"),
        ("{dd}", "日"),
        ("{HH}", "时"),
        ("{mm}", "分"),
        ("{ss}", "秒"),
        ("{W}", "宽"),
        ("{H}", "高"),
        ("{unix}", "时间戳")
    ]

    public static func makeBaseName(
        template: String,
        date: Date = Date(),
        pixelSize: (width: Int, height: Int)? = nil
    ) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let replacements: [(String, String)] = [
            ("{yyyy}", String(format: "%04d", comps.year ?? 2026)),
            ("{MM}", String(format: "%02d", comps.month ?? 1)),
            ("{dd}", String(format: "%02d", comps.day ?? 1)),
            ("{HH}", String(format: "%02d", comps.hour ?? 0)),
            ("{mm}", String(format: "%02d", comps.minute ?? 0)),
            ("{ss}", String(format: "%02d", comps.second ?? 0)),
            ("{W}", "\(max(0, pixelSize?.width ?? 0))"),
            ("{H}", "\(max(0, pixelSize?.height ?? 0))"),
            ("{unix}", "\(Int(date.timeIntervalSince1970))")
        ]

        var result = template
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }

        // 剥离误输入的扩展名后缀与非法文件名字符
        for ext in [".png", ".jpg", ".jpeg"] where result.lowercased().hasSuffix(ext) {
            result = String(result.dropLast(ext.count))
        }
        let illegalChars = CharacterSet(charactersIn: "/\\:\0\n\r")
        result = result.components(separatedBy: illegalChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") {
            result.removeFirst()
        }

        if result.isEmpty {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyyMMdd_HHmmss"
            return "Screenshot_\(fallbackFormatter.string(from: date))"
        }
        return result
    }

    public static func makeFilename(
        template: String,
        format: ExportFormat,
        date: Date = Date(),
        pixelSize: (width: Int, height: Int)? = nil
    ) -> String {
        "\(makeBaseName(template: template, date: date, pixelSize: pixelSize)).\(format.fileExtension)"
    }
}

public final class SettingsStore: ObservableObject {
    public static let defaultFilenameTemplate = "Screenshot_{yyyy}{MM}{dd}_{HH}{mm}{ss}"

    private enum Keys {
        static let saveDirectoryPath = "quicksnap.saveDirectoryPath"
        static let exportFormat = "quicksnap.exportFormat"
        static let jpegQuality = "quicksnap.jpegQuality"
        static let filenameTemplate = "quicksnap.filenameTemplate"
        static let playSound = "quicksnap.playSound"
        static let autoSaveOnFullscreen = "quicksnap.autoSaveOnFullscreen"
        static let regionHotkey = "quicksnap.hotkey.region"
        static let ocrHotkey = "quicksnap.hotkey.ocr"
        static let fullscreenHotkey = "quicksnap.hotkey.fullscreen"
    }

    private let defaults: UserDefaults

    @Published public var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: Keys.saveDirectoryPath) }
    }

    @Published public var exportFormat: ExportFormat {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    @Published public var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: Keys.jpegQuality) }
    }

    @Published public var filenameTemplate: String {
        didSet { defaults.set(filenameTemplate, forKey: Keys.filenameTemplate) }
    }

    @Published public var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }

    @Published public var autoSaveOnFullscreen: Bool {
        didSet { defaults.set(autoSaveOnFullscreen, forKey: Keys.autoSaveOnFullscreen) }
    }

    @Published public var regionHotkey: HotkeyCombo {
        didSet { Self.saveCombo(regionHotkey, forKey: Keys.regionHotkey, in: defaults) }
    }

    @Published public var ocrHotkey: HotkeyCombo {
        didSet { Self.saveCombo(ocrHotkey, forKey: Keys.ocrHotkey, in: defaults) }
    }

    @Published public var fullscreenHotkey: HotkeyCombo {
        didSet { Self.saveCombo(fullscreenHotkey, forKey: Keys.fullscreenHotkey, in: defaults) }
    }

    public var saveDirectoryURL: URL {
        URL(fileURLWithPath: (saveDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultDesktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask)
            .first?.path ?? ("~/Desktop" as NSString).expandingTildeInPath

        self.saveDirectoryPath = defaults.string(forKey: Keys.saveDirectoryPath) ?? defaultDesktop
        if let rawFormat = defaults.string(forKey: Keys.exportFormat),
           let parsedFormat = ExportFormat(rawValue: rawFormat) {
            self.exportFormat = parsedFormat
        } else {
            self.exportFormat = .png
        }

        let storedQuality = defaults.object(forKey: Keys.jpegQuality) as? Double
        self.jpegQuality = storedQuality ?? 0.92
        self.filenameTemplate = defaults.string(forKey: Keys.filenameTemplate) ?? Self.defaultFilenameTemplate

        if let storedSound = defaults.object(forKey: Keys.playSound) as? Bool {
            self.playSound = storedSound
        } else {
            self.playSound = true
        }

        self.autoSaveOnFullscreen = defaults.bool(forKey: Keys.autoSaveOnFullscreen)
        self.regionHotkey = Self.loadCombo(forKey: Keys.regionHotkey, in: defaults) ?? .defaultRegionCapture
        self.ocrHotkey = Self.loadCombo(forKey: Keys.ocrHotkey, in: defaults) ?? .defaultOCRCapture
        self.fullscreenHotkey = Self.loadCombo(forKey: Keys.fullscreenHotkey, in: defaults) ?? .defaultFullscreenCapture
    }

    public func resetToDefaults() {
        let defaultDesktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask)
            .first?.path ?? ("~/Desktop" as NSString).expandingTildeInPath
        saveDirectoryPath = defaultDesktop
        exportFormat = .png
        jpegQuality = 0.92
        filenameTemplate = Self.defaultFilenameTemplate
        playSound = true
        autoSaveOnFullscreen = false
        regionHotkey = .defaultRegionCapture
        ocrHotkey = .defaultOCRCapture
        fullscreenHotkey = .defaultFullscreenCapture
    }

    private static func saveCombo(_ combo: HotkeyCombo, forKey key: String, in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCombo(forKey key: String, in defaults: UserDefaults) -> HotkeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyCombo.self, from: data)
    }
}
