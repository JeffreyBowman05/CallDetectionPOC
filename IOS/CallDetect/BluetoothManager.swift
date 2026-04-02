//
//  BluetoothManager.swift
//  CallESP32
//
//  Created by developer on 1/8/26.
//

import Foundation
import CoreBluetooth

//Manager, the obj
final class BluetoothManager: NSObject, ObservableObject {
    
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var callCharacteristic: CBCharacteristic?
    
    private let BLE_SERVICE_UUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let BLE_CHARACTERISTIC_UUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func sendCallState(_ message: String){
         guard let characteristic = callCharacteristic,
               let peripheral = esp32Peripheral else {
            return
        }
        
        let data = message.data(using: .utf8)!
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

//CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
            central.scanForPeripherals(withServices: [BLE_SERVICE_UUID])
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        esp32Peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([BLE_SERVICE_UUID])
    }
    
}

//PeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(
        _ peripheral : CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(
                [BLE_CHARACTERISTIC_UUID],
                for: $0
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == BLE_CHARACTERISTIC_UUID {
                callCharacteristic = characteristic
            }
        }
    }
}
