import Foundation
import Combine

@MainActor final class WorkStore: ObservableObject {
    @Published var data = WorkData()
    @Published var error: String?
    private(set) var loadFailed = false
    let root: URL
    var file: URL { root.appendingPathComponent("worklog.json") }
    init(root directory: URL? = nil) {
        root = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Worklog", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(WorkData.self, from: Data(contentsOf: file))
                guard data.schemaVersion == 1 else { throw StoreError.invalidBackup }
            }
        } catch { loadFailed = true; self.error = "Could not open your saved records. Nothing has been overwritten. \(error.localizedDescription)" }
    }
    @discardableResult func save() -> Bool {
        guard !loadFailed else { error = "Records could not be loaded. Restart the app or recover the original files using Files."; return false }
        do {
            let bytes = try JSONEncoder().encode(data)
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { self.error = "Records have not been saved. Keep the app open and free device storage. \(error.localizedDescription)"; return false }
    }
    var lastTripDescription: String {
        data.lastTripDescription ?? data.trips.filter { $0.excluded != true }.max(by: { $0.start < $1.start })?.purpose ?? ""
    }
    var tripDescriptionChoices: [String] {
        let defaults = ["Site visit", "Customer visit", "Supply pickup", "Workshop visit", "Training"]
        let history = data.trips.filter { $0.excluded != true }.sorted { $0.start > $1.start }.map { $0.purpose }
        let candidates = [lastTripDescription] + (data.recentTripDescriptions ?? []) + history + defaults
        var seen = Set<String>()
        return Array(candidates.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(25))
    }
    @discardableResult func rememberTripDescription(_ value: String) -> Bool {
        let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !clean.isEmpty else { return false }
        let previousLast = data.lastTripDescription, previousRecent = data.recentTripDescriptions
        data.lastTripDescription = clean
        var seen = Set<String>()
        data.recentTripDescriptions = Array(([clean] + (previousRecent ?? [])).filter { seen.insert($0.lowercased()).inserted }.prefix(20))
        if save() { return true }
        data.lastTripDescription = previousLast; data.recentTripDescriptions = previousRecent; return false
    }
    func pdfURL(_ invoice: Invoice) -> URL { root.appendingPathComponent(invoice.pdfFilename) }
    func receiptURL(_ invoice: Invoice) -> URL { pdfURL(invoice).deletingPathExtension().appendingPathExtension("json") }
    func receiptBytes(_ invoice: Invoice) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(invoice)
    }
    func saveInvoice(_ invoice: Invoice, pdf: Data) throws {
        guard !loadFailed else { throw StoreError.unavailable }
        let url = pdfURL(invoice)
        try pdf.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do { try receiptBytes(invoice).write(to: receiptURL(invoice), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        let previous = data.invoices
        let replaced = data.invoices.first(where: { $0.id == invoice.id })
        if let index = data.invoices.firstIndex(where: { $0.id == invoice.id }) { data.invoices[index] = invoice }
        else { data.invoices.insert(invoice, at: 0) }
        if !save() {
            data.invoices = previous
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: receiptURL(invoice))
            throw StoreError.unavailable
        }
        // An edit writes a new dated file; remove the superseded copy so Files and exports hold one per receipt.
        if let replaced, replaced.pdfFilename != invoice.pdfFilename {
            try? FileManager.default.removeItem(at: pdfURL(replaced))
            try? FileManager.default.removeItem(at: receiptURL(replaced))
        }
    }
    func exportBackup() throws -> URL {
        guard data.active == nil else { throw StoreError.activeTrip }
        var documents: [String: Data] = [:]
        for invoice in data.invoices { documents[invoice.pdfFilename] = try Data(contentsOf: pdfURL(invoice)) }
        let backup = Backup(data: data, documents: documents)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-backup-\(UUID().uuidString).json")
        try JSONEncoder().encode(backup).write(to: url, options: .atomic)
        return url
    }
    func restoreBackup(_ url: URL) throws {
        guard !loadFailed else { throw StoreError.unavailable }
        guard data.active == nil else { throw StoreError.activeTrip }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bytes = try Data(contentsOf: url)
        guard bytes.count < 250 * 1024 * 1024 else { throw StoreError.tooLarge }
        let backup = try JSONDecoder().decode(Backup.self, from: bytes)
        guard backup.format == "worklog-ios-backup", backup.version == 1, backup.data.schemaVersion == 1, backup.data.active == nil else { throw StoreError.invalidBackup }
        let restoredSchedule = backup.data.schedule
        guard (0..<1440).contains(restoredSchedule.startMinute), (0..<1440).contains(restoredSchedule.endMinute),
              restoredSchedule.weekdays.isSubset(of: Set(1...7)), TimeZone(identifier: restoredSchedule.timeZoneID) != nil else { throw StoreError.invalidBackup }
        var next = data
        // On a fresh installation restore preferences, but leave automatic GPS disabled
        // until the owner reviews the schedule and permissions on this device.
        if next.trips.isEmpty && next.invoices.isEmpty {
            next.schedule = backup.data.schedule
            next.schedule.enabled = false
            next.lastTripDescription = backup.data.lastTripDescription
            next.recentTripDescriptions = backup.data.recentTripDescriptions
        }
        for trip in backup.data.trips where !next.trips.contains(where: { $0.id == trip.id }) {
            guard let end = trip.end, end >= trip.start, trip.km.isFinite, trip.km >= 0,
                  trip.points.allSatisfy({ $0.segmentMetres.isFinite && $0.segmentMetres >= 0 && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else { throw StoreError.invalidBackup }
            next.trips.append(trip)
        }
        var pending: [(URL, Data)] = []
        for var invoice in backup.data.invoices where !next.invoices.contains(where: { $0.id == invoice.id }) {
            guard let pdf = backup.documents[invoice.pdfFilename], pdf.starts(with: Data("%PDF".utf8)) else { throw StoreError.invalidBackup }
            invoice.pdfFilename = "invoice-\(invoice.id.uuidString)-\(UUID().uuidString).pdf"
            pending.append((pdfURL(invoice), pdf)); pending.append((receiptURL(invoice), try receiptBytes(invoice))); next.invoices.append(invoice)
        }
        for (destination, content) in pending { try content.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        let previous = data; data = next
        if !save() { data = previous; throw StoreError.unavailable }
    }
    func accountantExport(year: Int) throws -> [URL] {
        let interval = FinancialYear.interval(year, timeZone: data.schedule.timeZoneID)
        let receipts = data.invoices.filter { $0.date >= interval.start && $0.date < interval.end }
        func cell(_ value: String) -> String {
            let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        var rows = [["Invoice ID", "Supplier", "ABN", "Invoice number", "Invoice date UTC", "Total AUD", "GST AUD", "Category", "Custom category", "Work use percent (unverified)", "Reimbursed AUD", "Accountant review status", "Notes", "Original PDF", "Captured UTC", "Items purchased", "Receipt checked"]]
        for i in receipts { rows.append([i.id.uuidString, i.supplier, i.abn ?? "", i.number, formatter.string(from: i.date), i.total, i.gst, i.category ?? "Other", i.customCategory ?? "", i.workPercent ?? "", i.reimbursed ?? "", i.taxStatus ?? "Needs accountant review", i.notes, i.pdfFilename, formatter.string(from: i.captured), i.items ?? "", i.receiptReviewed == true ? "Yes" : "No"]) }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let register = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-invoices-FY-\(year).csv")
        try Data(csv.utf8).write(to: register, options: .atomic)
        let summary = "Worklog accountant export: 1 July \(year) to 30 June \(year+1). Work kilometres: \(data.trips.reduce(0) { $0 + $1.km(in: interval) }). Invoice categories, amounts and business-use proportions are user-entered and require review. Original PDFs are included. GPS work trips alone are not a complete ATO logbook. Retain other required odometer, total-use and expense evidence. No automatic deletion applies. Keep independent backups for the required retention period."
        let note = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-accountant-notes-FY-\(year).txt")
        try Data(summary.utf8).write(to: note, options: .atomic)
        var transactionFiles: [URL] = []
        for invoice in receipts {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(invoice.id.uuidString).json")
            try receiptBytes(invoice).write(to: url, options: .atomic); transactionFiles.append(url)
        }
        return [try csvExport(year: year), register, note] + receipts.map { pdfURL($0) } + transactionFiles
    }
    func csvExport(year: Int) throws -> URL {
        let interval = FinancialYear.interval(year, timeZone: data.schedule.timeZoneID)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        func cell(_ value: String) -> String {
            let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["Trip ID", "Purpose", "Vehicle", "Started UTC", "Finished UTC", "Time zone", "Work km in selected FY", "Full trip km", "GPS km", "Automatic", "Review", "Correction reason", "Odometer start km", "Odometer finish km", "Classification"]]
        for t in data.trips where (t.end ?? t.start) > interval.start && t.start < interval.end {
            rows.append([t.id.uuidString, t.purpose, t.vehicle, formatter.string(from: t.start), t.end.map { formatter.string(from: $0) } ?? "", t.timeZoneID, String(format: "%.3f", t.km(in: interval)), String(format: "%.3f", t.km), String(format: "%.3f", t.metres / 1000), t.automatic ? "Yes" : "No", t.reviewReasons.joined(separator: "; "), t.correctionReason, t.odometerStart.map { String($0) } ?? "", t.odometerEnd.map { String($0) } ?? "", t.excluded == true ? "Personal / excluded" : "Work"])
        }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-FY-\(year)-\(year+1).csv")
        try Data(csv.utf8).write(to: url, options: .atomic); return url
    }
}
enum StoreError: LocalizedError {
    case invalidBackup, unavailable, activeTrip, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This is not a valid Worklog iOS backup."
        case .unavailable: return "Local saving is unavailable. Check the storage error before continuing."
        case .activeTrip: return "Finish the current trip before backing up or restoring."
        case .tooLarge: return "This backup is too large to restore in memory."
        }
    }
}
