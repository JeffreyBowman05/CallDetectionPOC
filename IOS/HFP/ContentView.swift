//
//  ContentView.swift
//  CallESP32
//
//  Root view. Displays the list of provisioned devices and entry point
//  for adding new ones or managing existing ones.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var ble: BluetoothManager
    @EnvironmentObject var deviceStore: DeviceStore

    @State private var showProvisioning = false
    @State private var deviceToReprovision: ProvisionedDevice? = nil
    @State private var deviceToRename: ProvisionedDevice? = nil
    @State private var pendingName = ""

    var body: some View {
        NavigationStack {
            Group {
                if deviceStore.devices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }
            }
            .navigationTitle("My Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        deviceToReprovision = nil
                        showProvisioning = true
                    } label: {
                        Label("Add Device", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showProvisioning) {
                ProvisioningView(existingDevice: deviceToReprovision)
                    .environmentObject(ble)
                    .environmentObject(deviceStore)
            }
            .alert("Rename Device", isPresented: Binding(
                get: { deviceToRename != nil },
                set: { if !$0 { deviceToRename = nil } }
            )) {
                TextField("Name", text: $pendingName)
                    .autocorrectionDisabled()
                Button("Save") {
                    if let device = deviceToRename {
                        deviceStore.updateName(pendingName, for: device.id)
                    }
                    deviceToRename = nil
                }
                Button("Cancel", role: .cancel) { deviceToRename = nil }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Devices")
                .font(.title2.bold())
            Text("Tap the button on your device to enter\nprovisioning mode, then tap Add Device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Device") {
                deviceToReprovision = nil
                showProvisioning = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Device List

    private var deviceList: some View {
        List {
            ForEach(deviceStore.devices) { device in
                DeviceRow(device: device)
                    // Leading swipe: re-provision
                    .swipeActions(edge: .leading) {
                        Button {
                            deviceToReprovision = device
                            showProvisioning = true
                        } label: {
                            Label("Re-Provision", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.orange)
                    }
                    // Trailing swipe: delete
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deviceStore.remove(id: device.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    // Context menu: rename, confirm HFP, re-provision, delete
                    .contextMenu {
                        Button {
                            pendingName = device.displayName
                            deviceToRename = device
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            deviceStore.markHFPPaired(id: device.id)
                        } label: {
                            Label("Mark as HFP Paired", systemImage: "phone.badge.checkmark")
                        }
                        .disabled(device.isHFPPaired)

                        Divider()

                        Button {
                            deviceToReprovision = device
                            showProvisioning = true
                        } label: {
                            Label("Re-Provision", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button(role: .destructive) {
                            deviceStore.remove(id: device.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {

    let device: ProvisionedDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(device.displayName)
                    .font(.headline)
                Spacer()
                HFPBadge(isPaired: device.isHFPPaired)
            }
            Label(device.wifiSSID, systemImage: "wifi")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("ID: \(device.deviceID)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HFP Badge

struct HFPBadge: View {

    let isPaired: Bool

    var body: some View {
        Label(
            isPaired ? "HFP Active" : "Pair via Bluetooth",
            systemImage: isPaired
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.caption.bold())
        .foregroundStyle(isPaired ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (isPaired ? Color.green : Color.orange).opacity(0.12),
            in: Capsule()
        )
    }
}
