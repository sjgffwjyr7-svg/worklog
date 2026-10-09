# Worklog security

Worklog keeps everything on the iPhone. It has no server, account, analytics or advertising, and sends no records anywhere unless you share an export or backup yourself.

## Protections

| Area | Protection |
|---|---|
| App access | Face ID / Touch ID with the iPhone passcode as fallback (Settings → App security). Prompts automatically on open; locks when Worklog goes to the background. |
| Siri | Every Worklog Siri action requires the iPhone to be unlocked. Siri only repeats details you just gave it. |
| App switcher | Worklog's screen is always covered in the app switcher, so records don't appear in snapshots. |
| Storage location | Records live in the app's private Application Support folder. They can't be browsed from the Files app or a computer. Older versions stored them in a Files-visible folder; they move automatically on first launch. |
| Receipts (PDFs and transaction files) | iOS **Complete** data protection: encrypted with a key derived from your passcode and unreadable whenever the iPhone is locked. |
| Trip database | iOS **Complete until first unlock** protection. Encrypted at rest, but readable after the first unlock since restart, because background GPS has to save trips while the phone is locked. |
| Backups | Encrypted with AES-256-GCM. The key comes from your backup password via PBKDF2-HMAC-SHA256 (310,000 rounds, random salt). The password is never stored; without it a backup cannot be opened. Old unencrypted backups can still be restored. |
| Exports | Accountant exports and backups are written to a protected temporary folder that is cleared each time Worklog starts. |
| Spreadsheets | CSV cells that start with `=`, `+`, `-` or `@` are escaped so a crafted description can't run as a formula in Excel. |

## What you control

- Use a 6-digit or longer iPhone passcode. iOS data protection is only as strong as the passcode.
- Turn on Worklog's Face ID lock.
- Keep iOS up to date.
- Turn on **Advanced Data Protection** for iCloud (Settings → your name → iCloud) so iPhone backups in iCloud are end-to-end encrypted. Alternatively, use encrypted computer backups.
- Keep backup passwords in a password manager, and keep backups on the QNAP in a folder only you can access.
- Once a file is shared (email, AirDrop, Qfile Pro), its protection depends on where it goes.

## Limits

- An unlocked iPhone in someone else's hands is protected by the Worklog lock, not by encryption.
- A Sideloadly build is signed with your Apple ID; App Store review doesn't apply. Only install builds from your own GitHub repository.
