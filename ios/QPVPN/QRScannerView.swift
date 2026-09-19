import AVFoundation
import SwiftUI
import UIKit

/// Камера для QR-кода.
///
/// Код приходит человеку картинкой или показывается на другом экране —
/// наводим камеру и читаем системным распознавателем, без сторонних библиотек.
struct QRScannerView: UIViewControllerRepresentable {

    let onResult: (String) -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onResult = onResult
        controller.onClose = onClose
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

        var onResult: ((String) -> Void)?
        var onClose: (() -> Void)?

        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var handled = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setUpSession()
            setUpOverlay()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        private func setUpSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { return }

            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        private func setUpOverlay() {
            let hint = UILabel()
            hint.text = "Наведите камеру на QR-код"
            hint.textColor = .white
            hint.font = .systemFont(ofSize: 15, weight: .medium)
            hint.textAlignment = .center
            hint.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hint)

            let close = UIButton(type: .system)
            close.setTitle("Закрыть", for: .normal)
            close.tintColor = .white
            close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)

            NSLayoutConstraint.activate([
                hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
                close.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                close.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            ])
        }

        @objc private func closeTapped() {
            onClose?()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !handled,
                  let code = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                  let value = code.stringValue
            else { return }

            handled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            session.stopRunning()
            onResult?(value)
        }
    }
}
