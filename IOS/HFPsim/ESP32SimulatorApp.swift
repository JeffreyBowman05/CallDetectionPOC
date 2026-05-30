//
//  ESP32SimulatorApp.swift
//  ESP32Simulator
//
//  macOS app that simulates an ESP32 Call Display device for development.
//  Acts as a real BLE GATT peripheral for provisioning and injects HFP AT
//  command sequences manually for call event testing.
//
//  Required Xcode setup (BEFORE building):
//    1. Signing & Capabilities → + Capability → Bluetooth
//    2. Info.plist → Add NSBluetoothAlwaysUsageDescription with a reason string
//

import SwiftUI

@main
struct ESP32SimulatorApp: App {

    @StateObject private var vm = SimulatorViewModel()

    var body: some Scene {
        WindowGroup("ESP32 Call Display Simulator") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(vm.peripheral)
                .environmentObject(vm.callSimulator)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Single-instance dev tool — remove File > New Window
            CommandGroup(replacing: .newItem) {}
        }
    }
}
