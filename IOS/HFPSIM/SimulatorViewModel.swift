//
//  SimulatorViewModel.swift
//  ESP32Simulator
//
//  Owns the two subsystems and the shared log. Views receive all three
//  as separate environment objects so each can observe only what it needs.
//

import Foundation
internal import Combine

final class SimulatorViewModel: ObservableObject {

    // MARK: Published

    @Published var logEntries: [LogEntry] = []

    // MARK: Subsystems
    // Exposed so the App can inject them as separate environment objects

    let peripheral    = PeripheralManager()
    let callSimulator = CallSimulator()

    // MARK: Init

    init() {
        peripheral.onLog = { [weak self] entry in
            self?.append(entry)
        }
        callSimulator.onATCommand = { [weak self] entry in
            self?.append(entry)
        }
        append(LogEntry(
            message: "Simulator ready. Add Bluetooth capability in Xcode, then start advertising.",
            category: .system
        ))
    }

    // MARK: - Public

    func clearLog() {
        logEntries.removeAll()
    }

    // MARK: - Private

    private func append(_ entry: LogEntry) {
        // Both subsystems already fire on the main queue; this is a safety net
        DispatchQueue.main.async { [weak self] in
            self?.logEntries.append(entry)
        }
    }
}
