//
//  PeripheralManager.swift
//  ESP32Simulator
//
//  Acts as a real CBPeripheralManager GATT server, advertising the same
//  provisioning service and characteristics defined in BluetoothManager.swift
//  in the iOS companion app. The iPhone's CBCentralManager connects to this
//  Mac exactly as it would to a real ESP32.
//
//  Provisioning sequence handled here:
//    Central connects →
//    Central writes SSID → Central writes Password → Central subscribes to status →
//    Simulator waits 1.5s (simulated WiFi join) → Sends WIFI_OK notify →
//    Central disconnects
//
 
import SwiftUI
internal import Combine
import CoreBluetooth
 
// MARK: - PeripheralConnectionState
 
enum PeripheralConnectionState {
    case bluetoothUnavailable
    case idle
    case advertising
    case centralConnected
    case provisioning
    case provisioningComplete
 
    var displayText: String {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth Unavailable"
        case .idle:                 return "Idle"
        case .advertising:          return "Advertising"
        case .centralConnected:     return "Central Connected"
        case .provisioning:         return "Provisioning…"
        case .provisioningComplete: return "Provisioned ✓"
        }
    }
 
    var dotColor: Color {
        switch self {
        case .bluetoothUnavailable: return .red
        case .idle:                 return Color(white: 0.4)
        case .advertising:          return .orange
        case .centralConnected:     return .blue
        case .provisioning:         return .yellow
        case .provisioningComplete: return .green
        }
    }
}
 
// MARK: - BLE UUIDs
// Must exactly match BLEUUID in BluetoothManager.swift in the iOS app.
 
private enum BLEUUID {
    static let service   = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let ssid      = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    static let password  = CBUUID(string: "BEB5483F-36E1-4688-B7F5-EA07361B26A8")
    static let status    = CBUUID(string: "BEB54840-36E1-4688-B7F5-EA07361B26A8")
}
 
// MARK: - PeripheralManager
 
final class PeripheralManager: NSObject, ObservableObject {
 
    // MARK: Published
 
    @Published var connectionState: PeripheralConnectionState = .bluetoothUnavailable
    @Published var deviceID: String         // Simulates last 4 of BT MAC (randomised on launch)
    @Published var wifiNetwork: String = "" // Set after WIFI_OK is sent
 
    // MARK: Callback
 
    var onLog: ((LogEntry) -> Void)?
 
    // MARK: Private
 
    private var manager: CBPeripheralManager!
    private var statusChar: CBMutableCharacteristic?
    private var subscribedCentral: CBCentral?
    private var pendingSSID      = ""
    private var pendingPassword  = ""
    private var wifiTimer: Timer?
 
    // MARK: Init
 
    override init() {
        deviceID = String(format: "%04X", Int.random(in: 0...0xFFFF))
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }
 
    // MARK: - Public
 
