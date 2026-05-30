//
//  BluetoothManager.swift
//  CallESP32
//
//  BLE is now used exclusively for device provisioning (WiFi credential delivery).
//  Call state and caller ID are handled by HFP at the device level — this file
//  has no knowledge of calls.
//

import Foundation
import CoreBluetooth

// MARK: - ProvisioningState

enum ProvisioningState: Equatable {
    case idle
    case scanning
    case connecting
    case discoveringServices
    case awaitingCredentials        // Connected — waiting for user to enter WiFi credentials
    case writingSSID
    case writingPassword
    case awaitingWiFiConfirmation   // Credentials delivered — waiting for device to join WiFi
    case complete
    case failed(String)

    static func == (lhs: ProvisioningState, rhs: ProvisioningState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning), (.connecting, .connecting),
             (.discoveringServices, .discoveringServices), (.awaitingCredentials, .awaitingCredentials),
             (.writingSSID, .writingSSID), (.writingPassword, .writingPassword),
             (.awaitingWiFiConfirmation, .awaitingWiFiConfirmation), (.complete, .complete):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    /// Human-readable status for display in the UI.
    var statusText: String {
        switch self {
        case .idle:                     return "Ready"
        case .scanning:                 return "Scanning for device…"
        case .connecting:               return "Connecting…"
        case .discoveringServices:      return "Identifying device…"
        case .awaitingCredentials:      return "Enter Wi-Fi credentials"
        case .writingSSID:              return "Sending network name…"
        case .writingPassword:          return "Sending password…"
        case .awaitingWiFiConfirmation: return "Waiting for device to join Wi-Fi…"
        case .complete:                 return "Provisioning complete"
        case .failed(let msg):          return msg
        }
    }

    /// True while BLE work is actively in flight — used to detect unexpected interruptions.
    var isInProgress: Bool {
        switch self {
        case .scanning, .connecting, .discoveringServices,
             .writingSSID, .writingPassword, .awaitingWiFiConfirmation:
            return true
        default:
            return false
        }
    }
}

// MARK: - BLE UUIDs
//
// ⚠️  These UUIDs must match your ESP32 provisioning firmware exactly.
//     Update the firmware to advertise BLEUUID.service and expose three characteristics:
//       ssid     — Write with response. Accepts a UTF-8 encoded SSID string.
//       password — Write with response. Accepts a UTF-8 encoded password string.
//       status   — Notify. Device sends "WIFI_OK" on success or "WIFI_FAIL" on failure.

private enum BLEUUID {
    static let service   = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let ssid      = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    static let password  = CBUUID(string: "BEB5483F-36E1-4688-B7F5-EA07361B26A8")
    static let status    = CBUUID(string: "BEB54840-36E1-4688-B7F5-EA07361B26A8")
}

// MARK: - BluetoothManager

