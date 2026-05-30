# CallESP32 + ESP32Simulator — Setup & Code Walkthrough

This document covers everything you need to set up both projects, understand how
they connect, and review the key decisions in each file before your first test run.

---

## Part 1 — System Architecture

Before touching Xcode, it helps to understand how the two projects relate to each
other and to the real hardware.

```
 ┌─────────────────────────┐        BLE (Provisioning)        ┌──────────────────────────┐
 │   iOS App (CallESP32)   │ ────────────────────────────────► │  ESP32Simulator (macOS)  │
 │   CBCentralManager      │ ◄──────────── WIFI_OK ────────── │  CBPeripheralManager     │
 └─────────────────────────┘                                   └──────────────────────────┘

 ┌─────────────────────────┐       HFP (Bluetooth Classic)    ┌──────────────────────────┐
 │   iPhone                │ ────────────────────────────────► │  Real ESP32 Hardware     │
 │   Audio Gateway (AG)    │ ◄── RING / +CLIP / +CIEV ─────── │  Hands-Free Unit (HF)    │
 └─────────────────────────┘                                   └──────────────────────────┘
```

The iOS app talks to the simulator (or real ESP32) over BLE only for provisioning.
Once provisioned, BLE is done. The real ESP32 then pairs with the iPhone over
Bluetooth Classic using the HFP profile, receiving call events directly from the
phone's OS — the iOS app has no further involvement in that data path.

The macOS simulator replaces the ESP32 for BLE provisioning tests, and replaces
HFP with manually injected AT commands so you can test call scenarios at your desk
without real phone calls.

---

## Part 2 — iOS App Setup (CallESP32)

### Step 1 — Create the Xcode Project

Open Xcode → File → New → Project → iOS → App.

- Product Name: `CallESP32`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment Target: iOS 16.0

Delete the auto-generated `ContentView.swift`. You will replace it with the
refactored version from this project.

### Step 2 — Add the Source Files

Add all seven `.swift` files to the project target:

```
BluetoothManager.swift
ProvisionedDevice.swift
DeviceStore.swift
CallDisplayApp.swift
ContentView.swift
ProvisioningView.swift
QRScannerView.swift
```

`CallObserver.swift` from the original project is intentionally absent. It has been
replaced by the HFP profile at the hardware level and should not be added back.

### Step 3 — Info.plist Entries

Two keys are required. In Xcode, select your `Info.plist` and add:

| Key | Value |
|---|---|
| `NSBluetoothAlwaysUsageDescription` | `"Used to provision your call display device."` |
| `NSCameraUsageDescription` | `"Used to scan the QR code on your call display device."` |

Without `NSBluetoothAlwaysUsageDescription`, CoreBluetooth will immediately fail
with an authorization error and never scan. Without `NSCameraUsageDescription`, the
QR scanner will crash on first access.

### Step 4 — No Special Entitlements Needed

This is one of the architectural advantages of the new design. Because the iOS app
only uses CoreBluetooth (BLE), no special Apple entitlements are required. HFP
pairing happens at the OS level between the iPhone and the ESP32 hardware — the app
is not involved and needs no access to it.

### Step 5 — Build and Run

The app will request Bluetooth permission on first launch. Approve it. The camera
permission is requested the first time the user opens the provisioning sheet and
taps the QR scanner.

---

## Part 3 — iOS App Code Walkthrough

### BluetoothManager.swift

This is the most important file. It owns the entire BLE provisioning state machine.

**The 10-state machine.** `ProvisioningState` has ten cases: `idle`, `scanning`,
`connecting`, `discoveringServices`, `awaitingCredentials`, `writingSSID`,
`writingPassword`, `awaitingWiFiConfirmation`, `complete`, and `failed(String)`.
Each state maps to exactly one point in the provisioning sequence. The UI observes
`@Published var provisioningState` and responds to every transition.

**The GATT characteristic split.** The original code had one characteristic for
everything. The refactored version has three: one write-only characteristic for the
SSID, one write-only for the password, and one notify characteristic for the device
to send back the WiFi join result. This matches standard ESP32 provisioning
firmware patterns and makes each write unambiguous — the device always knows which
field it is receiving.

**The UUID constants.** Defined in the private enum `BLEUUID`. These four values
are the single most critical dependency between the iOS app and both the macOS
simulator and the real ESP32 firmware. They must match exactly in all three places.
The current values are:

