//
//  CallControlView.swift
//  ESP32Simulator
//
//  Manual call event injection panel. Each button fires the corresponding
//  HFP AT command sequence into the serial log and updates the device display.
//
//  The "Blocked" preset sends +CLIP: "",128 — a withheld number — which is
//  exactly what a real phone sends when the caller hides their ID.
//

import SwiftUI

struct CallControlView: View {

    @EnvironmentObject var peripheral: PeripheralManager
    @EnvironmentObject var callSim:    CallSimulator

    @State private var phoneNumber = "+14085551234"

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            controls
        }
        .background(.windowBackground)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "phone.circle")
                .foregroundStyle(.secondary)
            Text("HFP Call Simulator")
                .font(.headline)
            Spacer()
            callStateIndicator
            Button("Reset") { callSim.reset() }
                .controlSize(.small)
                .disabled(callSim.callState == .idle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var callStateIndicator: some View {
        HStack(spacing: 5) {
            Text(callSim.callState.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(stateColor)
            if case .active = callSim.callState {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(callSim.formattedDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {

            // Phone number row
            HStack(spacing: 8) {
                Image(systemName: "phone")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("Phone number (E.164: +14085551234)", text: $phoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(!isIdle)
            }

            // Preset numbers
            HStack(spacing: 6) {
                Text("Presets:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                presetButton("+14085551234", label: "US")
                presetButton("+447911123456", label: "UK")
                presetButton("+49301234567",  label: "DE")
                presetButton("",              label: "Blocked")
                Spacer()

                if peripheral.connectionState != .provisioningComplete {
                    Label("Provision first for full test", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Call event buttons
            HStack(spacing: 10) {

                Button {
                    callSim.triggerIncoming(rawNumber: phoneNumber)
                } label: {
                    Label("Incoming", systemImage: "phone.arrow.down.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!isIdle)

                Button {
                    callSim.triggerActive()
                } label: {
                    Label("Answer", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!isRinging)

                Button {
                    callSim.triggerEnded()
                } label: {
                    Label("End Call", systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!isRinging && !isActive)
            }
        }
        .padding(14)
    }

    // MARK: - Helpers

    private var isIdle: Bool {
        callSim.callState == .idle
    }

    private var isRinging: Bool {
        if case .ringing = callSim.callState { return true }
        return false
    }

    private var isActive: Bool {
        if case .active = callSim.callState { return true }
        return false
    }

    private var stateColor: Color {
        switch callSim.callState {
        case .idle:    return .secondary
        case .ringing: return .orange
        case .active:  return .green
        case .ended:   return .red
        }
    }

    private func presetButton(_ number: String, label: String) -> some View {
        Button(label) { phoneNumber = number }
            .controlSize(.small)
            .disabled(!isIdle)
    }
}
