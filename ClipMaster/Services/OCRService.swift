import AppKit
import Vision

enum OCRService {
    /// Recognize text from image data using macOS Vision framework.
    /// Supports Chinese and English. Returns recognized text or empty string.
    static func recognizeText(from imageData: Data) -> String {
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            debugLog("[ClipMaster OCR] 无法从 imageData 创建 CGImage")
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            debugLog("[ClipMaster OCR] perform 失败: \(error)")
            return ""
        }

        guard let observations = request.results, !observations.isEmpty else {
            debugLog("[ClipMaster OCR] 无识别结果")
            return ""
        }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let result = lines.joined(separator: "\n")
        debugLog("[ClipMaster OCR] 识别到 \(lines.count) 行文字")
        return result
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        guard shouldWriteDebugLog else { return }
        let value = message()
        AppLogger.ocr.debug("\(value, privacy: .public)")
    }

    private static var shouldWriteDebugLog: Bool {
#if DEBUG
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.debugLoggingEnabled)
#else
        false
#endif
    }
}
