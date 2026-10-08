# Worklog — one-command setup

## First run on a Mac

1. Install **full Xcode** from the Mac App Store. Open it once, review Apple's licence and finish installing its components. Use an Xcode version compatible with your Mac and your iPhone's installed iOS version. This app targets iOS 17 or later.
2. Download `Create-Worklog-iOS.command` into Downloads.
3. Open **Terminal** on the Mac and paste:

```bash
bash "$HOME/Downloads/Create-Worklog-iOS.command"
```

The file contains the complete native project: SwiftUI screens, GPS recorder, schedule, Siri App Intents, document scanner, local records, exports, tests, icon, privacy manifest and configuration. It verifies its embedded archive, extracts to `~/Worklog-iOS`, configures a unique app identifier, runs XCTest in a dedicated iPhone Simulator, installs and launches the simulator app, and opens the project in Xcode. A missing Simulator runtime is downloaded from Apple; it can be several GB. No Homebrew, XcodeGen, CocoaPods, npm, backend or API key is required.

This file cannot build on an iPhone or Windows. The Mac must already have Xcode installed; the command cannot accept Apple's licence, sign in to your Apple account, trust a phone or enable its Developer Mode for you.

If you downloaded the ZIP source instead, unzip it and run:

```bash
bash "$HOME/Downloads/Worklog-iOS/Build-Worklog.command"
```

Use the actual unzipped location if it differs. Simulator camera scanning and real Siri/GPS behaviour require a physical iPhone. You can import a PDF in the Simulator to test invoice records.

## Run on your iPhone 14 Pro

After the simulator build passes:

1. Add your Apple account in **Xcode → Settings → Accounts**.
2. Connect your iPhone by USB, unlock it, choose **Trust** if asked, and pair it in Xcode's Devices window / Device Hub.
3. If requested, enable **Settings → Privacy & Security → Developer Mode** on the iPhone and complete its restart/confirmation.
4. In Xcode choose the Worklog target, **Signing & Capabilities**, your **Team**, and your iPhone as the run destination. Press **Run**.

This is the easiest first device install. Alternatively, once the Apple account and device are ready, run:

```bash
bash "$HOME/Worklog-iOS/Build-Worklog.command" --mode device --team ABC123DE45 --device YOUR_IPHONE_UDID
```

Replace both example values. The team ID is Apple's 10-character development-team identifier; the iPhone hardware UDID is the **Identifier** in Xcode's device details. `xcrun xctrace list devices` also lists physical devices and their identifiers. The command runs simulator tests, builds with automatic signing for that phone, installs with `devicectl` and launches the app. Apple's provisioning service may require network access.

Keep the generated `Config/Local.xcconfig` and app bundle identifier for later installs. A different identifier installs a separate app with separate records. If signing was configured directly in Xcode, use Xcode for subsequent installs or also pass the same team to the script. A Personal Team may be used where Apple permits development signing; TestFlight requires the appropriate Apple Developer Program membership. Development installs can need re-signing. Back up records before deleting or replacing the app.

## Subsequent builds and editing

```bash
bash "$HOME/Worklog-iOS/Build-Worklog.command"
```

Edit the Swift files in Xcode and run the same command again. The installer never overwrites an existing project. Rerunning the same installer reuses its previously extracted project, including your edits. For a different installer revision, use a new directory and bring over your changes deliberately:

```bash
bash "$HOME/Downloads/Create-Worklog-iOS.command" --directory "$HOME/Worklog-iOS-next"
```

To extract the source without building (also works on Linux with Bash, tar and base64):

```bash
bash "$HOME/Downloads/Create-Worklog-iOS.command" --extract-only --directory "$HOME/Worklog-iOS-source"
```

Use `--no-download` to prevent an automatic Simulator download, `--no-open` for builds without opening app windows, and `--no-tests` only when deliberately skipping the simulator test gate. All flags are listed with `--help`.

## Prepare a distribution archive

```bash
bash "$HOME/Worklog-iOS/Build-Worklog.command" --mode archive --team ABC123DE45
```

This runs tests and creates a signed `.xcarchive` in `build/`. It opens the archive in Xcode Organizer; it does **not** upload. Configure your app record, distribution signing and App Store privacy details in your Apple account, then validate and distribute using Organizer when ready. An archive is not an installable IPA. TestFlight and App Store acceptance are not guaranteed by a successful build.

## If a step fails

| Message | Next action |
|---|---|
| Requires a Mac / full Xcode | Use a Mac; Command Line Tools alone cannot build an iOS app. |
| First-launch setup incomplete | Open Xcode, finish the licence/component prompts and rerun. |
| No iOS runtime | Let the command download it, or install iOS in Xcode Settings → Components (Platforms on older Xcode). |
| Signing / provisioning error | Check the Apple account, selected Team, unique app ID, device pairing and Developer Mode in Xcode. |
| Device unavailable | Update Xcode to support the phone's iOS version; unlock, reconnect and pair the phone. |
| Compiler / XCTest failure | Open the generated project and `build/build-*.log`. No successful app build is claimed until these pass. |
| Another build may be running | Let it finish. Only if no build is running, remove the empty `build/.worklog-build-lock` folder. |
| Existing destination | Rerun the extracted `Build-Worklog.command`, or choose a new `--directory`; your existing files are preserved. |

## Verification status of this delivery

The packaging and shell workflows are checked in the preparation environment. **Xcode and Apple's SDK are not available there**, so the native app and Swift tests have not been compiled or run there. The included runner performs those checks on your Mac. Complete `DEVICE-TESTS.md` before relying on the app for records. QNAP transfer is manual via Files / Qfile Pro; invoice fields are entered manually after scanning.

Apple references checked 12 September 2026:

- [Run an app on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Xcode command-line tools](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [Install additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)

