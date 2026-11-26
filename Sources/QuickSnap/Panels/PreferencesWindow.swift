/**
 * [INPUT]: 依赖 AppKit（NSVisualEffectView）、SwiftUI、Carbon、QuickSnapCore（SettingsStore、ScreenCaptureService、LaunchAtLoginService）
 * [OUTPUT]: 提供 PreferencesWindowController（原生 macOS 全透毛玻璃双栏偏好设置窗口）
 * [POS]: Panels 模块的偏好设置中心，采用原生 behindWindow 毛玻璃与半透明玻璃卡片呈现设置项
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import Carbon
import QuickSnapCore
import SwiftUI

private enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case storage
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .storage: return "保存与命名"
        case .shortcuts: return "快捷键"
        case .about: return "关于与提示"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "启动行为、声音反馈与屏幕录制权限"
        case .storage: return "默认输出目录、图像格式与文件命名模板"
        case .shortcuts: return "全局热键配置（基于 Carbon，无需辅助功能权限）"
        case .about: return "快捷手势、隐藏技巧与版本信息"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .storage: return "folder"
        case .shortcuts: return "command"
        case .about: return "sparkles"
        }
    }
}

private struct GlassSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(
                cornerRadius: 20,
                darkTint: Color.white.opacity(0.065),
                lightTint: Color.white.opacity(0.78),
                withBehindWindowBlur: false,
                showShadow: true
            )
        }
    }
}

private struct GlassSwitchRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct GlassInsetDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}

private struct HotkeyRecorderRow: View {
    let title: String
    let subtitle: String
    @Binding var combo: HotkeyCombo
    let onRecordingStateChanged: (Bool) -> Void
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                toggleRecording()
            } label: {
                Text(isRecording ? "按下快捷键 (Esc)" : combo.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .frame(minWidth: 102)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        onRecordingStateChanged(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let carbonMods = HotkeyCombo.carbonModifiers(from: flags)
            guard carbonMods != 0 else {
                NSSound.beep()
                return nil
            }
            combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if isRecording {
            onRecordingStateChanged(false)
        }
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

private struct TokenFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct PreferencesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: SettingsStore
    let onHotkeysUpdated: () -> Void
    let onRecordingStateChanged: (Bool) -> Void

    @State private var selectedTab: PreferencesTab = .general
    @State private var hoveredTab: PreferencesTab?
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var hasPermission = ScreenCaptureService.hasScreenRecordingPermission()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5)
                .ignoresSafeArea()
            detailContent
        }
        .frame(width: 640, height: 440)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
                .frame(height: 28)

            VStack(spacing: 3) {
                ForEach(PreferencesTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    let isHovered = (hoveredTab == tab)

                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: isSelected ? "\(tab.icon).fill" : tab.icon)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width: 20)
                            Text(tab.title)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.80))
                                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(
                                            colors: LiquidGlassTokens.chromaticSwiftUIColors(
                                                for: colorScheme,
                                                opacity: isSelected ? (colorScheme == .dark ? 0.44 : 0.36) : 0
                                            )
                                        ),
                                        center: .center
                                    ),
                                    lineWidth: 0.85
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isSelected ? 0.92 : 0),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 0.9
                                )
                                .padding(0.5)
                        )
                        .shadow(
                            color: Color.black.opacity(isSelected ? (colorScheme == .dark ? 0.22 : 0.07) : 0),
                            radius: 5,
                            y: 2
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("QuickSnap")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text("v1.0.0")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 172)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                NativeVisualEffectBackground(material: .sidebar)
                Color.white.opacity(colorScheme == .dark ? 0 : 0.14)
            }
            .ignoresSafeArea()
        )
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedTab.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(selectedTab.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalPane
                    case .storage:
                        storagePane
                    case .shortcuts:
                        shortcutsPane
                    case .about:
                        aboutPane
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                NativeVisualEffectBackground(material: colorScheme == .dark ? .popover : .sheet)
                Color.white.opacity(colorScheme == .dark ? 0 : 0.50)
            }
            .ignoresSafeArea()
        )
    }

    // MARK: - 通用

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionCard("启动与行为") {
                GlassSwitchRow(
                    "登录时自动启动 QuickSnap",
                    subtitle: "开机后静默常驻顶部菜单栏",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            do {
                                try LaunchAtLoginService.setEnabled(newValue)
                            } catch {
                                launchAtLogin = LaunchAtLoginService.isEnabled
                                ToastPresenter.shared.show(
                                    message: "开机自启设置失败：\(error.localizedDescription)",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                            }
                        }
                    )
                )

                GlassInsetDivider()

                GlassSwitchRow(
                    "截图完成播放提示音",
                    subtitle: "复制、保存或识别完成时播放轻量音效",
                    isOn: $settings.playSound
                )

                GlassInsetDivider()

                GlassSwitchRow(
                    "全屏截图同时自动保存到默认目录",
                    subtitle: "除复制到剪贴板外，按命名规则自动落盘",
                    isOn: $settings.autoSaveOnFullscreen
                )
            }

            GlassSectionCard("隐私与权限") {
                HStack(spacing: 12) {
                    Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(hasPermission ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasPermission ? "屏幕录制权限已授权" : "尚未授予屏幕录制权限")
                            .font(.system(size: 13, weight: .medium))
                        Text(hasPermission ? "可正常捕获多屏画面、识别窗口与执行离线 OCR" : "请前往系统设置开启 QuickSnap 的屏幕录制权限")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新") {
                        hasPermission = ScreenCaptureService.hasScreenRecordingPermission()
                    }
                    .controlSize(.small)

                    if !hasPermission {
                        Button("前往授权") {
                            ScreenCaptureService.requestScreenRecordingPermission()
                            ScreenCaptureService.openScreenRecordingSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - 保存与命名

    private var storagePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionCard("存储与图像格式") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("默认保存目录")
                            .font(.system(size: 13))
                        Text(settings.saveDirectoryPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("在 Finder 中打开") {
                        NSWorkspace.shared.open(settings.saveDirectoryURL)
                    }
                    .controlSize(.small)
                    Button("选择…") {
                        pickSaveDirectory()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GlassInsetDivider()

                HStack {
                    Text("默认导出格式")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if settings.exportFormat == .jpeg {
                    GlassInsetDivider()
                    HStack(spacing: 10) {
                        Text("JPEG 压缩质量")
                            .font(.system(size: 13))
                        Slider(value: $settings.jpegQuality, in: 0.5...1.0, step: 0.05)
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            GlassSectionCard("文件名命名规则") {
                HStack {
                    Text("快捷预设")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.filenameTemplate },
                        set: { settings.filenameTemplate = $0 }
                    )) {
                        ForEach(FilenamePreset.allPresets) { preset in
                            Text(preset.title).tag(preset.template)
                        }
                        if !FilenamePreset.allPresets.contains(where: { $0.template == settings.filenameTemplate }) {
                            Text("自定义模板").tag(settings.filenameTemplate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GlassInsetDivider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("自定义模板")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            settings.filenameTemplate = SettingsStore.defaultFilenameTemplate
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                    }

                    TextField("例如：Screenshot_{yyyy}{MM}{dd}_{HH}{mm}{ss}", text: $settings.filenameTemplate)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )

                    TokenFlowLayout(spacing: 5) {
                        ForEach(FilenameFormatter.supportedTokens, id: \.token) { item in
                            Button {
                                settings.filenameTemplate += item.token
                            } label: {
                                HStack(spacing: 3) {
                                    Text(item.token)
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    Text(item.label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.primary.opacity(0.055))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GlassInsetDivider()

                HStack(spacing: 8) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("预览")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Text(previewFilename)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.025))
            }
        }
    }

    // MARK: - 快捷键

    private var shortcutsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionCard {
                HotkeyRecorderRow(
                    title: "区域截图",
                    subtitle: "悬停自动识别窗口，拖拽框选、标注、取色或贴图",
                    combo: $settings.regionHotkey,
                    onRecordingStateChanged: onRecordingStateChanged
                )
                .onChange(of: settings.regionHotkey) { _, _ in onHotkeysUpdated() }

                GlassInsetDivider()

                HotkeyRecorderRow(
                    title: "OCR 文字识别",
                    subtitle: "选区完成后立即离线识别中英文文字",
                    combo: $settings.ocrHotkey,
                    onRecordingStateChanged: onRecordingStateChanged
                )
                .onChange(of: settings.ocrHotkey) { _, _ in onHotkeysUpdated() }

                GlassInsetDivider()

                HotkeyRecorderRow(
                    title: "全屏截图",
                    subtitle: "直接截取鼠标所在屏幕并复制到剪贴板",
                    combo: $settings.fullscreenHotkey,
                    onRecordingStateChanged: onRecordingStateChanged
                )
                .onChange(of: settings.fullscreenHotkey) { _, _ in onHotkeysUpdated() }
            }

            HStack {
                Spacer()
                Button("恢复全部默认设置") {
                    settings.resetToDefaults()
                    onHotkeysUpdated()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - 关于与提示

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSectionCard {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("QuickSnap v1.0.0")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("纯原生 Swift + ScreenCaptureKit + Vision，零第三方依赖，常驻待机内存约 26–31 MB。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            GlassSectionCard("效率技巧速查") {
                tipRow(key: "单击窗口 / 拖拽", desc: "悬停自动高亮窗口，单击直接捕获；拖拽自由框选")
                GlassInsetDivider()
                tipRow(key: "C  /  Shift", desc: "放大镜预览时按 C 复制色值，Shift 切换 HEX / RGB")
                GlassInsetDivider()
                tipRow(key: "⌘P", desc: "将选区固定为桌面悬浮贴图，支持拖动与滚轮/四角缩放")
                GlassInsetDivider()
                tipRow(key: "⌘S  /  Enter", desc: "⌘S 选路径保存，Enter 或双击选区直接复制")
                GlassInsetDivider()
                tipRow(key: "⌘Z  /  ⌘⇧Z", desc: "撤销与重做标注（序号 ①②③ 自动回退递增）")
            }
        }
    }

    private func tipRow(key: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .frame(minWidth: 114)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var previewFilename: String {
        FilenameFormatter.makeFilename(
            template: settings.filenameTemplate,
            format: settings.exportFormat,
            pixelSize: (1440, 900)
        )
    }

    private func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let onHotkeysUpdated: () -> Void
    private let onRecordingStateChanged: (Bool) -> Void
    var onDismissed: (() -> Void)?

    init(
        settings: SettingsStore,
        onHotkeysUpdated: @escaping () -> Void,
        onRecordingStateChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.settings = settings
        self.onHotkeysUpdated = onHotkeysUpdated
        self.onRecordingStateChanged = onRecordingStateChanged
        super.init()
    }

    func show() {
        if window == nil {
            let view = PreferencesView(
                settings: settings,
                onHotkeysUpdated: onHotkeysUpdated,
                onRecordingStateChanged: onRecordingStateChanged
            )
            let hosting = NSHostingView(rootView: view)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "QuickSnap 偏好设置"
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.contentView = hosting
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        onDismissed?()
    }
}
