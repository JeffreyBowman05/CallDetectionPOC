//
//  ContentView.swift
//  BLESim
//
//  Created by developer on 1/11/26.
//

import SwiftUI
import AVFoundation

var audioPlayer: AVAudioPlayer?

func playSound() {
    guard let soundURL = Bundle.main.url(forResource: "Calling 3", withExtension: "mp3") else {
        print("Sound File not Found")
        return }
    
    do {
        audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
        audioPlayer?.numberOfLoops = -1 // -1 = loop forever
        audioPlayer?.play()
    } catch {
        print("Error Playing Sound: \(error.localizedDescription)")
    }
}

struct ContentView: View {
    
    @StateObject private var ble = BLEPeriphManager()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("ESP32Simulator")
                .font(.headline)
            
            statusView
            
        }
        .padding()
        .frame(width: 300, height: 200)
        .onChange(of: ble.callState) { oldState, newState in
            if newState == "INCOMING CALL" {
                playSound()
            } else {
                audioPlayer?.stop()
            }
        }
    }
    
    @ViewBuilder var statusView: some View {
        switch ble.callState {
        case "INCOMING CALL":
            Text("Incoming Call From Wes Ray")
                .foregroundColor(.green)
            
        case "ACTIVE":
            Text("Call Active with Wes Ray")
                .foregroundColor(.blue)
            
        case "ENDED":
            Text("Call Ended")
                .foregroundColor(.gray)
            
        default:
            Text("Unkown State")
        }
    }
}

