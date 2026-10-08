# Start a work trip with Siri

Once this native iOS build is installed, open Worklog and allow precise location. Configure the vehicle under Schedule. If app lock is enabled, unlock Worklog before invoking Siri.

Say “Hey Siri, start a work trip in Worklog.”

Siri requests the purpose: say “Supply pickup” or a custom description such as “Collect hydraulic fittings from Bunbury.” Siri requests the current vehicle kilometres: say “128450”. This is the dashboard odometer, not the distance you expect to drive. Confirm Siri’s read-back to start the work trip. The system may vary the order of missing-parameter prompts.

The trip stores the spoken purpose, starting odometer, configured vehicle and start date/time, then records GPS distance. The purpose becomes the last-used description for manual entry. The purpose and starting odometer are included in accountant CSV exports and backups.

Preset commands such as “Start a supply pickup trip in Worklog” remain available and ask for the odometer. Use “Start a trip with my last description in Worklog” to explicitly reuse the previous purpose. “Set starting odometer in Worklog” corrects the active trip after confirmation.

A cancelled confirmation starts nothing. An existing active trip, denied location permission, app lock or failed local saving prevents a new trip. Siri access does not bypass Face ID. Give commands while parked.

This uses Apple App Intents in the native app; the HTML edition has no Siri integration. Source/package checks were completed in the Linux workspace. Xcode compilation, Siri phrase recognition, voice number entry, cancellation, app-lock interactions and GPS on a physical iPhone still need testing. Do not assume a single sentence with arbitrary purpose and odometer will always be understood; use the prompted conversation.
