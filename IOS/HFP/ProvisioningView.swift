//
//  ProvisioningView.swift
//  CallESP32
//
//  Multi-step sheet that walks the user through:
//    1. QR scan or manual device ID entry
//    2. BLE connect + service discovery
//    3. WiFi credential entry
//    4. GATT write + WiFi join confirmation
//    5. HFP pairing guidance (iOS Bluetooth Settings)
//    6. Completion
//
//  Required Info.plist keys:
//    NSBluetoothAlwaysUsageDescription
//    NSCameraUsageDescription
//

import SwiftUI

// MARK: - Local step enum
//
// Extends the BLE state machine in BluetoothManager with UI-only steps
// that have no BLE counterpart (HFP guidance, completion screen).

private enum ProvisioningStep {
    case entry              // QR scanner + manual ID field
    case inProgress         // Scanning / connecting / discovering
    case credentials        // WiFi SSID + password form
    case writing            // GATT writes + WiFi join in flight
    case hfpGuidance        // Instruct user to pair in iOS Settings
    case complete           // All done
    case failed(String)
}

// MARK: - ProvisioningView

struct ProvisioningView: View {

    @EnvironmentObject var ble: BluetoothManager
    @EnvironmentObject var deviceStore: DeviceStore
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when the user chose Re-Provision from the device list.
    let existingDevice: ProvisionedDevice?

    // MARK: State

    @State private var step: ProvisioningStep = .entry
    @State private var manualDeviceID = ""
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var showPassword = false
    @State private var resolvedDeviceID = ""
    @State private var deviceLabel = ""

    // MARK: Body

