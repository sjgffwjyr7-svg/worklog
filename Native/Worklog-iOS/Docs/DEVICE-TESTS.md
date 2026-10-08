# iPhone acceptance checks

Run these after the command's simulator tests pass. Use test records first. Operate the app while parked or have a passenger test it.

| Check | Expected result |
|---|---|
| Manual work trip | Record a short known route, date/time, purpose and vehicle. Compare GPS kilometres with the odometer; inspect flagged gaps. |
| Description memory | Select Supply pickup, close/reopen, and start another trip: the last description is filled. Custom text remains editable. |
| Odometer | Starting and finishing values survive a restart and appear in the accountant CSV. Negative/invalid values are rejected. |
| Siri start | Open the app and grant location first. Say “Start a supply pickup trip in Worklog”; dictate 128450, review and confirm. The saved active trip contains that value. |
| Siri cancellation / duplicate | Cancel confirmation and confirm no trip is created. Try to start while a trip is active and confirm it is refused. |
| Siri update | Set starting odometer for the current trip, confirm, then check the saved value. No completed trip should change. |
| Scheduled trip | Choose a test weekday/time, vehicle and purpose. Enable Always and Precise Location. Drive during the window with the screen locked; check start, stop and recorded distance. |
| Outside work hours | Scheduled travel is not saved outside the window. A manually started trip can still be recorded. |
| Stop / overnight | Test a stop longer than three minutes and an overnight shift; review whether the driving heuristic suits your work. |
| Permission / GPS loss | Deny location or interrupt GPS. The app should show the problem and flag incomplete distance instead of inventing kilometres. |
| Restart | Reopen after an interrupted active trip; the old trip is saved with a review flag. Schedule monitoring resumes if enabled and permission allows. Force-close/reboot can interrupt coverage. |
| Invoice | Scan a legible multipage invoice; enter details/category and save. Replace a scan and check that the displayed PDF changes. Reopen the saved document. |
| FY / accountant export | Select 1 July–30 June; check trip dates/times, vehicle, purpose, kilometres, odometer, exclusions and invoice originals. A category is not a deduction decision. |
| Backup / QNAP | Save a full JSON backup and copy through Files/Qfile Pro. Confirm the file exists on the NAS. On a separate test installation restore it and open an invoice PDF. |
| Restore twice | Restoring again must not duplicate IDs or overwrite existing record edits. On a fresh restore, review and re-enable the schedule. |

GPS work-only trips are not automatically a complete ATO logbook. Ask your accountant which additional records and retention periods apply. The app does not delete records automatically, but uninstalling it removes local app data. Keep independent dated backups. Browser Worklog and native iOS backups are separate formats; this package does not migrate browser data.

Record your iPhone iOS version, Xcode version, test date, result and any measured GPS discrepancy before everyday use.


## Face ID acceptance checks

- Enable app lock in Storage. Cancel the first authentication and confirm it stays off; then enable successfully.
- Lock now, test a successful Face ID unlock, a failed/cancelled scan and the iPhone passcode fallback. Also test denied Face ID permission and biometric lockout. Worklog must stay locked until Apple's authentication succeeds.
- Relaunch the app: enabled app lock remains on, but the session starts locked. No tax or trip details should appear before unlocking.
- Background and reopen the app during an authentication attempt. A cancelled or late result must not unlock the next session.
- Verify the app-switcher preview is blank/locked from the dashboard, invoice PDF, import screen and presented share sheet. Check real devices; do not rely only on Simulator.
- Lock the screen during a recorded drive. Check the trip continues to save GPS points with the usual iOS limitations; confirm no second recorder starts when unlocking.
- Try Siri while locked: it requests opening/unlocking Worklog. After unlocking, start/update a trip and verify it still confirms the odometer. Lock during confirmation: no change should be made.
- Disable app lock: cancellation must leave it enabled. Successful authentication must persist the disabled setting.
- Check saved invoice originals/exports separately: the app lock does not add a password to copies in Files or QNAP.
