# CallESP32

A Bluetooth-based whole-home call display system. An ESP32 microcontroller pairs with an iPhone using the **HFP Hands-Free Profile** — the same protocol used by car hands-free kits — to receive incoming call events and caller ID directly from the phone's operating system, with no special Apple entitlements required. A companion iOS app handles device provisioning over BLE and manages per-device call filtering. A macOS simulator allows the full provisioning and call-event workflow to be tested without physical hardware.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Components](#components)
  - [iOS App — CallESP32](#ios-app--callesp32)
  - [macOS Simulator — ESP32Simulator](#macos-simulator--esp32simulator)
  - [ESP32 Firmware](#esp32-firmware)
- [Provisioning Flow](#provisioning-flow)
- [Call Filtering](#call-filtering)
- [BLE UUID Reference](#ble-uuid-reference)
- [QR Code Format](#qr-code-format)
- [Setup & Build](#setup--build)
  - [iOS App](#ios-app-setup)
  - [macOS Simulator](#macos-simulator-setup)
  - [ESP32 Firmware](#esp32-firmware-setup)
- [Hardware Requirements](#hardware-requirements)
- [Software Requirements](#software-requirements)
- [Project Structure](#project-structure)
- [Development Notes](#development-notes)

---

## How It Works

When a call arrives on the iPhone, the phone's Bluetooth stack sends HFP AT commands (`RING`, `+CLIP`, `+CIEV`) directly to any paired HFP Hands-Free Unit in range. The ESP32 receives these commands, checks the caller number against a configured filter, and alerts accordingly. The iOS companion app is not involved in this data path at all — it is only used once, during provisioning, and then steps aside entirely.

This design avoids a fundamental iOS limitation: `CXCallObserver` can observe call state but cannot deliver the caller's phone number to a third-party app. By delegating call reception to hardware running a proper HFP HF stack, the system receives full caller ID with no entitlement workarounds.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  PROVISIONING  (one-time, BLE)                                      │
│                                                                     │
│  iOS App  ──── BLE GATT Write (SSID + Password) ────►  ESP32       │
│           ◄─── BLE GATT Notify (WIFI_OK / WIFI_FAIL) ──            │
│                                                                     │
│  iOS App  ──── BLE GATT Write (FilterMode + Whitelist) ──►  ESP32  │
│           ◄─── BLE GATT Notify (CONFIG_OK) ──────────────          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  CALL EVENTS  (ongoing, Bluetooth Classic HFP)                      │
│                                                                     │
│  iPhone  ──── HFP AT Commands (RING, +CLIP, +CIEV) ────►  ESP32   │
│               Caller ID, call state, call end                       │
│               iOS App has NO involvement in this path               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  DEVELOPMENT SIMULATION  (macOS Simulator)                          │
│                                                                     │
│  iOS App  ──── Real BLE provisioning ────────────────►  Mac        │
│                (identical protocol to real ESP32)                   │
│                                                                     │
│  Developer ─── Manual call event injection ──────────►  Mac        │
│                Generates accurate HFP AT commands                   │
│                in the serial monitor                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Components

### iOS App — CallESP32

The companion app for iPhone. Written in SwiftUI targeting iOS 16+.

**Responsibilities:**
- Scan for ESP32 devices via BLE (QR code or manual 4-character ID entry)
- Deliver WiFi credentials to the device over a secure GATT write sequence
- Guide the user through HFP pairing in iOS Bluetooth Settings
- Manage a list of provisioned devices (rename, re-provision, delete)
- Configure per-device call filtering (filter mode + whitelist) and auto-sync to the device over BLE whenever settings change

**What it does not do:**
- Observe, intercept, or relay phone calls in any way
- Require any special Apple entitlements (only standard Bluetooth and Camera permissions)
- Remain running for normal call operation

**Key files:**

| File | Purpose |
|---|---|
| `BluetoothManager.swift` | BLE central — provisioning scan and GATT write sequence |
| `DeviceManager.swift` | BLE central — post-provisioning management sync (filter/whitelist) |
| `ProvisioningView.swift` | Multi-step provisioning UI with QR scanner |
| `DeviceSettingsView.swift` | Per-device filter mode and whitelist management |
| `FilterMode.swift` | `FilterMode` enum, `WhitelistEntry` model, `SyncState` |
| `DeviceStore.swift` | Persists provisioned device list to UserDefaults |
| `QRScannerView.swift` | AVFoundation camera QR scanner |
| `ContactPickerView.swift` | `CNContactPickerViewController` wrapper for whitelist population |

---

### macOS Simulator — ESP32Simulator

A macOS development tool that replaces the physical ESP32 for testing. Written in SwiftUI targeting macOS 13+.

**BLE provisioning half — functionally equivalent to real hardware:**

The simulator runs a real `CBPeripheralManager` GATT server advertising the same provisioning service UUID as the iOS app expects. An iPhone running the CallESP32 app cannot distinguish the Mac from a real ESP32 during provisioning. It receives SSID and password writes, simulates a 1.5-second WiFi join delay, and sends `WIFI_OK` or `WIFI_FAIL` via BLE notify.

**HFP call simulation half — accurate content, manually triggered:**

The simulator cannot perform real HFP because macOS apps have no access to the Bluetooth Classic profile layer — the OS owns HFP connections entirely. What it does instead is inject the exact AT command sequences a real iPhone would send over HFP to a paired HF unit. These are the strings your firmware must parse: `RING`, `+CLIP: "number",type`, `+CIEV: callsetup,1`, `+CIEV: call,1`, etc. The serial monitor output is a ground-truth reference for firmware development.

**Key features:**
- Phosphor-green OLED-style simulated device display
- Dark-terminal serial monitor with `[BLE]`, `[HFP]`, and `[SYS]` tagged entries
- QR code generated from `BTPROV:XXXX` using CoreImage — scannable directly from the Mac screen
- Call control panel: Incoming, Answer, End Call buttons with US/UK/DE/Blocked presets
- Filter config panel showing current mode and whitelist received from the iOS app
- Management BLE service receives filter config from the iOS app and updates call simulation in real time

**Key files:**

| File | Purpose |
|---|---|
| `PeripheralManager.swift` | BLE GATT server — provisioning + management services |
| `CallSimulator.swift` | HFP AT command generation and whitelist filtering |
| `DeviceDisplayView.swift` | Simulated OLED device screen |
| `SerialMonitorView.swift` | Dark-terminal AT command and BLE event log |
| `QRCodeView.swift` | Scannable QR code generated via `CIQRCodeGenerator` |
| `WhitelistConfigView.swift` | Shows active filter config received from iOS |

---

### ESP32 Firmware

ESP-IDF 5.x firmware for the ESP32-WROOM-32D. Written in C.

**Responsibilities:**
- Advertise as a BLE peripheral during provisioning mode, accept WiFi credentials over GATT, join the network, and report the result
- Operate as an HFP Hands-Free Unit — the same role as a car's built-in hands-free system
- Receive `RING` and `+CLIP` AT commands from the paired iPhone over HFP and output call information to the serial monitor
- Apply filter mode and whitelist decisions locally on the device
- Accept management configuration updates from the iOS app over BLE at any time
- Persist all configuration to NVS so it survives power cycles

**Entering provisioning mode:**
Hold the BOOT button (GPIO0) for 3 seconds at any time. The device clears its stored WiFi credentials and begins advertising the provisioning BLE service.

**Key files:**

| File | Purpose |
|---|---|
| `main/main.c` | Entry point, state machine, button task |
| `main/bt_gatt.c/h` | BLE GATT server — provisioning + management services |
| `main/hfp_handler.c/h` | Classic BT GAP, HFP HF client, call filtering |
| `main/wifi_manager.c/h` | WiFi connection with 5-retry logic |
| `main/nvs_manager.c/h` | NVS read/write for all persistent state |
| `sdkconfig.defaults` | Build config — enables Bluedroid, HFP HF, BLE GATT |

---

## Provisioning Flow

The provisioning sequence is identical whether using the macOS simulator or real ESP32 hardware:

```
1.  User holds BOOT button on device (or device has no credentials)
    → Device advertises BLE provisioning service UUID

2.  User opens iOS app → taps Add Device
    → Points camera at QR code  OR  types 4-char device ID manually
    → App scans BLE, matches device by service UUID
    → App connects

3.  User enters WiFi SSID and password in app
    → App writes SSID to GATT characteristic (with response)
    → App writes Password to GATT characteristic (with response)
    → App subscribes to Status notify characteristic
    → Device attempts WiFi connection

4.  Device joins WiFi → sends WIFI_OK notify
    OR fails after 5 attempts → sends WIFI_FAIL notify

5.  iOS app shows HFP pairing guidance:
    Open Settings → Bluetooth → tap device name → pair
    (This step connects the HFP Hands-Free profile at OS level)

6.  Device appears in provisioned device list with HFP status badge
```

---

## Call Filtering

Filtering is performed on the ESP32 in firmware, not in the iOS app. When a `+CLIP` AT command arrives over HFP, the firmware normalises the caller number (strips all non-digit characters) and evaluates it against the configured filter mode:

| Mode | Behaviour |
|---|---|
| **Normal** | All incoming calls trigger an alert on this device |
| **Whitelist** | Only calls from numbers in the whitelist trigger an alert |
| **Silent** | No calls trigger an alert — device is completely quiet |

The whitelist supports up to **8 numbers per device**. Numbers are stored as digit-only strings in NVS, normalised at write time. This means `"+1 (408) 555-1234"`, `"14085551234"`, and `"408-555-1234"` all match the same entry.

**Scenario examples:**

- *Work-from-home:* All devices set to Whitelist mode with 8 family numbers. Spam calls are silently ignored system-wide; family calls ring every device.
- *Focused work session:* Office device set to Silent mode. Kitchen and bedroom devices remain on Normal or Whitelist. Only the office device is quieted — no other device is affected.

Config changes are pushed from the iOS app to the device over a separate BLE management connection. The app auto-syncs whenever settings are saved, with a 1.5-second debounce so rapid edits batch into a single sync attempt.

---

## BLE UUID Reference

These UUIDs must match exactly across the iOS app, macOS simulator, and ESP32 firmware. They are defined in `BluetoothManager.swift`, `PeripheralManager.swift` (macOS), and `bt_gatt.c`.

### Provisioning Service

| Role | UUID |
|---|---|
| Service | `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` |
| SSID Characteristic (Write) | `BEB5483E-36E1-4688-B7F5-EA07361B26A8` |
| Password Characteristic (Write) | `BEB5483F-36E1-4688-B7F5-EA07361B26A8` |
| Status Characteristic (Notify) | `BEB54840-36E1-4688-B7F5-EA07361B26A8` |

Status notify payload: `WIFI_OK` on success, `WIFI_FAIL` on failure.

### Management Service

| Role | UUID |
|---|---|
| Service | `F1E2D3C4-B5A6-9780-FEDC-BA0987654321` |
| Filter Mode Characteristic (Write) | `F1E2D3C4-B5A6-9780-FEDC-BA0987654322` |
| Whitelist Characteristic (Write) | `F1E2D3C4-B5A6-9780-FEDC-BA0987654323` |
| Confirm Characteristic (Notify) | `F1E2D3C4-B5A6-9780-FEDC-BA0987654324` |

Filter mode write payload: `ALL`, `WHITELIST`, or `NONE` (plain UTF-8 string).

Whitelist write payload: comma-separated digit-normalised phone numbers, e.g. `14085551234,447911123456`. Empty string clears the whitelist.

Confirm notify payload: `CONFIG_OK`.

> **Note:** All 128-bit UUIDs in ESP-IDF Bluedroid are stored in little-endian byte order (the canonical string representation reversed). The byte arrays in `bt_gatt.c` reflect this. Do not change them unless you change the iOS app and simulator UUIDs in lockstep.

---

## QR Code Format

The QR code affixed to or displayed by each device encodes:

```
BTPROV:XXXX
```

Where `XXXX` is the last 4 uppercase hexadecimal characters of the device's Bluetooth MAC address. The macOS simulator displays this string in the device preview footer and renders it as a scannable QR code using CoreImage.

The iOS app parses this format in `ProvisioningView.parseQRCode(_:)`, validates that `XXXX` is exactly 4 hex characters, and uses it as the device ID for BLE scanning.

---

## Setup & Build

### iOS App Setup

**Requirements:** Xcode 15+, iOS 16+ device (the Xcode Simulator does not support CoreBluetooth scanning)

1. Create a new Xcode project: **iOS → App**, SwiftUI, Swift
2. Set Deployment Target to **iOS 16.0**
3. Add all `.swift` files from the `CallESP32/` directory to the target
4. In `Info.plist`, add:
   - `NSBluetoothAlwaysUsageDescription` — reason string for Bluetooth access
   - `NSCameraUsageDescription` — reason string for QR scanner camera access
5. No special entitlements are required
6. Build and run on a physical iPhone

> The iOS Simulator cannot be used for BLE testing. Run on a real device.

---

### macOS Simulator Setup

**Requirements:** Xcode 15+, macOS 13+

1. Create a new Xcode project: **macOS → App**, SwiftUI, Swift
2. Set Deployment Target to **macOS 13.0**
3. Add all `.swift` files from the `ESP32Simulator/` directory to the target
4. In **Signing & Capabilities**, click `+` and add the **Bluetooth** capability. This is mandatory — without it `CBPeripheralManager` reports `.unauthorized` and advertising never starts.
5. In `Info.plist`, add `NSBluetoothAlwaysUsageDescription` with a reason string
6. Build and run

**First run:** Click **Start Advertising** in the bottom-left corner of the window. The QR code appears and the serial monitor logs advertising start. The device ID (`BTPROV:XXXX`) is shown in the display footer.

---

### ESP32 Firmware Setup

**Requirements:** ESP-IDF 5.x, ESP32-WROOM-32D or compatible ESP32 board with Bluetooth Classic support

```bash
# Install ESP-IDF 5.x (if not already installed)
# See: https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/

# Source the environment
. $HOME/esp/esp-idf/export.sh

# Navigate to the firmware directory
cd ESP32_Firmware/

# Set the target chip
idf.py set-target esp32

# Build
idf.py build

# Flash and open serial monitor (replace port as needed)
idf.py -p /dev/cu.usbserial-XXXX flash monitor
```

**First boot:** The device prints its name (`ESP32:XXXX`) and QR payload (`BTPROV:XXXX`) to the serial monitor. It immediately becomes discoverable in iOS Bluetooth Settings for HFP pairing. It also enters provisioning mode automatically since no WiFi credentials are stored.

**Re-provisioning:** Hold the BOOT button (GPIO0) for 3 seconds at any time to clear credentials and re-enter provisioning mode.

---

## Hardware Requirements

| Component | Specification |
|---|---|
| Microcontroller | ESP32-WROOM-32D (or any ESP32 variant with Bluetooth Classic + BLE) |
| Bluetooth | Dual-mode: Bluetooth Classic (BR/EDR) for HFP + BLE for provisioning |
| Flash | 4MB minimum (standard on WROOM-32D) |
| RAM | 520KB SRAM (standard) |
| Development board | ESP32-DevKitC or equivalent (provides USB-UART for flashing) |
| Provisioning button | BOOT button (GPIO0) — present on all standard ESP32 devkit boards |

> **Important:** ESP32-S2, ESP32-S3, and ESP32-C3 variants do **not** support Bluetooth Classic (they are BLE-only). HFP requires Bluetooth Classic. Only use an **ESP32** or **ESP32-WROOM** variant.

---

## Software Requirements

| Component | Requirement |
|---|---|
| iOS App | Xcode 15+, Swift 5.9+, iOS 16+ deployment target |
| macOS Simulator | Xcode 15+, Swift 5.9+, macOS 13+ deployment target |
| ESP32 Firmware | ESP-IDF **5.x** (5.0 or later) |
| ESP32 Toolchain | `xtensa-esp32-elf-gcc` (installed with ESP-IDF) |
| iPhone for testing | iOS 16+, physical device required (Simulator has no BLE radio) |

---

## Project Structure

```
CallESP32/                          iOS companion app
├── BluetoothManager.swift          BLE provisioning central
├── DeviceManager.swift             BLE management sync engine
├── CallDisplayApp.swift            App entry point
├── ContentView.swift               Device list + navigation
├── ProvisioningView.swift          Multi-step provisioning flow
├── DeviceSettingsView.swift        Per-device filter + whitelist UI
├── QRScannerView.swift             AVFoundation camera QR scanner
├── ContactPickerView.swift         CNContactPicker wrapper
├── FilterMode.swift                FilterMode, WhitelistEntry, SyncState
├── ProvisionedDevice.swift         Device data model
└── DeviceStore.swift               UserDefaults persistence

ESP32Simulator/                     macOS development simulator
├── ESP32SimulatorApp.swift         App entry point
├── SimulatorViewModel.swift        Coordinator — log routing + config wiring
├── PeripheralManager.swift         BLE GATT server (prov + management)
├── CallSimulator.swift             HFP AT command generation + filtering
├── ContentView.swift               Root layout
├── DeviceDisplayView.swift         Simulated OLED display
├── SerialMonitorView.swift         AT command + BLE event log
├── QRCodeView.swift                Scannable QR code (CoreImage)
├── CallControlView.swift           Incoming / Answer / End call panel
├── WhitelistConfigView.swift       Active filter config display
└── LogEntry.swift                  Shared log entry model

ESP32_Firmware/                     ESP32 firmware (ESP-IDF 5.x)
├── CMakeLists.txt
├── sdkconfig.defaults              BT Classic + BLE + WiFi build config
└── main/
    ├── CMakeLists.txt
    ├── main.c                      Entry point, state machine, button task
    ├── bt_gatt.c/h                 BLE GATT server — both services
    ├── hfp_handler.c/h             HFP HF client + call filtering
    ├── wifi_manager.c/h            WiFi connection with retry
    └── nvs_manager.c/h             NVS credential + config storage
```

---

## Development Notes

### Why HFP instead of CXCallObserver

`CXCallObserver` (CallKit) can observe call state changes on iOS but cannot deliver the caller's phone number to a third-party app. `CXCall` exposes only boolean state flags. The only way to receive caller ID from an iPhone without special carrier or VoIP entitlements is through the HFP AT command `+CLIP`, which the phone sends to any paired Bluetooth HF unit. The ESP32 receives this at the hardware level, bypassing the app entirely.

### Why BLE for provisioning, not AP mode or Bluetooth Classic pairing setup

BLE provisioning is handled entirely within the iOS app using CoreBluetooth, with no special entitlements. It does not require the user to manually leave the app to change network settings, and it works symmetrically on Android if a companion app is built for that platform. Classic BT provisioning would require Bluetooth Classic APIs that are not exposed to third-party iOS apps.

### UUID byte ordering in ESP-IDF Bluedroid

All 128-bit UUIDs in `bt_gatt.c` are stored as little-endian byte arrays — the canonical UUID string representation reversed byte by byte. This is a Bluedroid requirement. If you change any UUID, ensure the byte array is correctly reversed. The comment block at the top of `bt_gatt.c` shows the full conversion example.

### macOS BLE peripheral advertising limitation

macOS `CBPeripheralManager` does not reliably include service UUIDs in the primary advertisement packet in a way that iOS `withServices:` filtered scanning recognises. The iOS app works around this by scanning with `withServices: nil` and checking `CBAdvertisementDataServiceUUIDsKey` in the `didDiscover` callback. Additionally, macOS advertises its system Bluetooth name (e.g. `"Mac"`) instead of the custom name set in `CBAdvertisementDataLocalNameKey`. The discovery logic in `BluetoothManager` handles this by matching on service UUID first and only validating the name suffix when the device advertises an `ESP32:` prefixed name.

### HFP audio routing

The firmware initialises the HFP HF profile without audio routing (`CONFIG_BT_HFP_AUDIO_DATA_PATH_HCI=n`). This device is a call display, not a headset, and no audio is captured or played. iOS will still route the call audio through the phone's speaker and microphone normally. The HFP connection is used solely to receive the metadata AT commands.
