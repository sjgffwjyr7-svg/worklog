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
        if !loadFailed { migrateVehicles() }
    }

    // MARK: Home and work

    @discardableResult func savePlace(_ place: Place?, home: Bool) -> Bool {
        let previous = data
        if home { data.home = place } else { data.workplace = place }
        if save() { return true }
        data = previous; return false
    }
    /// Flags trips that look like commuting (home ↔ work) or a break at home during work hours.
    /// Only a suggestion: the driver confirms, and nothing is excluded automatically.
    func placeAssessment(_ trip: Trip) -> PlaceAssessment? {
        guard trip.excluded != true, trip.placeReviewed != true, let first = trip.points.first, let last = trip.points.last else { return nil }
        let fromHome = data.home?.contains(first) == true, toHome = data.home?.contains(last) == true
        let fromWork = data.workplace?.contains(first) == true, toWork = data.workplace?.contains(last) == true
        let commute = "Normal travel between home and your usual workplace is usually private, not work travel. Check with your accountant."
        if fromHome && toWork { return PlaceAssessment(kind: .commute, short: "Commute?", message: "Home to work. " + commute) }
        guard toHome && !fromHome else { return nil }
        let end = trip.end ?? last.date
        var shiftCalendar = data.schedule
        shiftCalendar.timeZoneID = trip.timeZoneID
        if let shift = shiftCalendar.window(at: end), shift.end.timeIntervalSince(end) >= 30 * 60 {
            let left = Int(shift.end.timeIntervalSince(end) / 60)
            let remaining = left >= 60 ? "\(left / 60) h \(left % 60) min" : "\(left) min"
            return PlaceAssessment(kind: .homeBreak, short: "Break?", message: "Ended at home with \(remaining) of your work hours left. If this was a meal or personal break, mark the trip private.")
        }
        if fromWork { return PlaceAssessment(kind: .commute, short: "Commute?", message: "Work to home. " + commute) }
        return nil
    }

    // MARK: Vehicles

    /// A reading more than this far past a vehicle's last reading is treated as implausible for it.
    static let plausibleOdometerGapKm = 2000.0
    var vehicles: [Vehicle] { data.vehicles ?? [] }
    var currentVehicle: Vehicle? { vehicles.first { $0.id == data.currentVehicleID } ?? vehicles.first }
    func vehicle(_ id: UUID?) -> Vehicle? { id.flatMap { id in vehicles.first { $0.id == id } } }

    /// Older records stored the vehicle as free text. Turn those names into vehicles once.
    private func migrateVehicles() {
        guard data.vehicles == nil else { return }
        var names: [String] = []
        for name in [data.schedule.vehicle] + data.trips.map(\.vehicle) {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) { names.append(clean) }
        }
        let created = names.map { Vehicle(name: $0) }
        data.vehicles = created
        for index in data.trips.indices {
            let name = data.trips[index].vehicle.trimmingCharacters(in: .whitespacesAndNewlines)
            data.trips[index].vehicleID = created.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        }
        data.currentVehicleID = created.first { $0.name.caseInsensitiveCompare(data.schedule.vehicle.trimmingCharacters(in: .whitespaces)) == .orderedSame }?.id ?? created.first?.id
        if !created.isEmpty { save() }
    }
    @discardableResult func saveVehicle(_ vehicle: Vehicle, makeCurrent: Bool = false) -> Bool {
        let previous = data
        var list = vehicles
        if let index = list.firstIndex(where: { $0.id == vehicle.id }) { list[index] = vehicle } else { list.append(vehicle) }
        data.vehicles = list
        // Keep each trip's saved label in step with a renamed vehicle.
        for index in data.trips.indices where data.trips[index].vehicleID == vehicle.id { data.trips[index].vehicle = vehicle.displayName }
        if data.active?.vehicleID == vehicle.id { data.active?.vehicle = vehicle.displayName }
        if makeCurrent || data.currentVehicleID == nil { data.currentVehicleID = vehicle.id }
        if save() { return true }
        data = previous; return false
    }
    func deleteVehicle(_ id: UUID) throws {
        guard !data.trips.contains(where: { $0.vehicleID == id }), data.active?.vehicleID != id else { throw StoreError.vehicleInUse }
        let previous = data
        data.vehicles = vehicles.filter { $0.id != id }
        if data.currentVehicleID == id { data.currentVehicleID = data.vehicles?.first?.id }
        if !save() { data = previous; throw StoreError.unavailable }
    }
    /// Remembers the vehicle being driven; it stays selected after the app is closed.
    /// A trip already recording moves to the new vehicle, so a forgotten switch can be fixed mid-trip.
    @discardableResult func selectVehicle(_ id: UUID) -> Bool {
        guard let chosen = vehicle(id) else { return false }
        let previous = data
        data.currentVehicleID = id
        if data.active != nil { data.active?.vehicleID = id; data.active?.vehicle = chosen.displayName }
        if save() { return true }
        data = previous; return false
    }
    func lastOdometer(for id: UUID) -> Double? {
        let trips = data.trips + (data.active.map { [$0] } ?? [])
        let readings = trips.filter { $0.vehicleID == id }.flatMap { [$0.odometerStart, $0.odometerEnd] }.compactMap { $0 }
        return (readings + [vehicle(id)?.startingOdometer].compactMap { $0 }).max()
    }
    /// Returns nil when the reading fits the selected vehicle. Otherwise explains the problem and,
    /// when another vehicle's last reading fits, suggests that vehicle (the driver may have forgotten to switch).
    func odometerCheck(reading: Double, vehicleID: UUID?) -> OdometerCheck? {
        func fits(_ last: Double?) -> Bool {
            guard let last else { return false }
            return reading >= last - 0.5 && reading - last <= Self.plausibleOdometerGapKm
        }
        func km(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + " km" }
        let selected = vehicle(vehicleID), selectedLast = vehicleID.flatMap { lastOdometer(for: $0) }
        if fits(selectedLast) { return nil }
        let candidates = vehicles.filter { $0.id != vehicleID }.compactMap { v in lastOdometer(for: v.id).map { (v, $0) } }.filter { fits($0.1) }
        if let best = candidates.min(by: { reading - $0.1 < reading - $1.1 }) {
            let (other, last) = best
            var message = "\(km(reading)) is close to the \(other.displayName)'s last reading of \(km(last))."
            if let selected, let selectedLast { message += " The \(selected.displayName) was last at \(km(selectedLast))." }
            return OdometerCheck(selected: selected, selectedLast: selectedLast, suggested: other, suggestedLast: last, message: message)
        }
        guard let selected, let selectedLast else { return nil }
        if reading < selectedLast - 0.5 {
            return OdometerCheck(selected: selected, selectedLast: selectedLast, message: "\(km(reading)) is lower than the \(selected.displayName)'s last reading of \(km(selectedLast)).")
        }
        return OdometerCheck(selected: selected, selectedLast: selectedLast, message: "\(km(reading)) is \(km(reading - selectedLast)) more than the \(selected.displayName)'s last reading of \(km(selectedLast)). Check the vehicle and reading.")
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
        for vehicle in backup.data.vehicles ?? [] where !(next.vehicles ?? []).contains(where: { $0.id == vehicle.id }) {
            next.vehicles = (next.vehicles ?? []) + [vehicle]
        }
        if next.trips.isEmpty && next.invoices.isEmpty {
            next.currentVehicleID = backup.data.currentVehicleID ?? next.currentVehicleID
            next.home = backup.data.home; next.workplace = backup.data.workplace
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
        let perVehicle = vehicles.map { v in "\(v.displayName): \(String(format: "%.1f", data.trips.filter { $0.vehicleID == v.id }.reduce(0) { $0 + $1.km(in: interval) })) km" }.joined(separator: "; ")
        let summary = "Worklog accountant export: 1 July \(year) to 30 June \(year+1). Work kilometres: \(data.trips.reduce(0) { $0 + $1.km(in: interval) }).\(perVehicle.isEmpty ? "" : " By vehicle: \(perVehicle).") Invoice categories, amounts and business-use proportions are user-entered and require review. Original PDFs are included. GPS work trips alone are not a complete ATO logbook. Retain other required odometer, total-use and expense evidence. No automatic deletion applies. Keep independent backups for the required retention period."
        let note = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-accountant-notes-FY-\(year).txt")
        try Data(summary.utf8).write(to: note, options: .atomic)
        var transactionFiles: [URL] = []
        for invoice in receipts {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(invoice.id.uuidString).json")
            try receiptBytes(invoice).write(to: url, options: .atomic); transactionFiles.append(url)
        }
        let vehicleLogs = vehicles.count > 1 ? try vehicles.filter { v in data.trips.contains { $0.vehicleID == v.id } }.map { try csvExport(year: year, vehicle: $0) } : []
        return [try csvExport(year: year), register, note] + vehicleLogs + receipts.map { pdfURL($0) } + transactionFiles
    }
    /// Trip log for the financial year; pass a vehicle for that vehicle's own log.
    func csvExport(year: Int, vehicle: Vehicle? = nil) throws -> URL {
        let interval = FinancialYear.interval(year, timeZone: data.schedule.timeZoneID)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        func cell(_ value: String) -> String {
            let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["Trip ID", "Purpose", "Vehicle", "Started UTC", "Finished UTC", "Time zone", "Work km in selected FY", "Full trip km", "GPS km", "Automatic", "Review", "Correction reason", "Odometer start km", "Odometer finish km", "Classification", "Home/work check"]]
        for t in data.trips where (t.end ?? t.start) > interval.start && t.start < interval.end && (vehicle == nil || t.vehicleID == vehicle?.id) {
            rows.append([t.id.uuidString, t.purpose, t.vehicle, formatter.string(from: t.start), t.end.map { formatter.string(from: $0) } ?? "", t.timeZoneID, String(format: "%.3f", t.km(in: interval)), String(format: "%.3f", t.km), String(format: "%.3f", t.metres / 1000), t.automatic ? "Yes" : "No", t.reviewReasons.joined(separator: "; "), t.correctionReason, t.odometerStart.map { String($0) } ?? "", t.odometerEnd.map { String($0) } ?? "", t.excluded == true ? "Personal / excluded" : "Work", placeAssessment(t).map { "\($0.short) \($0.message)" } ?? (t.placeReviewed == true ? "Confirmed work by driver" : "")])
        }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let suffix = vehicle.map { "-" + $0.displayName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-") } ?? ""
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Worklog-FY-\(year)-\(year+1)\(suffix).csv")
        try Data(csv.utf8).write(to: url, options: .atomic); return url
    }
}
enum StoreError: LocalizedError {
    case invalidBackup, unavailable, activeTrip, tooLarge, vehicleInUse
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This is not a valid Worklog iOS backup."
        case .unavailable: return "Local saving is unavailable. Check the storage error before continuing."
        case .activeTrip: return "Finish the current trip before backing up or restoring."
        case .tooLarge: return "This backup is too large to restore in memory."
        case .vehicleInUse: return "This vehicle has saved trips, so it can't be deleted. Rename it instead."
        }
    }
}
