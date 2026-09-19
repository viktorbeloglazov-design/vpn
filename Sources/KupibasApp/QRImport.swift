import AppKit
import CoreImage
import Foundation

/// Чтение QR-кодов с картинок.
///
/// Код приходит человеку картинкой в мессенджере: её либо сохраняют файлом и
/// перетаскивают в окно, либо копируют и вставляют. Камера здесь не нужна —
/// на компьютере код всегда оказывается в виде изображения.
enum QRImport {

    /// Расширения, которые имеет смысл проверять на QR-код.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "pdf",
    ]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Все надписи, зашитые в QR-коды на картинке.
    static func payloads(in image: CIImage) -> [String] {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options) else {
            return []
        }
        let features = detector.features(in: image).compactMap { $0 as? CIQRCodeFeature }
        return features.compactMap { $0.messageString }.filter { !$0.isEmpty }
    }

    static func payloads(at url: URL) -> [String] {
        guard let image = CIImage(contentsOf: url) else { return [] }
        return payloads(in: image)
    }

    /// Картинка из буфера обмена — когда QR просто скопировали.
    static func payloadsFromPasteboard() -> [String] {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard),
              let data = image.tiffRepresentation,
              let ci = CIImage(data: data)
        else { return [] }
        return payloads(in: ci)
    }

    /// Текст конфигурации из QR-кода на картинке.
    static func config(at url: URL) -> String? {
        for payload in payloads(at: url) {
            if let config = SharedLink.extractConfig(payload) { return config }
        }
        return nil
    }
}
