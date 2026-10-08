# Tax receipts

Tap Invoices → Tax receipt. On supported iPhones this opens Apple’s document camera for live edge detection and automatic/manual capture, cropping and multi-page scanning. After capture, Apple Vision reads the pages on-device; no cloud OCR is used.

The form suggests supplier, dated transaction time when recognised, purchased item lines, total and GST. Review and correct all fields against the scan before confirming Save. Recognition uses layout and text heuristics, not a general invoice-understanding model: multi-column receipts, discounts, split lines, faint print and unusual date formats may need manual corrections. Unread GST remains blank, never an assumed fraction of the total. Date-only receipts need a manual time check. Item text retains quantities where printed in the description; amounts are line totals, not inferred unit prices.

Each save keeps a dated PDF and matching JSON transaction record with a unique identifier. The main ledger keeps the transaction date, capture timestamp, items, total and GST. Financial-year totals use receipt dates and include all spending, including private/reimbursed entries. Accountant exports include receipt JSON files, PDFs and item text in the CSV. Full backups preserve the records and PDFs; restore recreates transaction JSON files. No new record format migration is required for older backups.

The separate HTML edition has camera/photo capture, manual item entry, the dated ledger, spending/GST totals and per-transaction ZIP downloads. It does not provide Apple document scanning or OCR.

Validation here: HTML logic and export ZIP checked; native project/package structure checked. Native Swift compilation, OCR accuracy, camera permission/cancellation, several-page scanning, edit/replacement, low storage, locked app, backup restoration and physical iPhone tests remain required. XCTest receipt parser and persistence tests are included for Xcode.
