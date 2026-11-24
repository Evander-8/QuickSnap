/**
 * [INPUT]: 依赖 Vision（VNRecognizeTextRequest）与 CoreGraphics（CGImage）
 * [OUTPUT]: 提供 OCRError 与 OCRService（离线中英混排文字识别及阅读行序拼接）
 * [POS]: QuickSnapCore 的离线 OCR 引擎，运行在后台线程并及时释放图像推理缓存
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import CoreGraphics
import Foundation
import Vision

public enum OCRError: Error, LocalizedError {
    case emptyResult
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyResult:
            return "未在选区内识别到有效文字。"
        case .recognitionFailed(let reason):
            return "文字识别失败：\(reason)"
        }
    }
}

public enum OCRService {
    public static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    throw OCRError.recognitionFailed(error.localizedDescription)
                }

                let observations = request.results ?? []
                let text = formatObservations(observations)
                guard !text.isEmpty else {
                    throw OCRError.emptyResult
                }
                return text
            }
        }.value
    }

    private static func formatObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        struct LineCandidate {
            let text: String
            let box: CGRect
        }

        let candidates: [LineCandidate] = observations.compactMap { observation in
            guard let top = observation.topCandidates(1).first else { return nil }
            let trimmed = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LineCandidate(text: trimmed, box: observation.boundingBox)
        }

        // Vision boundingBox 原点在左下角：先按 midY 从高到低排序（即自上而下）
        let sortedByY = candidates.sorted { $0.box.midY > $1.box.midY }
        var lines: [[LineCandidate]] = []

        for item in sortedByY {
            if let lastLine = lines.last, let anchor = lastLine.first {
                let tolerance = max(anchor.box.height, item.box.height) * 0.55
                if abs(anchor.box.midY - item.box.midY) <= tolerance {
                    lines[lines.count - 1].append(item)
                    continue
                }
            }
            lines.append([item])
        }

        return lines
            .map { line in
                line.sorted { $0.box.minX < $1.box.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
