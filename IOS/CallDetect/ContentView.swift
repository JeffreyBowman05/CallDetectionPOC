//
//  ContentView.swift
//  CallESP32
//
//  Created by developer on 1/11/26.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var ble: BluetoothManager
    
    var body: some View {
        Text("Call Display")
    }
}