    var body: some View {
        NavigationStack {
            stepContent
                .navigationTitle(existingDevice != nil ? "Re-Provision Device" : "Add Device")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            ble.cancelProvisioning()
                            dismiss()
                        }
                    }
                }
                .onChange(of: ble.provisioningState) { _, newState in
                    syncStep(from: newState)
                }
                .onAppear {
                    if let existing = existingDevice {
                        manualDeviceID = existing.deviceID
                        deviceLabel    = existing.displayName
                    }
                }
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .entry:              entryView
        case .inProgress:         progressView
        case .credentials:        credentialsView
        case .writing:            writingView
        case .hfpGuidance:        hfpGuidanceView
        case .complete:           completeView
        case .failed(let msg):    failedView(message: msg)
        }
    }

    // MARK: - Step 1: Entry (QR scan + manual ID)

    private var entryView: some View {
        VStack(spacing: 0) {
            QRScannerView { rawValue in
                if let id = parseQRCode(rawValue) {
                    beginProvisioning(deviceID: id)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Text("Point camera at device QR code")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 20)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Or enter device ID manually")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Last 4 of BT MAC (e.g. A1B2)", text: $manualDeviceID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: manualDeviceID) { _, val in
                            // Clamp to 4 uppercase hex characters
                            manualDeviceID = String(
                                val.uppercased()
                                   .filter { $0.isHexDigit }
                                   .prefix(4)
                            )
                        }

                    Button("Connect") {
                        beginProvisioning(deviceID: manualDeviceID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualDeviceID.count != 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Step 2: In Progress (scanning → connecting → discovering)

    private var progressView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.4)
            Text(ble.provisioningState.statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Keep your device close to your iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 3: WiFi Credentials

    private var credentialsView: some View {
        Form {
            Section {
                TextField("Network name (SSID)", text: $wifiSSID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: $wifiPassword)
                        } else {
                            SecureField("Password", text: $wifiPassword)
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            } header: {
                Text("Wi-Fi Network")
            } footer: {
                Text("Credentials are written directly to your device over Bluetooth and are not stored by this app.")
            }

            Section {
                Button("Provision Device") {
                    step = .writing
                    ble.submitCredentials(ssid: wifiSSID, password: wifiPassword)
                }
                .frame(maxWidth: .infinity)
                .disabled(
                    wifiSSID.trimmingCharacters(in: .whitespaces).isEmpty || wifiPassword.isEmpty
                )
            }
        }
    }

    // MARK: - Step 4: Writing / WiFi Join in Flight

    private var writingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.4)
            Text(ble.provisioningState.statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Do not close this app or move away from the device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 5: HFP Pairing Guidance

    private var hfpGuidanceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Success banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi provisioning complete")
                            .font(.headline)
                        Text("One more step to enable call events.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pair for Hands-Free Phone (HFP)")
                        .font(.headline)
                    Text(
                        "Your device receives call events — including the caller's phone number — " +
                        "through your iPhone's Bluetooth connection using the HFP protocol, " +
                        "the same mechanism used by car hands-free kits. " +
                        "This pairing is done once in iOS Settings."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                // Numbered steps
                VStack(alignment: .leading, spacing: 16) {
                    PairingStep(number: 1, text: "Open the Settings app on your iPhone.")
                    PairingStep(number: 2, text: "Tap Bluetooth.")
                    PairingStep(
                        number: 3,
                        text: "Find 'ESP32:\(resolvedDeviceID)' under Other Devices and tap it."
                    )
                    PairingStep(number: 4, text: "Accept the pairing request if prompted.")
                    PairingStep(
                        number: 5,
                        text: "The device moves to My Devices with a Connected indicator."
                    )
                }

                // Footnote
                Text(
                    "Once paired, the device will automatically reconnect whenever it is " +
                    "powered on and within range. No further app interaction is required " +
                    "for normal call operation."
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)

                // CTA
                Button("I've paired it in Bluetooth Settings") {
                    saveDevice()
                    step = .complete
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("I'll do this later") {
                    saveDevice()
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            }
            .padding()
        }
    }

    // MARK: - Step 6: Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Device Ready")
                .font(.title.bold())
            Text(
                "\(deviceLabel) is provisioned on \(wifiSSID) " +
                "and paired for HFP call events."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Provisioning Failed")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                ble.cancelProvisioning()
                step = .entry
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func beginProvisioning(deviceID: String) {
        guard !deviceID.isEmpty else { return }
        resolvedDeviceID = deviceID.uppercased()
        deviceLabel = existingDevice?.displayName ?? "Device \(resolvedDeviceID)"
        step = .inProgress
        ble.startProvisioning(deviceID: resolvedDeviceID)
    }

    /// Maps BluetoothManager's published state to the local UI step.
    private func syncStep(from state: ProvisioningState) {
        switch state {
        case .scanning, .connecting, .discoveringServices:
            step = .inProgress
        case .awaitingCredentials:
            step = .credentials
        case .writingSSID, .writingPassword, .awaitingWiFiConfirmation:
            step = .writing
        case .complete:
            step = .hfpGuidance
        case .failed(let msg):
            step = .failed(msg)
        case .idle:
            break
        }
    }

    /// Parses a QR payload in the format "BTPROV:XXXX".
    /// Returns the 4-character device ID on success, nil on format mismatch.
    private func parseQRCode(_ raw: String) -> String? {
        let prefix = "BTPROV:"
        let upper = raw.uppercased()
        guard upper.hasPrefix(prefix) else { return nil }
        let id = String(upper.dropFirst(prefix.count))
        guard id.count == 4, id.allSatisfy({ $0.isHexDigit }) else { return nil }
        return id
    }

    /// Persist the device to DeviceStore after provisioning succeeds.
    private func saveDevice() {
        if let existing = existingDevice {
            deviceStore.reprovision(id: existing.id, ssid: wifiSSID)
        } else {
            deviceStore.add(
                ProvisionedDevice(
                    deviceID: resolvedDeviceID,
                    displayName: deviceLabel,
                    wifiSSID: wifiSSID
                )
            )
        }
    }
}

// MARK: - Pairing Step

private struct PairingStep: View {

    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.blue, in: Circle())
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
