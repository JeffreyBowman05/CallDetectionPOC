//
//  CallDisplayApp.swift
//  CallESP32
//
//  Created by developer on 1/11/26.
//

import SwiftUI

@main

struct CallDisplayApp: App {
    
    //Define BLE central as an Object
    @StateObject private var ble = BluetoothManager()
    
    private let callObserver = CallObserver()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .onAppear {

                    
                    callObserver.onChange = { state in
                        
            
                    
                        ble.sendCallState(state)
                    }
                }
        }
    }
}


