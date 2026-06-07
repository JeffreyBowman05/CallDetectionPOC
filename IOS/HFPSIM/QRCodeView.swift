//
//  QRCodeView.swift
//  ESP32Simulator
//
//  Generates and displays a scannable QR code encoding "BTPROV:XXXX" using
//  CoreImage's built-in CIQRCodeGenerator filter. No external dependencies.
//
//  Point an iPhone running the iOS app at this code to trigger the QR
//  provisioning path instead of manual ID entry.
//

import SwiftUI
import CoreImage

struct QRCodeView: View {

    @EnvironmentObject var peripheral: PeripheralManager

    private let qrSize: CGFloat = 148

    var body: some View {
        VStack(spacing: 8) {

            Text("SCAN TO PROVISION")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.38))

            qrImage
                .interpolation(.none)   // Keep QR modules pixel-crisp — never smooth
                .resizable()
                .scaledToFit()
                .frame(width: qrSize, height: qrSize)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

            Text("BTPROV:\(peripheral.deviceID)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.48))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.10))
    }

    // MARK: - QR Generation

    private var qrImage: Image {
        generate(from: "BTPROV:\(peripheral.deviceID)")
    }

    /// Generates a QR code image from the given string using CoreImage.
    /// Scales the raw filter output up by 10x so individual modules are sharp
    /// when displayed on screen and captured by an iPhone camera.
    private func generate(from string: String) -> Image {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return Image(systemName: "qrcode")
        }

        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // M = ~15% error correction

        guard let rawOutput = filter.outputImage else {
            return Image(systemName: "qrcode")
        }

        // Scale up — raw CIQRCodeGenerator output is 1pt per module (very small)
        let scaled = rawOutput.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        )

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return Image(systemName: "qrcode")
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
        )
        return Image(nsImage: nsImage)
    }
}
