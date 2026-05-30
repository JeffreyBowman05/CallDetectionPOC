//
//  ContentView.swift
//  ESP32Simulator
//
//  Three-panel layout:
//    Left  — simulated device display + BLE controls
//    Right top    — serial monitor (BLE events + HFP AT commands)
//    Right bottom — HFP call control panel
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var peripheral: PeripheralManager

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 290, idealWidth: 310, maxWidth: 370)

            rightPanel
                .frame(minWidth: 500)
        }
        .frame(minWidth: 840, minHeight: 520)
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            DeviceDisplayView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            bleStatusBar
        }
    }

    private var bleStatusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(peripheral.connectionState.dotColor)
                .frame(width: 9, height: 9)

            Text(peripheral.connectionState.displayText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            bleActionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.windowBackground)
    }

    @ViewBuilder
    private var bleActionButton: some View {
        switch peripheral.connectionState {

        case .bluetoothUnavailable:
            Text("Enable Bluetooth in System Settings")
                .font(.system(size: 10))
                .foregroundStyle(.red)

        case .idle:
            Button("Start Advertising") {
                peripheral.startAdvertising()
            }
            .controlSize(.small)

        case .advertising:
            Button("Stop") {
                peripheral.stopAdvertising()
            }
            .controlSize(.small)

        case .centralConnected, .provisioning:
            Text("Provisioning in progress…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

        case .provisioningComplete:
            Button("Reset Device") {
                peripheral.resetProvisioning()
            }
            .controlSize(.small)
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VSplitView {
            SerialMonitorView()
                .frame(minHeight: 240)

            CallControlView()
                .frame(minHeight: 190, idealHeight: 230, maxHeight: 290)
        }
    }
}