    func startAdvertising() {
        guard manager.state == .poweredOn else {
            log("Cannot advertise — Bluetooth not powered on.", .system)
            return
        }
        rebuildService()
        let advertisement: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.service],
            CBAdvertisementDataLocalNameKey: "ESP32:\(deviceID)"
        ]
        manager.startAdvertising(advertisement)
    }
 
    func stopAdvertising() {
        manager.stopAdvertising()
        connectionState = .idle
        log("Advertising stopped.", .system)
    }
 
    func resetProvisioning() {
        wifiTimer?.invalidate()
        wifiTimer = nil
        subscribedCentral = nil
        pendingSSID = ""
        pendingPassword = ""
        wifiNetwork = ""
        log("Device reset. Ready to re-provision.", .system)
        if manager.state == .poweredOn {
            connectionState = .idle
            startAdvertising()
        } else {
            connectionState = .bluetoothUnavailable
        }
    }
 
    // MARK: - Private
 
    private func rebuildService() {
        manager.removeAllServices()
 
        let ssidChar = CBMutableCharacteristic(
            type: BLEUUID.ssid,
            properties: .write,
            value: nil,
            permissions: .writeable
        )
        let pwChar = CBMutableCharacteristic(
            type: BLEUUID.password,
            properties: .write,
            value: nil,
            permissions: .writeable
        )
        let statChar = CBMutableCharacteristic(
            type: BLEUUID.status,
            properties: .notify,
            value: nil,
            permissions: .readable
        )
        statusChar = statChar
 
        let service = CBMutableService(type: BLEUUID.service, primary: true)
        service.characteristics = [ssidChar, pwChar, statChar]
        manager.add(service)
    }
 
    /// Simulates the ESP32 attempting to join the provisioned WiFi network.
    private func beginWiFiSimulation() {
        guard !pendingSSID.isEmpty, !pendingPassword.isEmpty else { return }
        log("Simulating WiFi join to \"\(pendingSSID)\"…", .system)
        wifiTimer?.invalidate()
        wifiTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.sendStatusNotification("WIFI_OK")
            self.wifiNetwork = self.pendingSSID
            self.connectionState = .provisioningComplete
        }
    }
 
    private func sendStatusNotification(_ payload: String) {
        guard let char = statusChar,
              let central = subscribedCentral,
              let data = payload.data(using: .utf8) else { return }
        let sent = manager.updateValue(data, for: char, onSubscribedCentrals: [central])
        log("\(payload) → central (queued: \(!sent))", .ble)
    }
 
    private func log(_ message: String, _ category: LogEntry.Category) {
        onLog?(LogEntry(message: message, category: category))
    }
}
 
// MARK: - CBPeripheralManagerDelegate
 
extension PeripheralManager: CBPeripheralManagerDelegate {
 
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            connectionState = .idle
            log("Bluetooth powered on.", .system)
        case .poweredOff:
            connectionState = .bluetoothUnavailable
            log("Bluetooth powered off.", .system)
        case .unauthorized:
            connectionState = .bluetoothUnavailable
            log("Bluetooth unauthorized — add Bluetooth capability in Xcode Signing & Capabilities.", .system)
        case .unsupported:
            connectionState = .bluetoothUnavailable
            log("Bluetooth Classic/LE unsupported on this Mac.", .system)
        default:
            break
        }
    }
 
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            log("Advertising failed: \(error.localizedDescription)", .ble)
        } else {
            connectionState = .advertising
            log("Advertising as ESP32:\(deviceID) with provisioning service UUID.", .ble)
        }
    }
 
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error {
            log("Service registration failed: \(error.localizedDescription)", .ble)
        } else {
            log("Provisioning service registered (3 characteristics: SSID/PW/Status).", .ble)
        }
    }
 
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == BLEUUID.status else { return }
        subscribedCentral = central
        log("Central subscribed to status characteristic.", .ble)
 
        // If both credentials arrived before subscription, kick off WiFi sim now
        if !pendingSSID.isEmpty && !pendingPassword.isEmpty {
            beginWiFiSimulation()
        }
    }
 
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == BLEUUID.status else { return }
        subscribedCentral = nil
        log("Central unsubscribed from status characteristic.", .ble)
    }
 
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        // Upgrade state on first write (central is now connected)
        if connectionState == .advertising {
            connectionState = .centralConnected
            log("Central connected (inferred from first write request).", .ble)
        }
 
        for request in requests {
            guard let data = request.value,
                  let value = String(data: data, encoding: .utf8) else {
                peripheral.respond(to: request, withResult: .success)
                log("Received unreadable write (nil data or non-UTF-8) — skipped.", .ble)
                continue
            }
 
            switch request.characteristic.uuid {
 
            case BLEUUID.ssid:
                pendingSSID = value
                connectionState = .provisioning
                log("SSID received: \"\(value)\"", .ble)
 
            case BLEUUID.password:
                pendingPassword = value
                log("Password received: [\(value.count) chars — masked in log]", .ble)
                // If the central already subscribed before writing the password, proceed immediately
                if subscribedCentral != nil { beginWiFiSimulation() }
 
            default:
                log("Write to unknown characteristic: \(request.characteristic.uuid)", .ble)
            }
 
            peripheral.respond(to: request, withResult: .success)
        }
    }
 
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Called when a previously failed updateValue can be retried
        log("Ready to update subscribers (previous notify was queued).", .ble)
    }
}
