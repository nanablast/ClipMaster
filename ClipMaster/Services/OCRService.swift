import AppKit
import Vision

enum OCRService {
    private struct OCRPass {
        let name: String
        let languages: [String]?
        let recognitionLevel: VNRequestTextRecognitionLevel
        let usesLanguageCorrection: Bool
    }

    private static let ocrPasses: [OCRPass] = [
        OCRPass(
            name: "mixed-cjk",
            languages: ["zh-Hans", "zh-Hant", "ja-JP", "en-US"],
            recognitionLevel: .accurate,
            usesLanguageCorrection: true
        ),
        OCRPass(
            name: "jp-priority",
            languages: ["ja-JP", "zh-Hans", "zh-Hant", "en-US"],
            recognitionLevel: .accurate,
            usesLanguageCorrection: false
        ),
        OCRPass(
            name: "jp-only",
            languages: ["ja-JP"],
            recognitionLevel: .accurate,
            usesLanguageCorrection: false
        ),
        OCRPass(
            name: "auto-fallback",
            languages: nil,
            recognitionLevel: .accurate,
            usesLanguageCorrection: false
        ),
    ]

    /// Recognize text from image data using macOS Vision framework.
    /// Supports Chinese, Japanese and English. Uses multi-pass fallback.
    /// Returns recognized text or empty string.
    static func recognizeText(from imageData: Data) -> String {
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            debugLog("[ClipMaster OCR] 无法从 imageData 创建 CGImage")
            return ""
        }

        for pass in ocrPasses {
            if let result = recognizeText(cgImage: cgImage, pass: pass),
               !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return result
            }
        }

        debugLog("[ClipMaster OCR] 所有识别策略均未命中")
        return ""
    }

    private static func recognizeText(cgImage: CGImage, pass: OCRPass) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = pass.recognitionLevel
        request.usesLanguageCorrection = pass.usesLanguageCorrection
        if let languages = pass.languages {
            request.recognitionLanguages = languages
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            debugLog("[ClipMaster OCR] pass=\(pass.name) perform 失败: \(error)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            debugLog("[ClipMaster OCR] pass=\(pass.name) 无识别结果")
            return nil
        }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("[ClipMaster OCR] pass=\(pass.name) 识别到 \(lines.count) 行")
        return result.isEmpty ? nil : result
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
