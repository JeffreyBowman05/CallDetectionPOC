//
//  DeviceDisplayView.swift
//  ESP32Simulator
//
//  Renders a simulated embedded OLED display showing exactly what a real
//  ESP32 running your firmware would show on its screen, given the current
//  call state and provisioning status.
//

import SwiftUI

struct DeviceDisplayView: View {

    @EnvironmentObject var peripheral: PeripheralManager
    @EnvironmentObject var callSim:    CallSimulator

    // Phosphor green palette
    private let phosphorBright = Color(red: 0.18, green: 0.92, blue: 0.18)
    private let phosphorMid    = Color(red: 0.12, green: 0.60, blue: 0.12)
    private let phosphorDim    = Color(red: 0.07, green: 0.32, blue: 0.07)
    private let screenBG       = Color(red: 0.03, green: 0.05, blue: 0.03)
    private let bezelBG        = Color(white: 0.14)
    private let panelBG        = Color(white: 0.10)

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            screenBezel
                .padding(.horizontal, 18)

            Spacer(minLength: 0)

            deviceIDFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBG)
    }

    // MARK: - Header

    private var header: some View {
        Text("DEVICE PREVIEW")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(white: 0.35))
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Screen Bezel

    private var screenBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(bezelBG)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)

            screen
                .padding(14)
        }
        .aspectRatio(4/3, contentMode: .fit)
    }

    // MARK: - Screen Content

    private var screen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(screenBG)

            // Subtle scanline overlay for CRT authenticity
            scanlineOverlay

            VStack(alignment: .leading, spacing: 0) {
                topBar
                dividerLine
                Spacer(minLength: 6)
                callContent
                Spacer(minLength: 6)
                dividerLine
                bottomBar
            }
            .padding(10)
        }
    }

    // MARK: - Screen Sections

    private var topBar: some View {
        HStack {
            mono("ESP32:\(peripheral.deviceID)", size: 12, color: phosphorBright)
            Spacer()
            statusDot
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 7, height: 7)
            .shadow(color: statusDotColor.opacity(0.9), radius: 5)
    }

    private var statusDotColor: Color {
        switch callSim.callState {
        case .idle:    return peripheral.connectionState == .provisioningComplete ? phosphorMid : phosphorDim
        case .ringing: return .orange
        case .active:  return .green
        case .ended:   return .red
        }
    }

    @ViewBuilder
    private var callContent: some View {
        switch callSim.callState {

        case .idle:
            mono("  CALL DISPLAY", size: 12, color: phosphorBright)
            Spacer(minLength: 4)
            mono(
                peripheral.connectionState == .provisioningComplete ? "  READY" : "  NOT PROVISIONED",
                size: 12,
                color: peripheral.connectionState == .provisioningComplete ? phosphorBright : phosphorMid
            )
            Spacer(minLength: 4)
            mono("  AWAITING CALL...", size: 10, color: phosphorDim)

        case .ringing(let number):
            mono("  >> INCOMING CALL <<", size: 12, color: phosphorBright)
            Spacer(minLength: 4)
            mono("  \(number)", size: 11, color: phosphorBright)
            Spacer(minLength: 4)
            mono("  RING [\(callSim.ringCount)]", size: 10, color: phosphorMid)

        case .active(let number):
            mono("  [ CALL ACTIVE ]", size: 12, color: phosphorBright)
            Spacer(minLength: 4)
            mono("  \(number)", size: 11, color: phosphorBright)
            Spacer(minLength: 4)
            mono("  \(callSim.formattedDuration)", size: 10, color: phosphorMid)

        case .ended(let number):
            mono("  -- CALL ENDED --", size: 12, color: phosphorMid)
            Spacer(minLength: 4)
            mono("  \(number)", size: 11, color: phosphorDim)
            Spacer(minLength: 4)
            mono("", size: 10, color: phosphorDim)
        }
    }

    private var bottomBar: some View {
        mono(
            peripheral.wifiNetwork.isEmpty ? "WIFI: --" : "WIFI: \(peripheral.wifiNetwork)",
            size: 10,
            color: phosphorDim
        )
    }

    private var dividerLine: some View {
        mono(String(repeating: "─", count: 22), size: 10, color: phosphorDim)
            .padding(.vertical, 2)
    }

    // MARK: - Scanline Overlay

    private var scanlineOverlay: some View {
        GeometryReader { geo in
            Path { path in
                var y: CGFloat = 0
                while y < geo.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += 3
                }
            }
            .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Device ID Footer

    private var deviceIDFooter: some View {
        Text("SIM • BT-ID: \(peripheral.deviceID) • QR: BTPROV:\(peripheral.deviceID)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color(white: 0.28))
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func mono(_ text: String, size: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
