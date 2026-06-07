//
//  CallSimulator.swift
//  ESP32Simulator
//
//  Simulates the HFP AT command sequences a real paired iPhone would send
//  to the ESP32 over its RFCOMM channel. These are the exact commands your
//  firmware must parse.
//
//  Real HFP AT sequence reference:
//    Incoming call:
//      +CIEV: callsetup,1       ← incoming call setup indicator
//      RING                     ← repeated every ~3s while ringing
//      +CLIP: "number",type     ← caller ID (with each RING if AT+CLIP=1)
//    Call answered (by phone user or HF):
//      +CIEV: callsetup,0       ← setup complete
//      +CIEV: call,1            ← call now active
//    Call ended:
//      +CIEV: call,0            ← call cleared
//      +CIEV: callsetup,0       ← redundant but always sent
//

import Foundation
internal import Combine

// MARK: - CallState

enum CallState: Equatable {
    case idle
    case ringing(phoneNumber: String)
    case active(phoneNumber: String)
    case ended(phoneNumber: String)

    var phoneNumber: String? {
        switch self {
        case .ringing(let n), .active(let n), .ended(let n): return n
        case .idle: return nil
        }
    }

    var label: String {
        switch self {
        case .idle:    return "IDLE"
        case .ringing: return "RINGING"
        case .active:  return "ACTIVE"
        case .ended:   return "ENDED"
        }
    }
}

// MARK: - CallSimulator

final class CallSimulator: ObservableObject {

    // MARK: Published

    @Published var callState: CallState = .idle
    @Published var ringCount: Int       = 0
    @Published var callDuration: Int    = 0     // seconds since call became active

    // MARK: Callback

    var onATCommand: ((LogEntry) -> Void)?

    // MARK: Private

    private var ringTimer: Timer?
    private var durationTimer: Timer?

    // MARK: - Public API

    /// Simulate an incoming call. Sends +CIEV: callsetup,1 then repeating RING+CLIP.
    /// Pass an empty string to simulate a blocked / withheld number.
    func triggerIncoming(rawNumber: String) {
        guard case .idle = callState else { return }

        let cleaned = rawNumber.trimmingCharacters(in: .whitespaces)
        // Represent blocked number on the display as <BLOCKED>
        let displayNumber = cleaned.isEmpty ? "<BLOCKED>" : cleaned

        ringCount = 0
        callState = .ringing(phoneNumber: displayNumber)

        at("+CIEV: callsetup,1", note: "incoming call: setup indicator raised")
        sendRing(rawNumber: cleaned)

        ringTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sendRing(rawNumber: cleaned)
        }
    }

    /// Simulate the call being answered. Sends callsetup cleared + call active indicator.
    func triggerActive() {
        guard case .ringing(let number) = callState else { return }
        ringTimer?.invalidate()
        callDuration = 0
        callState = .active(phoneNumber: number)

        at("+CIEV: callsetup,0", note: "call answered: setup cleared")
        at("+CIEV: call,1",      note: "call indicator: call now active")

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.callDuration += 1
        }
    }

    /// Simulate call end from either ringing or active state.
    func triggerEnded() {
        let number: String
        switch callState {
        case .ringing(let n): number = n
        case .active(let n):  number = n
        default: return
        }

        ringTimer?.invalidate()
        durationTimer?.invalidate()
        callState = .ended(phoneNumber: number)

        at("+CIEV: call,0",      note: "call indicator: call cleared")
        at("+CIEV: callsetup,0", note: "call setup: cleared")

        // Auto-return to idle after the ended state is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, case .ended = self.callState else { return }
            self.callState = .idle
            self.ringCount = 0
        }
    }

    /// Hard reset back to idle without sending AT commands.
    func reset() {
        ringTimer?.invalidate()
        durationTimer?.invalidate()
        callState = .idle
        ringCount = 0
        callDuration = 0
    }

    // MARK: - Computed

    var formattedDuration: String {
        String(format: "%02d:%02d", callDuration / 60, callDuration % 60)
    }

    // MARK: - Private

    /// Sends one RING + CLIP pair. Called on first incoming and then every 3s by timer.
    private func sendRing(rawNumber: String) {
        ringCount += 1

        // RING has no parameters — the HF unit knows it means "still ringing"
        at("RING", note: "ring event \(ringCount)")

        // +CLIP type: 145 = international (+prefix), 129 = national, 128 = unknown/blocked
        if rawNumber.isEmpty {
            at("+CLIP: \"\",128", note: "caller ID withheld (blocked)")
        } else {
            let clipType = rawNumber.hasPrefix("+") ? 145 : 129
            at("+CLIP: \"\(rawNumber)\",\(clipType)", note: "caller ID delivered")
        }
    }

    private func at(_ command: String, note: String = "") {
        let message = note.isEmpty ? command : "\(command)   ← \(note)"
        onATCommand?(LogEntry(message: message, category: .hfp))
    }
}
