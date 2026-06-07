//
//  CallDisplayApp.swift
//  CallESP32
//
//
//  This app is responsible for:
//    1. BLE-based WiFi provisioning of ESP32 devices.
//    2. Guiding the user through HFP pairing in iOS Bluetooth Settings.
//    3. Device management (rename, re-provision, remove).
//

import SwiftUI

@main
struct CallDisplayApp: App {

    @StateObject private var ble = BluetoothManager()
    @StateObject private var deviceStore = DeviceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(deviceStore)
        }
    }
}