final class BluetoothManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var provisioningState: ProvisioningState = .idle
    @Published var isBLEReady = false

    // MARK: Private — BLE stack

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var ssidChar: CBCharacteristic?
    private var passwordChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    // MARK: Private — Session data

    private var targetDeviceID: String?
    private var pendingPassword: String?
    private var scanTimer: Timer?
    private let scanTimeoutInterval: TimeInterval = 15

    // MARK: Callback

    /// Called when provisioning ends. `true` = WiFi join confirmed by device, `false` = failed.
    var onProvisioningComplete: ((Bool) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    /// Begin a provisioning session for the device with the given 4-character suffix
    /// (the last 4 hex characters of its Bluetooth MAC address).
    /// Obtain this value by scanning the QR code on the device or reading it from the label.
    func startProvisioning(deviceID: String) {
        guard isBLEReady else {
            provisioningState = .failed("Bluetooth is not available. Enable it in Settings.")
            return
        }
        cleanupSession()
        targetDeviceID = deviceID.uppercased()
        provisioningState = .scanning
        central.scanForPeripherals(
            withServices: [BLEUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleScanTimeout()
    }

    /// Deliver WiFi credentials to the connected device.
    /// Only effective when provisioningState == .awaitingCredentials.
    func submitCredentials(ssid: String, password: String) {
        guard provisioningState == .awaitingCredentials,
              !ssid.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else { return }
        pendingPassword = password
        writeSSID(ssid)
    }

    /// Abort the active provisioning session and return to idle.
    func cancelProvisioning() {
        cleanupSession()
        provisioningState = .idle
    }

    // MARK: - Private — GATT state machine

    private func writeSSID(_ ssid: String) {
        guard let p = peripheral, let char = ssidChar,
              let data = ssid.data(using: .utf8) else {
            provisioningState = .failed("Failed to prepare SSID write.")
            return
        }
        provisioningState = .writingSSID
        p.writeValue(data, for: char, type: .withResponse)
    }

    private func writePassword() {
        guard let p = peripheral, let char = passwordChar,
              let pw = pendingPassword,
              let data = pw.data(using: .utf8) else {
            provisioningState = .failed("Failed to prepare password write.")
            return
        }
        pendingPassword = nil   // Zero out immediately after encoding into Data
        provisioningState = .writingPassword
        p.writeValue(data, for: char, type: .withResponse)
    }

    private func subscribeToStatus() {
        guard let p = peripheral, let char = statusChar else { return }
        provisioningState = .awaitingWiFiConfirmation
        p.setNotifyValue(true, for: char)
    }

    // MARK: - Private — Cleanup

    private func cleanupSession() {
        scanTimer?.invalidate()
        scanTimer = nil
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        ssidChar = nil
        passwordChar = nil
        statusChar = nil
        targetDeviceID = nil
        pendingPassword = nil
    }

    private func scheduleScanTimeout() {
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: scanTimeoutInterval,
            repeats: false
        ) { [weak self] _ in
            guard let self, case .scanning = self.provisioningState else { return }
            self.central.stopScan()
            self.provisioningState = .failed(
                "Device not found. Press the button on your device to enter provisioning mode, then try again."
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBLEReady = central.state == .poweredOn
        if !isBLEReady, provisioningState.isInProgress {
            cleanupSession()
            provisioningState = .failed("Bluetooth was disabled during provisioning.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Device advertises as "ESP32:XXXX" — match on the 4-character suffix
        guard let name = peripheral.name,
              let id = targetDeviceID,
              name.uppercased().hasSuffix(id) else { return }

        scanTimer?.invalidate()
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        provisioningState = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        provisioningState = .discoveringServices
        peripheral.discoverServices([BLEUUID.service])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        provisioningState = .failed(error?.localizedDescription ?? "Connection failed.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // Ignore the expected disconnect that follows a successful provisioning completion
        if case .complete = provisioningState { return }
        if let error {
            provisioningState = .failed("Connection lost: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            provisioningState = .failed("Service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEUUID.service }) else {
            provisioningState = .failed(
                "Provisioning service not found. Is the device in provisioning mode?"
            )
            return
        }
        peripheral.discoverCharacteristics(
            [BLEUUID.ssid, BLEUUID.password, BLEUUID.status],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            provisioningState = .failed("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case BLEUUID.ssid:     ssidChar = char
            case BLEUUID.password: passwordChar = char
            case BLEUUID.status:   statusChar = char
            default:               break
            }
        }
        guard ssidChar != nil, passwordChar != nil, statusChar != nil else {
            provisioningState = .failed(
                "Required characteristics missing. Ensure firmware is up to date."
            )
            return
        }
        provisioningState = .awaitingCredentials
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            provisioningState = .failed("Write failed: \(error.localizedDescription)")
            return
        }
        switch characteristic.uuid {
        case BLEUUID.ssid:     writePassword()
        case BLEUUID.password: subscribeToStatus()
        default:               break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BLEUUID.status else { return }

        if let error {
            provisioningState = .failed("Status read error: \(error.localizedDescription)")
            onProvisioningComplete?(false)
            return
        }

        let message = characteristic.value
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        if message.uppercased().contains("OK") {
            provisioningState = .complete
            onProvisioningComplete?(true)
            central.cancelPeripheralConnection(peripheral)
        } else {
            provisioningState = .failed(
                "Device failed to join the Wi-Fi network. Check credentials and try again."
            )
            onProvisioningComplete?(false)
        }
    }
}
