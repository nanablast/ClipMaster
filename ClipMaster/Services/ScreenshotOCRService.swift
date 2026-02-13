import AppKit

enum ScreenshotOCRService {
    /// Launches macOS interactive region capture, OCRs the result,
    /// and places the recognized text on the clipboard.
    static func captureAndOCR() {
        let tempPath = NSTemporaryDirectory() + "clipmaster_ocr_\(UUID().uuidString).png"

        // screencapture -i: interactive region select, -s: selection only
        // -t png: format, -x: no sound
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", tempPath]

        process.terminationHandler = { proc in
            defer { try? FileManager.default.removeItem(atPath: tempPath) }

            guard proc.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: tempPath),
                  let imageData = try? Data(contentsOf: URL(fileURLWithPath: tempPath))
            else {
                // User cancelled or screencapture failed
                return
            }

            let text = OCRService.recognizeText(from: imageData)

            DispatchQueue.main.async {
                if text.isEmpty {
                    ToastService.shared.show(
                        message: "OCR 未识别到文字",
                        systemImage: "xmark.circle.fill",
                        tintColor: .systemOrange
                    )
                    NSSound.beep()
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    ToastService.shared.show(
                        message: "OCR 已复制（\(text.count) 字）",
                        systemImage: "checkmark.circle.fill",
                        tintColor: .systemGreen
                    )
                }
            }
        }

        do {
            try process.run()
        } catch {
            AppLogger.ocr.error("screencapture launch failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async {
                ToastService.shared.show(
                    message: "OCR 启动失败",
                    systemImage: "exclamationmark.triangle.fill",
                    tintColor: .systemRed
                )
            }
        }
    }
}
