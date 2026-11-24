/**
 * [INPUT]: 依赖 AppKit、SwiftUI（OCRResultModel / OCRResultView）
 * [OUTPUT]: 提供 OCRResultWindowController（按需创建的轻量 OCR 结果展示与复制窗口）
 * [POS]: Panels 模块的 OCR 交互出口，关闭后立即销毁以保持低内存占用
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import AppKit
import SwiftUI

@MainActor
final class OCRResultModel: ObservableObject {
    enum State {
        case loading
        case success(String)
        case failure(String)
    }

    @Published var state: State = .loading
    @Published var editableText: String = ""
    @Published var isPinned: Bool = true
    @Published var copiedNotice: Bool = false

    func setLoading() {
        state = .loading
        editableText = ""
        copiedNotice = false
    }

    func setSuccess(_ text: String) {
        state = .success(text)
        editableText = text
        copiedNotice = false
    }

    func setFailure(_ message: String) {
        state = .failure(message)
        editableText = ""
        copiedNotice = false
    }
}

private struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel
    let onTogglePin: (Bool) -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("OCR 文字识别", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                Spacer()
                Toggle(isOn: Binding(
                    get: { model.isPinned },
                    set: { newValue in
                        model.isPinned = newValue
                        onTogglePin(newValue)
                    }
                )) {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("置顶窗口")
            }

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if case .success = model.state {
                    Text("共 \(model.editableText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    onClose()
                }
                .keyboardShortcut(.escape, modifiers: [])

                if case .success = model.state {
                    Button {
                        onCopy(model.editableText)
                    } label: {
                        Label(
                            model.copiedNotice ? "已复制" : "复制全文",
                            systemImage: model.copiedNotice ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 260)
    }

    @ViewBuilder
    private var contentArea: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("正在离线识别文字…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .success:
            TextEditor(text: $model.editableText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

        case .failure(let message):
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

@MainActor
final class OCRResultWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let model = OCRResultModel()
    var onDismissed: (() -> Void)?

    func showLoading() {
        model.setLoading()
        ensurePanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showResult(_ text: String) {
        model.setSuccess(text)
        ensurePanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showError(_ message: String) {
        model.setFailure(message)
        ensurePanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel?.contentView = nil
        panel = nil
        onDismissed?()
    }

    private func ensurePanel() {
        if let panel {
            panel.level = model.isPinned ? .floating : .normal
            return
        }

        let rootView = OCRResultView(
            model: model,
            onTogglePin: { [weak self] pinned in
                self?.panel?.level = pinned ? .floating : .normal
            },
            onCopy: { [weak self] text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self?.model.copiedNotice = true
                ToastPresenter.shared.show(message: "已复制识别文字")
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "OCR 文字识别结果"
        newPanel.level = model.isPinned ? .floating : .normal
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self
        newPanel.contentView = NSHostingView(rootView: rootView)
        newPanel.center()
        panel = newPanel
    }
}
