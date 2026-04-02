//
//  BLEPeriphManager.swift
//  BLESim
//
//  Created by developer on 1/11/26.
//

import Foundation
import CoreBluetooth

final class BLEPeriphManager: NSObject, ObservableObject {
    
    private var peripheralManager: CBPeripheralManager!
    private var callStateCharacteristic: CBMutableCharacteristic!
    private var notifyCharacteristic: CBMutableCharacteristic!
    
    //@publijsed allows for updating in UI
    @Published var callState: String = "null"
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func sendCallUpdate(_ message: String) {
        guard peripheralManager.state == .poweredOn else { return }
        
        let data = message.data(using: .utf8)!
        peripheralManager.updateValue(
            data,
            for: notifyCharacteristic,
            onSubscribedCentrals: nil
        )
    }
}

extension BLEPeriphManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {	
            print("BLE not available")
            return
        }
    
        setupService()
        startAdvertising()
        
    }
    
    private func setupService() {
        let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        
        callStateCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        
        notifyCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"),
            properties: [.notify],
            value: nil,
            permissions: []
        )
        
        let service = CBMutableService(
            type: serviceUUID,
            primary: true
        )
        service.characteristics = [callStateCharacteristic, notifyCharacteristic]
        
        peripheralManager.add(service)
    }
    
    private func startAdvertising() {
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [
            CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        ],
            CBAdvertisementDataLocalNameKey: "ESP32-CallDisplay"
        ])
    }
    
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            guard let value = request.value,
                  let message = String(data: value, encoding: .utf8)
            else { continue }
            
            print("received from IOS:", message)
            
            DispatchQueue.main.async {
                self.callState = message
            }
            
            peripheralManager.respond(to: request, withResult: .success)
        }
    }
    
}
