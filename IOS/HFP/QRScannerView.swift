//
//  QRScannerView.swift
//  CallESP32
//
//  Camera-based QR code scanner using AVFoundation.
//
//  Required Info.plist key:
//    NSCameraUsageDescription — explain why the app needs camera access.
//
//  The scanner fires onScanned once per session, then stops the capture session
//  to prevent repeated callbacks on the same code.
//

import SwiftUI
import AVFoundation

// MARK: - QRScannerView (SwiftUI wrapper)

struct QRScannerView: UIViewRepresentable {

    /// Called on the main thread exactly once when a QR code is successfully decoded.
    var onScanned: (String) -> Void

    func makeUIView(context: Context) -> QRCameraPreview {
        let preview = QRCameraPreview()
        preview.onScanned = onScanned
        return preview
    }

    func updateUIView(_ uiView: QRCameraPreview, context: Context) {}
}

// MARK: - QRCameraPreview (UIKit camera view)

final class QRCameraPreview: UIView {

    var onScanned: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // Guards against double-setup during multiple layoutSubviews calls
    private var isConfiguringSession = false
    // Guards against multiple callbacks on the same QR code
    private var hasScanned = false

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if captureSession == nil, !isConfiguringSession {
            isConfiguringSession = true
            requestAccessAndConfigure()
        }
        previewLayer?.frame = bounds
    }

    // MARK: - Setup

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showMessage("Camera access denied.")
                    }
                }
            }
        case .denied, .restricted:
            showMessage("Camera access denied.\nEnable it in Settings → Privacy → Camera.")
        @unknown default:
            showMessage("Camera not available.")
        }
    }

    private func configureSession() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video) else {
            showMessage("No camera found on this device.")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            showMessage("Could not access camera input.")
            return
        }

        let output = AVCaptureMetadataOutput()

        guard session.canAddInput(input), session.canAddOutput(output) else {
            showMessage("Camera configuration failed.")
            return
        }

        session.addInput(input)
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // MARK: - Session Control

    func stopSession() {
        captureSession?.stopRunning()
    }

    // MARK: - Fallback UI

    private func showMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let label = UILabel()
            label.text = message
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -24)
            ])
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension QRCameraPreview: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue,
              !value.isEmpty else { return }

        hasScanned = true   // Prevent duplicate callbacks on the same scan session
        stopSession()
        onScanned?(value)
    }
}
