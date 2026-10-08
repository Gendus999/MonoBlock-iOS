# MonoBlock for iOS

Native SwiftUI port of the Android MonoBlock game. Open `MonoBlock.xcodeproj` in Xcode, select the `MonoBlock` scheme, then build or run on an iOS Simulator (deployment target: iOS 16).

The GitHub Actions workflow builds the simulator app and runs `MonoBlockTests` on macOS. Game preferences and per-assistant high scores are stored locally with `UserDefaults`; the active board is intentionally transient, matching the Android app.
