//
//  ProvisionedDevice.swift
//  CallESP32
//
//  Data model for a single provisioned device.
//  Stored and retrieved by DeviceStore.
//

import Foundation

struct ProvisionedDevice: Identifiable, Codable, Equatable {

    let id: UUID
    let deviceID: String        // Last 4 hex chars of BT MAC address (uppercase)
    var displayName: String     // User-editable friendly label
    var wifiSSID: String        // Network the device is currently provisioned to
    var provisionedAt: Date     // Timestamp of most recent successful provisioning
    var isHFPPaired: Bool       // User has confirmed pairing via iOS Bluetooth Settings

    // MARK: - Init (new device)

    init(deviceID: String, displayName: String, wifiSSID: String) {
        self.id           = UUID()
        self.deviceID     = deviceID.uppercased()
        self.displayName  = displayName
        self.wifiSSID     = wifiSSID
        self.provisionedAt = Date()
        self.isHFPPaired  = false
    }

    // MARK: - Re-provisioning

    /// Updates provisioning metadata when the device is re-provisioned.
    /// Resets isHFPPaired because re-provisioning may produce a new BT identity.
    mutating func reprovision(ssid: String) {
        self.wifiSSID      = ssid
        self.provisionedAt = Date()
        self.isHFPPaired   = false
    }
}
