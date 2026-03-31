# CallDetectionPOC

This Github contains code and usage information for the CallDetection Proof-of-Concept. So far there is solely IOS design. Andriod is being worked on currently.

## Usage

Have all files in same directory. Run each App and BLE-Sim on its own instance of Xcode, CallDetect App is designed for IOS 26.4. BLE-Sim is designed for MacOS 26.4.

#### Steps for Use (IOS)

1. Run BLE-Sim first on MacOS and allow to initialize.
2. Start CallDetect App on phone and once started it'll run in foreground, background, and while phone is locked.
3. Once a call is Incoming/Active/Ended the BLE-Sim will update accordingly.

## Known Bugs

Contact Name info is currently unobtainable due to Apple's sandboxing and privacy regulation. Workarounds are in the process of being tested.
