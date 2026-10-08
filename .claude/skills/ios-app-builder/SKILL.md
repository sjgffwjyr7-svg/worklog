---
name: ios-app-builder
description: Dan's process for designing, building, updating and delivering native iPhone (iOS) apps from a Windows PC with no Mac. Use whenever Dan asks to design, create, change, fix, restyle or install an iOS/iPhone app, or shares an iOS project export — even if he calls Xcode "codex" or asks to "emulate" it on a PC. Covers the GitHub Actions cloud-Mac build, tests, simulator screenshots, the dark amber/mint design kit, and handing over a Sideloadly-ready IPA.
---

# iOS app builder (Windows, no Mac)

Dan designs iPhone apps on a Windows PC and installs them on his iPhone (iOS 26) with Sideloadly. He has no Mac. Every build runs on GitHub's macOS runners. He is happy for you to create, commit and push the project files automatically each time — no need to ask before writing files, committing or pushing to his app repositories.

Reference app: `sjgffwjyr7-svg/worklog` (Worklog — work kilometres and tax receipts). Copy patterns from it.

## The process — follow every time

1. **Understand the request.** If Dan shares an export or existing source, rebuild the files exactly (verify any SHA256 sums), read all source, and report what is implemented, what is broken and what is untested before changing anything. Ask only for information that blocks a concrete step.
2. **Native SwiftUI, iOS 17+.** Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY = minimal`. No third-party packages unless essential. Real Apple features (Siri App Intents, VisionKit scanner, Core Location, Face ID) — never a web imitation.
3. **Repository.** One private GitHub repo per app under `sjgffwjyr7-svg`. Attach it with `add_repo` (push access). If the repo does not exist yet, ask Dan to create an empty private repo with that name (you cannot create repos) and to allow the Claude GitHub App on it. If GitHub isn't linked, send him to `claude.ai/connect-github` (on iPhone: sign in to claude.ai in Safari first). Commit as `Dan <dan@farmwest.com.au>` with clear messages and push to `main`.
4. **New app scaffolding** (templates in `templates/`, proven end to end on 8 Oct 2026). Copy them, rename `MyApp` everywhere (folders, `project.yml`, `SCHEME` in `ios.yml`, `@testable import`), then build the real screens:
   - `project.yml` — XcodeGen spec; CI generates the `.xcodeproj`, so never hand-write `project.pbxproj` for a new app. Set name, bundle ID (`au.com.farmwest.<app>`), usage descriptions.
   - `ios.yml` → `.github/workflows/ios.yml`; set `APP_DIR` and `SCHEME`.
   - `MyApp/MyAppApp.swift` — starter app (dark mode, tabs, design-kit sample). `MyApp/Theme.swift` — the design kit (below). `MyApp/DemoMode.swift` + `screenshots.txt` — demo data and the screenshot list. `MyAppTests/MyAppTests.swift` — starter test.
   - An app icon in `Assets.xcassets/AppIcon.appiconset` (single 1024×1024 PNG).
   - An XCTest target covering the app's real logic (calculations, parsing, persistence, rules).
   Existing apps with a committed `.xcodeproj` (like Worklog): edit the project file only when adding files; prefer putting new types into existing files.
5. **Design kit — Dan's preferred look.** Dark mode only (`.preferredColorScheme(.dark)`), near-black background, charcoal cards, bright amber/orange gradient for primary actions, mint green for numbers and money, no blue. Use `DropdownField` (label above a filled field with a chevron menu) for every choice, `ThemedTextField` for inputs, `PrimaryButtonStyle` for buttons, `StatChip` for badges, `.themedForm()` on Form/List screens, large rounded numbers for key figures.
6. **Build in the cloud.** Push, then watch with `gh run watch <id> -R <owner/repo>` (run it in the background for long waits) and read failures with `gh run view <id> --log-failed`. Fix and push until both jobs are green. Report test counts.
7. **Check the screenshots yourself.** Download the `screenshots` artifact (`gh run download <id> -n screenshots`), look at every image, and fix layout problems before showing Dan.
8. **Deliver.** Download the IPA artifact and send it plus the screenshots with `SendUserFile`. Remind Dan to back up records in the app before reinstalling. Explain in plain language what changed and what still needs testing on the phone.

## Installing on the iPhone (tell Dan when relevant)

On the Windows PC: Apple iTunes + iCloud from apple.com (not the Microsoft Store), then Sideloadly (sideloadly.io). Plug in the iPhone, drag the IPA onto Sideloadly, enter the Apple ID, Start, enter the 2-factor code. On the iPhone: Settings → Privacy & Security → Developer Mode on (restart), then Settings → General → VPN & Device Management → trust the Apple ID. A free Apple ID install expires after 7 days (re-run Sideloadly; data is kept while the bundle ID stays the same). A paid Apple Developer account allows 1-year installs and TestFlight. To get files onto the PC: open the same Claude session at claude.ai on the PC, or download the run's Artifacts from GitHub Actions. Creating GitHub releases and deleting remote branches are not permitted from these sessions, so work on `main` and avoid temporary branches.

## Honesty rules

- A green CI run proves compilation and unit tests only. Never claim GPS, camera/OCR, Siri, Face ID, background behaviour or notifications work until Dan has tried them on the phone.
- Siri App Intents print "Could not archive SSU artifacts" / "Failed to refresh AppShortcut parameters" in CI; these are simulator noise, not failures — still ask Dan to test Siri on the device.
- Tax features: categories, GST and commute/break tags are suggestions for the accountant, never decisions about deductibility.

## Gotchas already hit (avoid repeating)

- A closure that creates a `@MainActor` object needs a `@MainActor` closure type.
- Swift can't destructure a tuple in `if let (a, b) = optional`; bind first, then `let (a, b) = value`.
- Test helpers defined on one `XCTestCase` class aren't visible in another class in the same file.
- In Form/List rows, several buttons in one row all fire on a tap — give each button its own row (`.buttonRow()`).
- `Label` inside List rows takes the row's icon layout and stretches; use `HStack { Image; Text }` for badges and add `.fixedSize()` so chips don't wrap.
- Create `build/` before `tee build/…` in CI.
- `CLLocationManagerDelegate` methods on a `@MainActor` class compile with warnings in Swift 5 mode; that's acceptable.