```
Service:   4FAFC201-1FB5-459E-8FCC-C5C9C331914B
SSID:      BEB5483E-36E1-4688-B7F5-EA07361B26A8
Password:  BEB5483F-36E1-4688-B7F5-EA07361B26A8
Status:    BEB54840-36E1-4688-B7F5-EA07361B26A8
```

**Device discovery matching.** In `centralManager(_:didDiscover:)`, the app matches
peripherals using `name.uppercased().hasSuffix(targetID)`. This means it looks for
any device whose advertised name ends in the 4-character device ID (e.g., "ABCD"
matches "ESP32:ABCD"). This is intentionally loose — it matches the last 4 chars
regardless of what prefix the firmware uses.

**The 15-second scan timeout.** `scheduleScanTimeout()` creates a `Timer` that
fires if no matching device is discovered within 15 seconds. When it fires, the
state moves to `.failed(...)` with a user-facing message. Without this, the app
would scan silently forever if the device is not in provisioning mode.

**Password zeroing.** In `writePassword()`, `pendingPassword = nil` is called
immediately after the password data is encoded into a `Data` object. This clears
the String from memory as soon as possible after encoding. The actual bytes in the
`Data` will be freed when the write completes.

**The `isInProgress` flag.** The `ProvisioningState` enum has an `isInProgress`
computed property that returns `true` for all the "mid-flight" states. This is used
in `centralManagerDidUpdateState` to detect if Bluetooth was disabled partway
through a provisioning session, and to fire a failure event immediately instead of
leaving the UI frozen in a spinner.

**GATT write sequencing.** The sequence is chained through `didWriteValueFor`. When
the SSID write succeeds, `writePassword()` is called. When the password write
succeeds, `subscribeToStatus()` is called. When the status notification arrives with
"OK" in its payload, `complete` is set and the peripheral connection is closed. If
any write fails, `provisioningState` moves to `.failed(...)` immediately.

---

### ProvisionedDevice.swift

A simple `Codable` struct with one notable method: `reprovision(ssid:)`. This
mutating method updates the WiFi SSID and provisioning date when the user
re-provisions a device, and it resets `isHFPPaired` to `false`. The reason for
resetting the HFP flag is that re-provisioning may change the device's Bluetooth
identity, requiring the user to re-pair in iOS Settings.

`isHFPPaired` is a boolean the user manually confirms via the app — it is never
automatically detected. iOS provides no API to check whether a specific Bluetooth
device is paired as HFP.

---

### DeviceStore.swift

Persists devices to `UserDefaults` under the key `com.callESP32.provisioned_devices`
using `JSONEncoder/JSONDecoder`. UserDefaults was chosen over CoreData deliberately
— the expected device count is small (single digits), there are no relational
queries, and the simplicity of a flat `[ProvisionedDevice]` array is correct for
this use case.

The `add(_:)` method silently ignores duplicate `deviceID` values, preventing
double-registration if the user scans the same QR code twice. The `reprovision(id:ssid:)`
method finds the device by its persistent `UUID` and calls the mutating
`reprovision(ssid:)` method.

---

### CallDisplayApp.swift

The file shrank from its original 24 lines of wiring to 13 lines of setup. The
`CallObserver` is gone entirely. The file now only creates two `@StateObject`
instances — `BluetoothManager` and `DeviceStore` — and injects them into the
environment. Every view that needs them declares `@EnvironmentObject` and receives
them automatically.

---

### ContentView.swift

The root view owns the navigation stack and the sheet presentation. A few things
worth reviewing:

