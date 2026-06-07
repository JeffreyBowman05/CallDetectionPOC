//  Observable store for all provisioned devices.
//  Persists to UserDefaults and exposes a clean mutation API.
//
 
import Foundation
internal import Combine

final class DeviceStore: ObservableObject {
 
    // No default value here — _devices is initialized directly in init()
    // using Published(initialValue:) to satisfy Swift's definite initialization
    // checker without calling self.load() before all properties are confirmed ready.
    @Published private(set) var devices: [ProvisionedDevice]
 
    private let storageKey = "com.callESP32.provisioned_devices"
 
    init() {
        // Load persisted devices, or start with an empty array.
        // Writing to _devices directly initializes the backing store without
        // going through the property setter, which is required at this stage.
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ProvisionedDevice].self, from: data) {
            _devices = Published(initialValue: decoded)
        } else {
            _devices = Published(initialValue: [])
        }
    }
 
    // MARK: - Public API
 
    /// Add a newly provisioned device. Silently ignores duplicates by deviceID.
    func add(_ device: ProvisionedDevice) {
        guard !devices.contains(where: { $0.deviceID == device.deviceID }) else { return }
        devices.append(device)
        save()
    }
 
    /// Remove a device by its store ID.
    func remove(id: UUID) {
        devices.removeAll { $0.id == id }
        save()
    }
 
    /// Update the user-facing display name. Ignores blank strings.
    func updateName(_ name: String, for id: UUID) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].displayName = name
        save()
    }
 
    /// Mark the device as HFP-paired after the user confirms pairing in iOS Settings.
    func markHFPPaired(id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].isHFPPaired = true
        save()
    }
 
    /// Update provisioning metadata after a successful re-provisioning session.
    func reprovision(id: UUID, ssid: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].reprovision(ssid: ssid)
        save()
    }
 
    // MARK: - Persistence
 
    private func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
 
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ProvisionedDevice].self, from: data) else { return }
        devices = decoded
    }
}
