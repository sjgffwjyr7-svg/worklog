import Foundation
import Combine
import CryptoKit
import CommonCrypto
import Security

@MainActor final class WorkStore: ObservableObject {
    @Published var data = WorkData()
    @Published var error: String?
    private(set) var loadFailed = false
    let root: URL
    /// All records, as LZFSE-compressed JSON.
    var file: URL { root.appendingPathComponent("worklog.lzfse") }
    /// Records saved by versions before compression; converted on first launch.
    var legacyFile: URL { root.appendingPathComponent("worklog.json") }
    /// The trip being recorded, saved on every GPS update (small, so it's quick and light on battery).
    var activeFile: URL { root.appendingPathComponent("active-trip.json") }
    init(root directory: URL? = nil) {
        root = directory ?? Self.privateRoot()
        if directory == nil { Self.clearExports() }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var convertLegacy = false
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(WorkData.self, from: Self.decompress(Data(contentsOf: file)))
            } else if FileManager.default.fileExists(atPath: legacyFile.path) {
                data = try JSONDecoder().decode(WorkData.self, from: Data(contentsOf: legacyFile))
                convertLegacy = true
            }
            guard data.schemaVersion == 1 else { throw StoreError.invalidBackup }
            loadActiveTrip()
            // Convert once to the compressed format; the old file is removed only after the new one is saved.
            if convertLegacy, save() { try? FileManager.default.removeItem(at: legacyFile) }
        } catch { loadFailed = true; self.error = "Could not open your saved records. Nothing has been overwritten. \(error.localizedDescription)" }
        if !loadFailed { migrateVehicles(); protectReceiptFiles() }
    }

    // MARK: Security

    /// Records live in Application Support, which the Files app and computer file sharing can't browse,
    /// so they can only be reached through Worklog (and its Face ID lock). Older versions used Documents.
    static func privateRoot() -> URL {
        let fm = FileManager.default
        let legacy = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Worklog", isDirectory: true)
        let secure = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Worklog", isDirectory: true)
        return moveLegacyStorage(from: legacy, to: secure)
    }
    /// Moves the old Files-visible folder into private storage once. If the move can't happen yet
    /// (for example the phone is locked), keeps using the old folder so no records are split or lost.
    static func moveLegacyStorage(from legacy: URL, to secure: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: secure.path) || !fm.fileExists(atPath: legacy.path) { return secure }
        do {
            try fm.createDirectory(at: secure.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: secure)
            return secure
        } catch { return legacy }
    }
    /// Receipts are only opened while the phone is unlocked, so they get iOS's strongest protection:
    /// encrypted and unreadable whenever the iPhone is locked. The trip database stays readable after
    /// first unlock because background GPS must save trips while the phone is locked.
    static let receiptProtection: Data.WritingOptions = .completeFileProtection
    private func protectReceiptFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where !["worklog.json", "active-trip.json"].contains(file.lastPathComponent) && ["pdf", "json"].contains(file.pathExtension.lowercased()) {
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        }
    }
    /// Exports and backups are written here and cleared every time Worklog starts.
    static var exportFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WorklogExports", isDirectory: true) }
    static func clearExports() { try? FileManager.default.removeItem(at: exportFolder) }
    private func exportURL(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: Self.exportFolder, withIntermediateDirectories: true)
        return Self.exportFolder.appendingPathComponent(name)
    }

    // MARK: ATO logbook

    /// The ATO logbook must cover at least 12 continuous weeks.
    static let logbookMinimumWeeks = 12.0
    /// Australian rule for when a supplier's tax invoice (with ABN) is needed.
    static let taxInvoiceThreshold = Decimal(string: "82.50")!
    func setYearOdometer(vehicleID: UUID, year: Int, _ reading: YearOdometer) -> Bool {
        guard var vehicle = vehicle(vehicleID) else { return false }
        var readings = vehicle.yearOdometers ?? [:]
        readings[String(year)] = reading
        vehicle.yearOdometers = readings
        return saveVehicle(vehicle)
    }
    func logbookSummary(_ vehicle: Vehicle, year: Int) -> LogbookSummary {
        let tz = data.schedule.timeZoneID
        let fy = FinancialYear.interval(year, timeZone: tz)
        let trips = data.trips.filter { $0.vehicleID == vehicle.id }
        var issues: [String] = []
        if vehicle.registration.isEmpty { issues.append("\(vehicle.name): add the registration number.") }
        if (vehicle.make ?? "").isEmpty || (vehicle.model ?? "").isEmpty { issues.append("\(vehicle.name): add the make and model.") }
        if (vehicle.engineCapacity ?? "").isEmpty { issues.append("\(vehicle.name): add the engine capacity.") }
        var weeks: Double?, logbookTotal: Double?, logbookBusiness = 0.0, percent: Double?
        if let start = vehicle.logbookStart, let end = vehicle.logbookEnd, end > start {
            weeks = end.timeIntervalSince(start) / (7 * 86400)
            logbookBusiness = trips.filter { $0.excluded != true && $0.start >= start && $0.start < end.addingTimeInterval(86400) }.reduce(0) { $0 + $1.km }
            if let a = vehicle.logbookStartOdometer, let b = vehicle.logbookEndOdometer, b > a {
                logbookTotal = b - a
                percent = min(100, logbookBusiness / (b - a) * 100)
            } else { issues.append("\(vehicle.name): enter the odometer at the start and end of the logbook period.") }
            if (weeks ?? 0) < Self.logbookMinimumWeeks - 0.01 { issues.append("\(vehicle.name): the logbook period is under 12 continuous weeks.") }
        } else {
            issues.append("\(vehicle.name): set a logbook period of at least 12 continuous weeks (needed in the first year you use the logbook method; valid for 5 years).")
        }
        let reading = vehicle.yearOdometers?[String(year)]
        if reading?.start == nil { issues.append("\(vehicle.name): enter the odometer on 1 July \(year).") }
        if reading?.end == nil && Date() >= fy.end { issues.append("\(vehicle.name): enter the odometer on 30 June \(year + 1).") }
        let yearTotal = reading.flatMap { r in r.start.flatMap { s in r.end.map { $0 - s } } }
        let yearTrips = trips.filter { fy.contains($0.start) }
        let missingOdometer = yearTrips.filter { $0.excluded != true && ($0.odometerStart == nil || $0.odometerEnd == nil) }.count
        if missingOdometer > 0 { issues.append("\(vehicle.name): \(missingOdometer) work trip\(missingOdometer == 1 ? "" : "s") missing a start or finish odometer reading.") }
        return LogbookSummary(vehicle: vehicle, logbookWeeks: weeks, logbookTotalKm: logbookTotal, logbookBusinessKm: logbookBusiness, businessPercent: percent,
                              yearStartOdometer: reading?.start, yearEndOdometer: reading?.end, yearTotalKm: yearTotal,
                              yearWorkKm: yearTrips.reduce(0) { $0 + $1.km(in: fy) }, issues: issues)
    }
    /// Everything the ATO asks for that is still missing for this financial year.
    func atoChecklist(year: Int) -> [String] {
        let tz = data.schedule.timeZoneID
        let fy = FinancialYear.interval(year, timeZone: tz)
        var issues: [String] = []
        let used = vehicles.filter { v in data.trips.contains { $0.vehicleID == v.id && fy.contains($0.start) } }
        if used.isEmpty && data.trips.contains(where: { fy.contains($0.start) }) { issues.append("Add your vehicle in Settings → Vehicles and assign it to your trips.") }
        for v in used { issues += logbookSummary(v, year: year).issues }
        let periods = used.compactMap { v in v.logbookStart.flatMap { s in v.logbookEnd.map { DateInterval(start: s, end: max(s, $0)) } } }
        if periods.count > 1, Set(periods.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }).count > 1 {
            issues.append("With 2 or more cars, the ATO expects each car's logbook to cover the same period.")
        }
        let noABN = data.invoices.filter { fy.contains($0.date) && (Decimal(string: $0.total, locale: Locale(identifier: "en_US_POSIX")) ?? 0) >= Self.taxInvoiceThreshold && ($0.abn ?? "").filter(\.isNumber).count != 11 }
        if !noABN.isEmpty { issues.append("\(noABN.count) receipt\(noABN.count == 1 ? "" : "s") of $82.50 or more without the supplier's 11-digit ABN. A valid tax invoice shows it.") }
        return issues
    }

    // MARK: Continuing a trip

    /// A finished trip can be continued for this long, e.g. after a stop to pick up parts.
    static let continueWindow: TimeInterval = 12 * 3600
    /// The most recent finished trip, if it ended recently enough to continue and nothing is recording.
    func continuableTrip(now: Date = Date()) -> Trip? {
        guard data.active == nil,
              let trip = data.trips.max(by: { ($0.end ?? $0.start) < ($1.end ?? $1.start) }),
              let end = trip.end, now >= end, now.timeIntervalSince(end) <= Self.continueWindow else { return nil }
        return trip
    }
    /// Reopens a finished trip as the active trip. The stop is kept as a pause; no distance is added for it.
    @discardableResult func reopenTrip(_ id: UUID, at now: Date = Date()) -> Bool {
        guard data.active == nil, let index = data.trips.firstIndex(where: { $0.id == id }), let end = data.trips[index].end else { return false }
        let previous = data
        var trip = data.trips.remove(at: index)
        trip.pauses = (trip.pauses ?? []) + [DateInterval(start: end, end: max(end, now))]
        trip.end = nil
        trip.odometerEnd = nil       // The finishing reading is entered again at the real finish.
        trip.automatic = false       // Continued by the driver, so the schedule doesn't auto-finish it.
        trip.scheduleEnd = nil
        data.active = trip
        if save() { return true }
        data = previous; return false
    }

    // MARK: Deleting records

    /// Permanently removes a saved trip. The trip being recorded is not in this list and can't be deleted.
    func deleteTrip(_ id: UUID) throws {
        guard !loadFailed else { throw StoreError.unavailable }
        let previous = data.trips
        data.trips.removeAll { $0.id == id }
        guard data.trips.count < previous.count else { return }
        if !save() { data.trips = previous; throw StoreError.unavailable }
    }
    /// Permanently removes a receipt, its scanned PDF and its transaction file.
    func deleteInvoice(_ id: UUID) throws {
        guard !loadFailed else { throw StoreError.unavailable }
        guard let invoice = data.invoices.first(where: { $0.id == id }) else { return }
        let previous = data.invoices
        data.invoices.removeAll { $0.id == id }
        if !save() { data.invoices = previous; throw StoreError.unavailable }
        try? FileManager.default.removeItem(at: pdfURL(invoice))
        try? FileManager.default.removeItem(at: receiptURL(invoice))
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
            let bytes = try Self.compress(JSONEncoder().encode(data))
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // The full file now holds the latest state, so the separate active-trip file isn't needed.
            if data.active == nil { try? FileManager.default.removeItem(at: activeFile) } else { saveActive() }
            return true
        } catch { self.error = "Records have not been saved. Keep the app open and free device storage. \(error.localizedDescription)"; return false }
    }
    /// Saves only the recording trip. Used on every GPS update instead of rewriting all records.
    @discardableResult func saveActive() -> Bool {
        guard !loadFailed, let active = data.active else { return false }
        do {
            try JSONEncoder().encode(active).write(to: activeFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { self.error = "The recording trip was not saved. Free device storage. \(error.localizedDescription)"; return false }
    }
    /// The active-trip file can be newer than the main file (it's saved more often). Use it when it is.
    private func loadActiveTrip() {
        guard let bytes = try? Data(contentsOf: activeFile), let trip = try? JSONDecoder().decode(Trip.self, from: bytes) else { return }
        if data.trips.contains(where: { $0.id == trip.id }) { try? FileManager.default.removeItem(at: activeFile); return }
        if data.active == nil || data.active?.id == trip.id && trip.points.count >= (data.active?.points.count ?? 0) { data.active = trip }
    }
    nonisolated static func compress(_ bytes: Data) throws -> Data { try (bytes as NSData).compressed(using: .lzfse) as Data }
    nonisolated static func decompress(_ bytes: Data) throws -> Data { try (bytes as NSData).decompressed(using: .lzfse) as Data }
    /// Space used by records and receipts on this iPhone.
    func storageUsed() -> (records: Int64, receipts: Int64) {
        let fm = FileManager.default
        var records: Int64 = 0, receipts: Int64 = 0
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if [file, legacyFile, activeFile].map(\.lastPathComponent).contains(url.lastPathComponent) { records += size } else { receipts += size }
        }
        return (records, receipts)
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
        try pdf.write(to: url, options: [.atomic, Self.receiptProtection])
        do { try receiptBytes(invoice).write(to: receiptURL(invoice), options: [.atomic, Self.receiptProtection]) }
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
    /// Full backup including receipt PDFs. With a password the file is encrypted (AES-256-GCM, key from
    /// PBKDF2-SHA256); without one it is plain JSON (kept for older backups and tests).
    func exportBackup(password: String? = nil) throws -> URL {
        guard data.active == nil else { throw StoreError.activeTrip }
        var documents: [String: Data] = [:]
        for invoice in data.invoices { documents[invoice.pdfFilename] = try Data(contentsOf: pdfURL(invoice)) }
        let backup = Backup(data: data, documents: documents)
        var bytes = try JSONEncoder().encode(backup)
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if let password {
            guard password.count >= 8 else { throw StoreError.weakPassword }
            bytes = try BackupCrypto.seal(Self.compress(bytes), password: password, compression: "lzfse")
        }
        let url = try exportURL("Worklog-backup-\(stamp)\(password == nil ? "" : "-encrypted").json")
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    func restoreBackup(_ url: URL, password: String? = nil) throws {
        guard !loadFailed else { throw StoreError.unavailable }
        guard data.active == nil else { throw StoreError.activeTrip }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        var bytes = try Data(contentsOf: url)
        guard bytes.count < 250 * 1024 * 1024 else { throw StoreError.tooLarge }
        if BackupCrypto.isEncrypted(bytes) {
            guard let password, !password.isEmpty else { throw StoreError.passwordNeeded }
            bytes = try BackupCrypto.open(bytes, password: password)
        }
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
        for (destination, content) in pending { try content.write(to: destination, options: [.atomic, Self.receiptProtection]) }
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
        let local = Self.localFormatter(data.schedule.timeZoneID, "dd/MM/yyyy")
        var rows = [["Date", "Supplier", "Supplier ABN", "Tax invoice check", "Invoice number", "Items purchased", "Total AUD", "GST AUD", "Category", "Custom category", "Work use percent (unverified)", "Reimbursed AUD", "Accountant review status", "Notes", "Original PDF", "Invoice ID", "Invoice date UTC", "Captured UTC", "Receipt checked"]]
        for i in receipts {
            let total = Decimal(string: i.total, locale: Locale(identifier: "en_US_POSIX")) ?? 0
            let hasABN = (i.abn ?? "").filter(\.isNumber).count == 11
            let check = total < Self.taxInvoiceThreshold ? "Under $82.50" : (hasABN ? "Supplier ABN recorded" : "ABN missing — check the tax invoice")
            rows.append([local.string(from: i.date), i.supplier, i.abn ?? "", check, i.number, i.items ?? "", i.total, i.gst, i.category ?? "Other", i.customCategory ?? "", i.workPercent ?? "", i.reimbursed ?? "", i.taxStatus ?? "Needs accountant review", i.notes, i.pdfFilename, i.id.uuidString, formatter.string(from: i.date), formatter.string(from: i.captured), i.receiptReviewed == true ? "Yes" : "No"])
        }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let register = try exportURL("Worklog-invoices-FY-\(year).csv")
        try Data(csv.utf8).write(to: register, options: [.atomic, .completeFileProtection])
        let perVehicle = vehicles.map { v in "\(v.displayName): \(String(format: "%.1f", data.trips.filter { $0.vehicleID == v.id }.reduce(0) { $0 + $1.km(in: interval) })) km" }.joined(separator: "; ")
        let checklist = atoChecklist(year: year)
        let summary = "Worklog accountant export: 1 July \(year) to 30 June \(year+1). Work kilometres: \(String(format: "%.1f", data.trips.reduce(0) { $0 + $1.km(in: interval) })).\(perVehicle.isEmpty ? "" : " By vehicle: \(perVehicle).")\n\nFiles: trip log (all vehicles, and one per vehicle), vehicle logbook summary (make, model, engine, registration, logbook period, odometer readings, business-use percentage), receipt register with tax-invoice ABN check, original receipt PDFs.\n\nATO record check: " + (checklist.isEmpty ? "no missing items found." : "\n- " + checklist.joined(separator: "\n- ")) + "\n\nInvoice categories, amounts and business-use proportions are user-entered and require review. Kilometres come from GPS unless corrected; odometer readings are entered by the driver. The accountant decides deductibility. No automatic deletion applies; keep records for at least 5 years from lodgement.\n"
        let note = try exportURL("Worklog-accountant-notes-FY-\(year).txt")
        try Data(summary.utf8).write(to: note, options: [.atomic, .completeFileProtection])
        var transactionFiles: [URL] = []
        for invoice in receipts {
            let url = try exportURL("receipt-\(invoice.id.uuidString).json")
            try receiptBytes(invoice).write(to: url, options: [.atomic, .completeFileProtection]); transactionFiles.append(url)
        }
        let vehicleLogs = vehicles.count > 1 ? try vehicles.filter { v in data.trips.contains { $0.vehicleID == v.id } }.map { try csvExport(year: year, vehicle: $0) } : []
        return [try csvExport(year: year), try logbookSummaryExport(year: year), register, note] + vehicleLogs + receipts.map { pdfURL($0) } + transactionFiles
    }
    static func localFormatter(_ timeZoneID: String, _ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_AU"); f.timeZone = TimeZone(identifier: timeZoneID) ?? .current; f.dateFormat = format; return f
    }
    /// One row per vehicle with the ATO logbook details and business-use percentage.
    func logbookSummaryExport(year: Int) throws -> URL {
        let day = Self.localFormatter(data.schedule.timeZoneID, "dd/MM/yyyy")
        func cell(_ value: String) -> String {
            let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func km(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "" }
        var rows = [["Vehicle", "Make", "Model", "Engine capacity", "Registration", "Logbook start", "Logbook end", "Logbook weeks", "Odometer at logbook start", "Odometer at logbook end", "Total km in logbook period", "Business km in logbook period", "Business-use percentage", "Odometer 1 July \(year)", "Odometer 30 June \(year + 1)", "Total km in financial year", "Work km in financial year", "Missing for ATO"]]
        for v in vehicles {
            let s = logbookSummary(v, year: year)
            rows.append([v.name, v.make ?? "", v.model ?? "", v.engineCapacity ?? "", v.registration, v.logbookStart.map { day.string(from: $0) } ?? "", v.logbookEnd.map { day.string(from: $0) } ?? "",
                         s.logbookWeeks.map { String(format: "%.1f", $0) } ?? "", km(v.logbookStartOdometer), km(v.logbookEndOdometer), km(s.logbookTotalKm), km(s.logbookBusinessKm),
                         s.businessPercent.map { String(format: "%.1f%%", $0) } ?? "", km(s.yearStartOdometer), km(s.yearEndOdometer), km(s.yearTotalKm), km(s.yearWorkKm), s.issues.joined(separator: " ")])
        }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let url = try exportURL("Worklog-vehicle-logbook-FY-\(year)-\(year+1).csv")
        try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    /// Trip log for the financial year; pass a vehicle for that vehicle's own log.
    func csvExport(year: Int, vehicle: Vehicle? = nil) throws -> URL {
        let interval = FinancialYear.interval(year, timeZone: data.schedule.timeZoneID)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        func cell(_ value: String) -> String {
            let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let tz = data.schedule.timeZoneID
        let day = Self.localFormatter(tz, "dd/MM/yyyy"), time = Self.localFormatter(tz, "HH:mm")
        var rows = [["Start date", "Start time", "End date", "End time", "Reason for journey", "Journey type", "Vehicle", "Registration", "Make and model", "Odometer start km", "Odometer finish km", "Km by odometer", "Km travelled", "Work km in selected FY", "GPS km", "Recording", "Review", "Correction reason", "Home/work check", "Stops (minutes)", "Started UTC", "Finished UTC", "Time zone", "Trip ID"]]
        for t in data.trips.sorted(by: { $0.start < $1.start }) where (t.end ?? t.start) > interval.start && t.start < interval.end && (vehicle == nil || t.vehicleID == vehicle?.id) {
            let v = self.vehicle(t.vehicleID)
            let odoKm = t.odometerStart.flatMap { s in t.odometerEnd.map { String(format: "%.1f", $0 - s) } } ?? ""
            rows.append([day.string(from: t.start), time.string(from: t.start), t.end.map { day.string(from: $0) } ?? "", t.end.map { time.string(from: $0) } ?? "",
                         t.purpose, t.excluded == true ? "Private" : "Business", t.vehicle, v?.registration ?? "", v?.makeModel ?? "",
                         t.odometerStart.map { String(format: "%.1f", $0) } ?? "", t.odometerEnd.map { String(format: "%.1f", $0) } ?? "", odoKm,
                         String(format: "%.1f", t.km), String(format: "%.3f", t.km(in: interval)), String(format: "%.3f", t.metres / 1000), t.automatic ? "Scheduled" : "Manual",
                         t.reviewReasons.joined(separator: "; "), t.correctionReason,
                         placeAssessment(t).map { "\($0.short) \($0.message)" } ?? (t.placeReviewed == true ? "Confirmed work by driver" : ""),
                         (t.pauses ?? []).map { String(Int($0.duration / 60)) }.joined(separator: "; "),
                         formatter.string(from: t.start), t.end.map { formatter.string(from: $0) } ?? "", t.timeZoneID, t.id.uuidString])
        }
        let csv = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let suffix = vehicle.map { "-" + $0.displayName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-") } ?? ""
        let url = try exportURL("Worklog-FY-\(year)-\(year+1)\(suffix).csv")
        try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
}
enum StoreError: LocalizedError {
    case invalidBackup, unavailable, activeTrip, tooLarge, vehicleInUse, passwordNeeded, wrongPassword, weakPassword
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This is not a valid Worklog iOS backup."
        case .unavailable: return "Local saving is unavailable. Check the storage error before continuing."
        case .activeTrip: return "Finish the current trip before backing up or restoring."
        case .tooLarge: return "This backup is too large to restore in memory."
        case .vehicleInUse: return "This vehicle has saved trips, so it can't be deleted. Rename it instead."
        case .passwordNeeded: return "This backup is encrypted. Enter its password to restore it."
        case .wrongPassword: return "That password doesn't open this backup. Nothing was restored."
        case .weakPassword: return "Use a backup password of at least 8 characters."
        }
    }
}

/// Password-encrypted backups: AES-256-GCM with a key derived by PBKDF2-HMAC-SHA256 and a random salt.
/// The password is never stored; a lost password means the backup can't be opened.
enum BackupCrypto {
    static let format = "worklog-ios-backup-encrypted"
    static let rounds: UInt32 = 310_000
    struct Envelope: Codable {
        var format = BackupCrypto.format
        var version = 1
        var kdf = "PBKDF2-HMAC-SHA256"
        /// "lzfse" when the backup was compressed before encryption (smaller files).
        var compression: String? = nil
        var rounds: UInt32
        var salt: Data
        var sealed: Data
    }
    static func key(_ password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let length = password.utf8.count
        let status = derived.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, length,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     out.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        guard status == kCCSuccess else { throw StoreError.invalidBackup }
        return SymmetricKey(data: derived)
    }
    static func seal(_ plain: Data, password: String, compression: String? = nil) throws -> Data {
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard ok == errSecSuccess else { throw StoreError.unavailable }
        guard let combined = try AES.GCM.seal(plain, using: key(password, salt: salt, rounds: rounds)).combined else { throw StoreError.unavailable }
        return try JSONEncoder().encode(Envelope(compression: compression, rounds: rounds, salt: salt, sealed: combined))
    }
    static func isEncrypted(_ bytes: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: bytes))?.format == format
    }
    static func open(_ bytes: Data, password: String) throws -> Data {
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.format == format, envelope.version == 1, (100_000...5_000_000).contains(envelope.rounds), envelope.salt.count >= 16 else { throw StoreError.invalidBackup }
        let plain: Data
        do { plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key(password, salt: envelope.salt, rounds: envelope.rounds)) }
        catch { throw StoreError.wrongPassword }
        guard let compression = envelope.compression else { return plain }
        guard compression == "lzfse" else { throw StoreError.invalidBackup }
        return try WorkStore.decompress(plain)
    }
}