**HFP badge.** The `HFPBadge` view renders green ("HFP Active") or orange ("Pair
via Bluetooth") based on `device.isHFPPaired`. This badge is the user's reminder
that provisioning and HFP pairing are two separate steps. Many users will provision
successfully and then wonder why call events aren't arriving — the orange badge is
the signal that HFP pairing in iOS Settings is still needed.

**Re-provision routing.** The sheet is shared between "Add Device" and
"Re-Provision". The distinction is made by `deviceToReprovision: ProvisionedDevice?`
— if it is `nil`, the sheet is adding a new device; if it holds a device, the sheet
is re-provisioning it. `ProvisioningView` receives this as `existingDevice` and
adjusts its title, device ID pre-fill, and save behavior accordingly.

**Swipe action layout.** Leading swipe is re-provision (orange), trailing swipe is
delete (red with full-swipe enabled). These directions were chosen to make accidental
deletion harder — the more destructive action requires a deliberate right-to-left
swipe.

---

### ProvisioningView.swift

This is the most complex view file. It layers a local `ProvisioningStep` enum on
top of `BluetoothManager`'s `ProvisioningState` to handle UI-only steps that have
no BLE equivalent.

**Local vs BLE state.** `BluetoothManager` stops publishing new states at `.complete`
once WiFi is confirmed. But the UI still needs to show the HFP pairing guidance
screen and then the completion screen. These two states are local to
`ProvisioningView` and are never published by the BLE layer.

**State synchronisation.** `syncStep(from:)` is called in `.onChange(of: ble.provisioningState)`.
It maps BLE states to local steps. `.awaitingCredentials` → show the WiFi form.
`.writingSSID`, `.writingPassword`, `.awaitingWiFiConfirmation` → show the writing
spinner. `.complete` → show the HFP guidance screen. `.failed` → show the error
view. The local step enum is the source of truth for which view is displayed.

**QR code format.** `parseQRCode(_:)` expects the format `BTPROV:XXXX` where XXXX
is exactly 4 uppercase hexadecimal characters. The method validates the prefix,
extracts the ID, checks the length, and verifies all characters are hex digits. If
any check fails it returns `nil` and the scan is silently ignored — the camera
keeps running. Your ESP32's QR code must encode this exact format.

**Save routing.** `saveDevice()` checks `existingDevice`. If non-nil, it calls
`deviceStore.reprovision(id:ssid:)` to update the existing record. If nil, it
creates a new `ProvisionedDevice` and calls `deviceStore.add(_:)`.

---

### QRScannerView.swift

A `UIViewRepresentable` wrapping `QRCameraPreview`, a custom `UIView` that manages
an `AVCaptureSession`.

**Authorization gating.** `requestAccessAndConfigure()` is called before the
session starts. It checks `AVCaptureDevice.authorizationStatus(for: .video)` and
handles all four cases: already authorized (start immediately), not determined
(request access then start), denied, and restricted. The session only starts if
authorization is confirmed.

**Double-setup prevention.** `layoutSubviews()` is called by UIKit any time the
view's bounds change. Without the `isConfiguringSession` flag, a bounds change
during the async authorization callback could trigger a second session setup.

**Single-fire guarantee.** `hasScanned` is set to `true` and the session is stopped
in `metadataOutput(_:didOutput:)` before `onScanned` is called. This ensures the
callback fires exactly once per scan session even if the same QR code appears in
multiple frames before the session stops.

---

## Part 4 — macOS Simulator Setup

### Step 1 — Create the Xcode Project

File → New → Project → macOS → App.

- Product Name: `ESP32Simulator`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment Target: macOS 13.0

### Step 2 — Add the Source Files

Add all nine `.swift` files:

```
ESP32SimulatorApp.swift
LogEntry.swift
PeripheralManager.swift
CallSimulator.swift
SimulatorViewModel.swift
ContentView.swift
DeviceDisplayView.swift
SerialMonitorView.swift
CallControlView.swift
```

### Step 3 — Add the Bluetooth Capability

This is the most commonly missed step and will cause a silent failure at runtime.

In Xcode: select your project in the navigator → select the app target → tab
"Signing & Capabilities" → click the `+` button → search for "Bluetooth" → add it.

This adds `com.apple.security.bluetooth` to your entitlements file. Without it,
`CBPeripheralManager` will report `.unauthorized` in its state callback and the
simulator will never be able to advertise.

### Step 4 — Info.plist Entry

Add `NSBluetoothAlwaysUsageDescription` to `Info.plist` with a reason string such
as `"Used to simulate an ESP32 BLE peripheral for development."` macOS 12 and later
requires this key for apps using CoreBluetooth.

### Step 5 — Build and Run

On first launch, macOS will present a Bluetooth permission prompt. Approve it.
The app opens to the three-panel layout. The BLE status dot in the bottom-left
corner will be grey (idle) if Bluetooth is on, or red (unavailable) if it is off or
the capability was not added.

---

## Part 5 — macOS Simulator Code Walkthrough

### PeripheralManager.swift

The counterpart to the iOS app's `BluetoothManager`. Where the iOS app is a
`CBCentralManager` (scanner/client), this is a `CBPeripheralManager` (advertiser/server).

**`rebuildService()`** is called each time advertising starts. It calls
`manager.removeAllServices()` first, which is important for re-provisioning — if
you start advertising again without removing the old service, CoreBluetooth will
reject the `add(_:)` call with an error. Three `CBMutableCharacteristic` objects are
created fresh each time with the same UUIDs as the iOS app.

**The two paths to `beginWiFiSimulation()`** handle a timing ambiguity: the iOS app
writes SSID, then password, then subscribes to status. But the confirm-then-proceed
order means the subscription always comes last. However, for robustness, the code
handles both orders: if the subscription arrives before the password write,
`didSubscribeTo` stores `subscribedCentral` but does not start the timer (because
`pendingPassword` is still empty). When the password write arrives and the central
is already subscribed, `beginWiFiSimulation()` is called immediately in
`didReceiveWrite`. If the password arrives first and the central has not subscribed
yet, `beginWiFiSimulation()` is called in `didSubscribeTo` when the subscription
finally arrives.

**Connection inference.** `CBPeripheralManager` does not have a "central connected"
delegate callback — unlike `CBCentralManager` which has `didConnect`. The simulator
infers connection from the first write request: when `didReceiveWrite` fires and the
state is still `.advertising`, it transitions to `.centralConnected`. This matches
how Bluetooth peripherals actually work — the peripheral does not know a central is
present until the central initiates communication.

**`peripheralManagerIsReady(toUpdateSubscribers:)`** fires if a previous
`updateValue(_:for:onSubscribedCentrals:)` call returned `false` due to a full
transmit queue. In a real device, you would retry the notification here. In the
simulator it is logged so you can see if this occurs during testing.

---

### CallSimulator.swift

**AT command accuracy.** The commands generated here are exact. `RING` has no
parameters. `+CLIP` carries the phone number in quotes, followed by the address
type as an integer: 145 for international numbers (those starting with `+`), 129
for national numbers, and 128 for unknown/blocked. The `+CIEV` commands use the
standard HFP indicator indices: `call` tracks whether a call is active (0 or 1),
and `callsetup` tracks the setup state (0 = no setup, 1 = incoming).

**RING timer.** `triggerIncoming(rawNumber:)` fires one RING+CLIP pair immediately
and then schedules a `Timer` to repeat every 3 seconds. This matches the real
behaviour of a phone ringing — `RING` is sent repeatedly until the call is answered
or rejected. The `ringCount` increments with each repetition and is displayed on
the device screen and in the log note.

**Blocked number handling.** When `rawNumber` is empty, `sendRing(rawNumber:)` sends
`+CLIP: "",128` — an empty caller ID string with type 128 (unknown). The display
receives `<BLOCKED>` as the phone number (set in `triggerIncoming` via the
`displayNumber` logic). This accurately simulates a call from a number that has
enabled CLI restriction.

**Auto-return to idle.** After `triggerEnded()` sets state to `.ended`, a
`DispatchQueue.main.asyncAfter` with 2.5 seconds resets to `.idle`. The guard
`case .ended = self.callState` ensures this reset does not fire if the user
triggered a new call before the timer elapsed.

---

### SimulatorViewModel.swift

Owns both `PeripheralManager` and `CallSimulator` and routes their output callbacks
into a single `@Published var logEntries` array. The important pattern is in the
App file: all three objects (`vm`, `vm.peripheral`, `vm.callSimulator`) are injected
as separate environment objects. This means views subscribe only to the object they
care about — `DeviceDisplayView` observes `peripheral` and `callSim` directly
without going through `vm`, so a new log entry does not cause the display to
re-render.

---

### DeviceDisplayView.swift

The simulated OLED is a `ZStack` containing a dark `RoundedRectangle` (the screen
background) and a `VStack` of monospaced `Text` views (the content). The scanline
overlay is a `Path` drawn as horizontal lines every 3 points across the full screen
height, stroked with black at 12% opacity. It is marked `allowsHitTesting(false)` so
it does not intercept taps.

The footer line at the very bottom of the panel (outside the bezel) shows
`BTPROV:XXXX` — this is the exact string your ESP32's QR code must encode. During
development you can read this value off the simulator screen and type it into the
iOS app's manual entry field without needing a camera.

The status dot colour changes with call state: grey when idle and not provisioned,
green when idle and provisioned, orange when ringing, green when active, red when
ended.

---

### SerialMonitorView.swift

Uses `LazyVStack` inside `ScrollView` for efficient rendering — only visible log
rows are laid out, so the view does not slow down even with hundreds of entries.
Auto-scrolling is implemented via `ScrollViewReader` and `onChange(of: vm.logEntries.count)`,
which fires when a new entry is appended and scrolls to the last entry's `id` with
no animation (to avoid the scroll lag visible when using animation on fast-arriving
entries).

Log rows are `textSelection(.enabled)` so you can select and copy individual AT
commands directly from the monitor for use in firmware documentation.

---

### CallControlView.swift

Button enabled/disabled states enforce the valid state transitions. The Incoming
button requires `callState == .idle` — you cannot trigger a second incoming call
while one is already in progress. The Answer button requires `callState == .ringing`.
The End button accepts either ringing or active. The phone number field is disabled
whenever a call is in any non-idle state, preventing a mid-call number change.

---

## Part 6 — Critical Cross-Project Dependencies

These are the three points where both projects must agree exactly. A mismatch in
any of them will cause a silent failure during testing.

**1. The four BLE UUIDs.**
Defined as `BLEUUID` in `BluetoothManager.swift` (iOS) and `PeripheralManager.swift`
(macOS). They must be identical. If they differ, the iOS app's scan filter
`withServices: [BLEUUID.service]` will never discover the macOS simulator. Verify
by comparing them side by side before your first test.

**2. The device name suffix format.**
The macOS simulator advertises as `ESP32:XXXX` via `CBAdvertisementDataLocalNameKey`.
The iOS app discovers devices using `name.uppercased().hasSuffix(targetID)` where
`targetID` is the 4-character ID from the QR scan or manual entry. Both sides must
use the same suffix — the last 4 characters of the advertised name must match the
device ID the iOS app is searching for. If the simulator changes its name format,
the discovery match will fail silently.

**3. The QR code payload format.**
`ProvisioningView.parseQRCode(_:)` expects `BTPROV:XXXX` where XXXX is exactly 4
uppercase hex characters. The footer of `DeviceDisplayView` renders this exact
string. When you test with the real ESP32, its QR code must encode this format —
no surrounding braces, no JSON wrapper, just the raw string `BTPROV:A1B2`.

**4. The WiFi confirmation payload.**
`BluetoothManager.peripheral(_:didUpdateValueFor:)` checks
`message.uppercased().contains("OK")`. The macOS simulator sends `"WIFI_OK"`. Your
real ESP32 firmware must send a string containing "OK" over the status
characteristic's notify when WiFi joins successfully, and anything not containing
"OK" is treated as failure.

---

## Part 7 — End-to-End Testing Workflow

**Provisioning test (iOS app + macOS simulator):**

1. Build and run the macOS simulator on your Mac.
2. Click **Start Advertising** in the bottom-left of the simulator window.
3. The status dot turns orange and the serial monitor logs:
   `Advertising as ESP32:XXXX with provisioning service UUID.`
4. Build and run the iOS app on your iPhone.
5. Tap **Add Device**.
6. In the provisioning sheet, read the device ID from the simulator footer
   (`BTPROV:XXXX`) and type the 4-character `XXXX` into the manual entry field,
   then tap **Connect**. (Or point the camera at a QR code encoding `BTPROV:XXXX`.)
7. The iOS app scans, finds the Mac, connects, and moves to the WiFi credentials
   screen. The simulator log shows `SSID received` and `Password received`.
8. Enter any SSID and password in the iOS app and tap **Provision Device**.
9. After 1.5 seconds the simulator sends `WIFI_OK` and the iOS app advances to the
   HFP pairing guidance screen.
10. Tap **I'll do this later** to dismiss. The device appears in the ContentView
    list with an orange "Pair via Bluetooth" badge.

**Call event test (macOS simulator):**

1. With the simulator running, enter a phone number in the call control panel.
2. Click **Incoming**. The serial monitor shows `+CIEV: callsetup,1`, `RING`, and
   `+CLIP` entries. The device display shows `>> INCOMING CALL <<` with the number
   and a ring count.
3. Click **Answer**. The monitor shows `+CIEV: callsetup,0` and `+CIEV: call,1`.
   The display transitions to `[ CALL ACTIVE ]` with a running duration timer.
4. Click **End Call**. The monitor shows `+CIEV: call,0`. The display briefly shows
   `-- CALL ENDED --` before returning to idle.
5. Click the **Blocked** preset, then **Incoming**. The monitor shows
   `+CLIP: "",128`. The display shows `<BLOCKED>`.

These two tests together validate the full provisioning pipeline and verify that
your understanding of the HFP AT command sequence matches what the real ESP32
firmware will need to process.
