//
//  SerialMonitorView.swift
//  ESP32Simulator
//
//  Dark-terminal log showing the interleaved BLE provisioning events and
//  HFP AT commands in timestamp order. Auto-scrolls to the latest entry.
//

import SwiftUI

struct SerialMonitorView: View {

    @EnvironmentObject var vm: SimulatorViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logBody
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text("Serial Monitor")
                .font(.headline)
            Spacer()
            Text("\(vm.logEntries.count) entries")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Clear") { vm.clearLog() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Log Body

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.logEntries) { entry in
                        LogRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color(white: 0.06))
            .onChange(of: vm.logEntries.count) { _, _ in
                if let last = vm.logEntries.last {
                    withAnimation(.none) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Row

private struct LogRow: View {

    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {

            // Timestamp
            Text(entry.formattedTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.36))
                .frame(width: 96, alignment: .leading)

            // Category badge
            Text(entry.category.tag)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.category.color, in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 34)

            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.category.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}
