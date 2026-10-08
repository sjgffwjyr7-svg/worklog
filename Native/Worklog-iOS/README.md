# Worklog for iPhone

Native SwiftUI development project for iPhone 14 Pro and other iPhones running iOS 17 or later. This is source code, not a signed IPA or TestFlight build. It has not been compiled or run on an Apple device in this workspace; Xcode and the iOS SDK are unavailable here.

## Build and install without a Mac (Windows)

The repository includes `.github/workflows/ios.yml`. Each push to GitHub runs it on GitHub's macOS machines:

- **test**: compiles the app and runs the XCTest suite in an iPhone Simulator. This is the first real compile check.
- **ipa**: builds `Worklog-unsigned.ipa` for iPhone. Download it from the run's **Artifacts** section.

To install the IPA from a Windows PC, use [Sideloadly](https://sideloadly.io): install Apple iTunes and iCloud (the versions from Apple's website, not the Microsoft Store), connect the iPhone by USB, drag in the IPA, sign in with your Apple ID and press Start. On the iPhone, trust the developer profile in Settings → General → VPN & Device Management, and enable Developer Mode if asked. With a free Apple ID the install expires after 7 days and must be re-signed, and records survive re-signing only when the same bundle identifier is kept. A paid Apple Developer Program membership gives a 1-year signature and allows TestFlight, which avoids the weekly re-sign.

Back up your records (Storage → Save full backup) before replacing or re-signing the app.

## One-command setup and build

The separate **Create-Worklog-iOS.command** file contains this entire project. On a Mac with Xcode installed and its first-launch setup completed, save that file to Downloads and run:

```bash
bash "$HOME/Downloads/Create-Worklog-iOS.command"
```

It extracts to `~/Worklog-iOS`, prepares configuration, installs a missing iOS Simulator runtime, runs the XCTest suite, launches the simulator app and opens the project in Xcode. Your Apple account is only needed for a signed device build. If using this unzipped source directly, run `bash Build-Worklog.command` from this folder.

See [QUICK-START.md](Docs/QUICK-START.md) for iPhone installation, device/archive command options, repeat builds and troubleshooting. Follow [DEVICE-TESTS.md](Docs/DEVICE-TESTS.md) after installation. The generated build logs and `.xcresult` files distinguish actual Mac test results from the preparation checks.

## Install on your iPhone 14 Pro

1. On a Mac, install an Xcode version that supports your iPhone's installed iOS version.
2. Unzip this folder and open `Worklog.xcodeproj`.
3. Select the Worklog target → Signing & Capabilities. Choose your Apple development team. The command already generates a unique bundle identifier; keep that identifier for later upgrades. Automatic signing is enabled. If you opened the source without running the command, set your own unique identifier.
4. Connect and trust your iPhone. Enable Developer Mode on the phone if Xcode requests it.
5. Choose your iPhone as the run destination and press Run. Resolve any compiler/signing issues before real-world use.
6. Start a manual trip and allow location. In Schedule, choose your workdays, hours, time zone and vehicle, enable scheduled capture, then Save schedule. Choose Always and Precise Location in iPhone Settings → Apps → Worklog → Location.
7. Test as a passenger or let another person operate the app. Compare a short test trip with the vehicle odometer before relying on recorded kilometres.

Xcode can use a Personal Team for direct development installation. TestFlight distribution requires the appropriate Apple developer account and an uploaded, signed build. Nothing has been uploaded to Apple or installed on your phone.

Apple instructions: https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html
Signing: https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html

## Included

- GPS work trips with start and finish dates/times, vehicle, purpose, original coordinates and measured kilometres.
- Manual start/finish, plus an opt-in work schedule. Default: Monday–Friday, 07:00–17:00, Australia/Perth. It starts disabled.
- Overnight shifts associated with their starting weekday.
- Driving detection from two consecutive moving GPS fixes above about 9 km/h. Very short, slow trips or the beginning of a trip may be missed; test and review this heuristic.
- Trip separation after about three minutes stopped and automatic finish at shift end, processed when the app receives an execution opportunity.
- Financial year dashboard for 1 July–30 June in the selected time zone. GPS segments crossing 1 July are split proportionally by elapsed segment time. A corrected distance crossing a boundary is apportioned by trip duration and needs review.
- Tax receipt capture using Apple's multipage document scanner, saved as local dated PDFs with a matching per-transaction JSON file. Text is read on the iPhone (Apple Vision) and suggests supplier, items, date, total and GST for you to check and correct before saving. Import an existing photo or PDF the same way.
- Native share menu for invoice PDF, trip CSV and complete JSON backup. JSON backup includes invoice PDFs. Restore adds missing IDs without overwriting existing records.
- QNAP transfer through Qfile Pro / Files. Direct or automatic NAS sync is not configured.
- GPS accuracy filtering and flags for missing data. Missing route sections are never invented. Distance corrections preserve the original GPS measurement and a reason.

## Background recording limits

This project declares the location background mode and uses Core Location. Scheduled monitoring keeps GPS active while enabled, even outside the chosen hours, so location callbacks can detect work boundaries. It discards positions outside recorded trips. This can noticeably use battery. Disable scheduled monitoring when not needed.

Always authorization is required for automatic scheduled trips; precise location improves measurements. A manual trip can use While Using permission with background location enabled. iOS controls execution: force-quitting, rebooting, permission changes, battery restrictions, poor GPS or suspension can interrupt recording. There is no guaranteed wall-clock wake-up at shift start. Reopen after force-close or reboot and confirm status. Interrupted saved trips are flagged. Do not treat this prototype as a guaranteed unattended log.

Trips during selected hours are initially classified as work by the schedule. Review personal travel and passenger journeys. Automatic classification is a heuristic, not proof of business purpose. Records are not a certification of tax deductibility or a complete statutory vehicle logbook.

## Storage and QNAP

Records are in Files → On My iPhone → Worklog → Worklog. Invoice PDFs and the JSON database use file protection that allows access after the phone's first unlock, including while locked for background recording. Do not edit these internal files while the app is running. Keep exported backups elsewhere. Deleting the app deletes its local data.

To save to QNAP: export a backup or share an invoice → Save to Files. Open Qfile Pro, select the NAS and destination folder, then Upload → Other and select the saved file. Complete the upload and verify it in Qfile Pro. The app does not know whether Qfile Pro finished. No NAS address, login or password has been configured. A reachable home connection through your existing QNAP setup is required.

QNAP instructions: https://docs.qnap.com/application/qfile-pro/4.x/en-us/uploading-files-and-folders-ios-B6EF3FB6.html

## Validation

`Tests/WorklogTests.swift` contains XCTest checks for workday boundaries, overnight shifts, financial-year rollover, cross-year distance allocation and persistence encoding. Run Product → Test on a Mac. These Swift tests were authored but could not be executed here.

Before everyday use, test permission denial, manual trip recovery after restart, a locked-screen scheduled drive, a drive crossing the end of a shift, a GPS outage, a stationary stop followed by another drive, an overnight shift, a multipage invoice, restart persistence, backup/restore and QNAP upload.

The separately hosted browser test version uses separate on-device browser storage. Its GPS is foreground-only, and its schedule editor does not trigger background tracking. Browser and iOS backups currently have different formats and are not interchangeable.

## Australian accountant records

On the Trips page choose the financial year and tap Accountant. This exports the trip CSV, invoice register, explanatory notes and the invoice PDFs for that year. The original work distance, date/time, purpose, vehicle, odometer readings (if entered), private-trip exclusions, corrections and review flags are retained. Use Trip details to enter odometer readings and exclude private travel from work totals.

Invoice categories cover common work, business, vehicle, home office, training, professional, investment, rental-property, donation and tax-affairs expenses, plus a custom category. Supplier ABN, invoice number, date, AUD total, GST, work-use percentage, reimbursement, notes and proposed review status are editable. New invoices default to Needs accountant review. Categories are for organisation and do not establish deductibility, a GST credit, or whether an item is an immediate expense versus a depreciating asset. The accountant determines the treatment.

Records never expire automatically. Keep dated independent backups for the retention period your accountant requires. A GPS work-only log does not provide every record needed for the ATO logbook method: additional vehicle, total-use, odometer and representative-period evidence may be required.

ATO logbook guidance: https://www.ato.gov.au/individuals-and-families/income-deductions-offsets-and-records/deductions-you-can-claim/work-related-deductions/cars-transport-and-travel/motor-vehicle-and-car-expenses/expenses-for-a-car-you-own-or-lease/logbook-method
ATO record guidance: https://www.ato.gov.au/individuals-and-families/income-deductions-offsets-and-records/records-you-need-to-keep

## Trip-description quick selection

Starting a manual trip opens the description field with your last choice filled in. The Quick select menu contains recent descriptions and common presets. You can edit the text or enter a new description. Quick selections are remembered immediately; typed descriptions are remembered when starting a trip. Preferences persist in the local record file and are included in full native backups. Existing saved trips retain their own descriptions when opened for editing.

## Siri and Apple Shortcuts

The native project now includes App Intents for Start work trip and Set starting odometer. This is source integration only: it has not been compiled, installed, indexed by Siri or voice-tested in this workspace. It does not give the hosted browser/PWA Siri support.

After building and signing this revision in Xcode, install it on the iPhone, open Worklog once and allow precise location. In Storage → Siri commands use the Shortcuts link. Worklog should appear under Apps in Apple Shortcuts after the build metadata is processed. Enable Siri access if iOS requests it. The actions open Worklog, and iOS can require an unlock; locked-screen hands-free operation is not guaranteed.

Intended voice commands:

- “Hey Siri, start a supply pickup trip in Worklog.” Siri requests the starting odometer in kilometres, reads back the description and number, and asks for confirmation before recording.
- “Hey Siri, start a trip in Worklog.” Uses the last description; asks for a description if none has been saved, and asks for the starting odometer.
- “Hey Siri, start a custom trip in Worklog.” Requests a custom description and the starting odometer.
- “Hey Siri, set starting odometer in Worklog.” Updates the active trip after reading back the value for confirmation. It does not change a completed trip.

Built-in trip choices: Supply pickup, Site visit, Customer visit, Workshop visit, Training, Last description and Custom. Numeric odometer input is collected as a follow-up question or provided as an action parameter in Shortcuts. Recognition of an arbitrary single sentence containing both description and number is not claimed. You can create a personal shortcut with a shorter name, preset the description, and set the odometer action parameter to Ask Each Time. Never preset a stale odometer for reuse across trips.

A starting reading can also be entered in the normal Start work trip sheet. It is saved atomically with the new trip, displayed on the live trip card, retained in backups and included in the accountant CSV. GPS distance remains independently measured; entering the odometer does not invent or change GPS kilometres. Siri uses the same store and GPS recorder as the visible app to avoid two simultaneous recorders.

Validation before real use: confirm and cancel a start; dictate a large reading such as 128450; try a negative reading; try a duplicate start; deny location; remove GPS reception; change/finish the trip during odometer confirmation; restart the app and inspect the saved reading; check the accountant CSV. Confirm that Siri reports an error on failed saving and does not claim GPS distance before the first fix. These device tests remain outstanding.

Apple references:
- https://developer.apple.com/videos/play/wwdc2022/10032/
- https://developer.apple.com/documentation/appintents/app-shortcuts
- https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(result:confirmationactionname:showprompt:)


## Face ID and app lock

In **Storage → App security**, enable **Face ID / device passcode** and complete Apple's authentication prompt. App lock starts off; enabling or disabling it requires authentication. Once enabled, Worklog opens with an Unlock button, locks when the app enters the background, and provides a Lock Worklog now button. iOS chooses Face ID, Touch ID or the device passcode using LocalAuthentication. Worklog does not receive, store or upload face images or biometric templates.

The active GPS recorder and work schedule run independently of the screen lock, subject to normal iOS background-location restrictions. Save any in-progress form edits before switching apps: locking removes the protected screens and dismisses their sheets. A privacy window covers app content during inactive/background transitions, including invoice previews, for app-switcher snapshots. A locked app shows no trip, invoice or storage-error details.

Siri actions require the iPhone to be unlocked (Face ID or passcode); iOS asks for this before running them. They do not also need Worklog's app lock to be unlocked, so voice trip starts work while the app is locked. When Siri opens Worklog its screens stay locked until you unlock the app. App lock is an access gate for the app screens; it is not separate encryption for records. Copies accessible through iOS Files, exported documents and QNAP backups have their own protection. The device-specific lock setting lives in Application Support and is intentionally excluded from Worklog JSON backups.

Native compilation, biometric prompts, passcode fallback, snapshot coverage, Face ID interruptions and background/Siri interactions still require a signed build and real iPhone testing. XCTest cases are included for enable/disable authentication, persistence, failed attempts, corrupt preferences and late authentication after backgrounding. They have not been run in this non-Apple preparation workspace.

Apple reference: https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id
