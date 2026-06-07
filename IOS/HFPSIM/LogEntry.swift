//
//  LogEntry.swift
//  ESP32Simulator
//
//  Shared log entry model. Both BLE events and HFP AT commands write
//  to the same log so the developer sees the full interleaved timeline.
//

import SwiftUI

struct LogEntry: Identifiable {
    let id        = UUID()
    let timestamp = Date()
    let message:    String
    let category:   Category

    // MARK: - Category

    enum Category {
        case ble     // CoreBluetooth peripheral events
        case hfp     // Simulated HFP AT commands
        case system  // Simulator lifecycle messages

        var tag: String {
            switch self {
            case .ble:    return "BLE"
            case .hfp:    return "HFP"
            case .system: return "SYS"
            }
        }

        var color: Color {
            switch self {
            case .ble:    return .blue
            case .hfp:    return Color(red: 0.15, green: 0.72, blue: 0.15)
            case .system: return .secondary
            }
        }
    }

    // MARK: - Display

    var formattedTime: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
