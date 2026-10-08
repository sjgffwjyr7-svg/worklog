# Validation status — 12 September 2026

## Completed in the preparation workspace

- Parsed the complete Xcode project and checked object references, Swift source membership and shared configuration links.
- Parsed the app Info.plist, privacy manifest, asset metadata and shared test scheme.
- Checked Bash syntax for the build runner and self-contained installer.
- Exercised the runner with mocked Apple commands: default test/build/launch, paths containing spaces, repeat-build identity preservation, failed-test blocking, incomplete Xcode setup, missing-runtime download, no-download failure, device build, archive build, explicit test skip, invalid team, missing team and non-Mac rejection.
- Checked the actual embedded source archive, checksums, extraction, preservation of edits on rerun, conflicting-destination refusal and rejection of a corrupted payload.

The mock checks validate script control flow only. They do not execute Xcode, Swift compilation, XCTest, device signing or Simulator.

## To be run by the command on your Mac

- Native Swift and App Intents metadata compilation using Apple's iOS SDK.
- XCTest for weekday/overnight schedules, July financial-year rollover, cross-year GPS distance, private exclusions/corrections, persistence, description memory, corrupt-file protection, accountant CSV fields/escaping and backup/restore.
- Actual Simulator install and launch.
- Signed build/install when device mode is selected.

See the resulting build/build-*.log and Tests-*.xcresult on your Mac for those results. Physical camera scanning, voice recognition, permissions, locked-screen GPS, odometer comparison and QNAP backup recovery are still pending; follow DEVICE-TESTS.md.


## Face ID revision

Added LocalAuthentication app lock, NSFaceIDUsageDescription, background relock, a privacy window, authenticated settings changes and Siri access checks. Project structure and installer packaging checks were rerun. Added four XCTest cases for authentication state and persistence; native execution and all Face ID hardware checks remain pending on an Apple build host/device.
