import XCTest
import CoreLocation
@testable import Worklog

final class WorklogTests: XCTestCase {
    let iso = ISO8601DateFormatter()
    func testWeekdayScheduleAndBoundaries() {
        let schedule = WorkSchedule()
        XCTAssertNotNil(schedule.window(at: iso.date(from: "2026-09-14T07:00:00+08:00")!))
        XCTAssertNil(schedule.window(at: iso.date(from: "2026-09-14T17:00:00+08:00")!))
        XCTAssertNil(schedule.window(at: iso.date(from: "2026-09-13T10:00:00+08:00")!))
    }
    func testOvernightUsesStartingWeekday() {
        var schedule = WorkSchedule(); schedule.weekdays = [6]; schedule.startMinute = 22*60; schedule.endMinute = 6*60
        XCTAssertNotNil(schedule.window(at: iso.date(from: "2026-09-12T05:00:00+08:00")!))
        XCTAssertNil(schedule.window(at: iso.date(from: "2026-09-12T06:00:00+08:00")!))
        XCTAssertNil(schedule.window(at: iso.date(from: "2026-09-13T05:00:00+08:00")!))
    }
    func testFinancialYearChangesOnJulyFirst() {
        XCTAssertEqual(FinancialYear.startYear(for: iso.date(from: "2026-06-30T23:59:59+08:00")!), 2025)
        XCTAssertEqual(FinancialYear.startYear(for: iso.date(from: "2026-07-01T00:00:00+08:00")!), 2026)
    }
    func testCrossYearDistanceSplit() {
        let start = iso.date(from: "2026-06-30T23:59:50+08:00")!, end = iso.date(from: "2026-07-01T00:00:10+08:00")!
        var trip = Trip(purpose: "Work", vehicle: "Van", start: start, automatic: false, timeZoneID: "Australia/Perth")
        trip.end = end
        var point = GPSPoint(CLLocation(latitude: -33.3, longitude: 115.6)); point.date = end; point.segmentStart = start; point.segmentMetres = 1000
        trip.points = [point]
        XCTAssertEqual(trip.km(in: FinancialYear.interval(2025)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(trip.km(in: FinancialYear.interval(2026)), 0.5, accuracy: 0.0001)
    }
    func testTripLogWeeksRunMondayToSunday() {
        func trip(_ when: String) -> Trip { Trip(purpose: "Work", vehicle: "", start: iso.date(from: when)!, automatic: false, timeZoneID: "Australia/Perth") }
        let sunday = trip("2026-09-13T16:00:00+08:00"), monday = trip("2026-09-14T08:00:00+08:00"), lateMonday = trip("2026-09-14T23:30:00+08:00")
        let weeks = TripCalendar.weeks([sunday, monday, lateMonday], timeZoneID: "Australia/Perth")
        XCTAssertEqual(weeks, [iso.date(from: "2026-09-14T00:00:00+08:00")!, iso.date(from: "2026-09-07T00:00:00+08:00")!])
        let days = TripCalendar.days(inWeek: weeks[0], timeZoneID: "Australia/Perth")
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, iso.date(from: "2026-09-20T00:00:00+08:00")!)
        XCTAssertEqual(TripCalendar.trips([sunday, monday, lateMonday], onDay: days[0], timeZoneID: "Australia/Perth").map(\.id), [monday.id, lateMonday.id])
        XCTAssertEqual(TripCalendar.trips([sunday, monday, lateMonday], inWeek: weeks[1], timeZoneID: "Australia/Perth").map(\.id), [sunday.id])
    }
    func testTripLogYearsAndMonthsFollowFinancialYear() {
        func trip(_ when: String, km: Double, privateTrip: Bool = false) -> Trip {
            var t = Trip(purpose: "Work", vehicle: "", start: iso.date(from: when)!, automatic: false, timeZoneID: "Australia/Perth")
            t.correctedKm = km; if privateTrip { t.excluded = true }; return t
        }
        let june = trip("2026-06-30T20:00:00+08:00", km: 10), july = trip("2026-07-01T08:00:00+08:00", km: 20)
        let lateJuly = trip("2026-07-31T23:00:00+08:00", km: 5, privateTrip: true), sept = trip("2026-09-30T09:00:00+08:00", km: 7)
        let all = [june, july, lateJuly, sept]
        XCTAssertEqual(TripCalendar.financialYears(all, timeZoneID: "Australia/Perth"), [2026, 2025])
        let months = TripCalendar.months(all, timeZoneID: "Australia/Perth")
        XCTAssertEqual(months.first, iso.date(from: "2026-09-01T00:00:00+08:00")!)
        XCTAssertEqual(months.count, 3)
        let julySpan = TripCalendar.monthInterval(of: iso.date(from: "2026-07-15T00:00:00+08:00")!, timeZoneID: "Australia/Perth")
        let julyTrips = TripCalendar.trips(all, within: julySpan)
        XCTAssertEqual(julyTrips.count, 2)
        XCTAssertEqual(TripCalendar.workKm(julyTrips), 20, accuracy: 0.001, "Private trips are left out of totals")
    }
    func testDataRoundTrip() throws {
        var data = WorkData(); data.schedule.enabled = true
        let decoded = try JSONDecoder().decode(WorkData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.schedule, data.schedule)
    }

    func testPersonalTripExcludedAndCorrectionCrossesYear() {
        let start = iso.date(from: "2026-06-30T23:59:50+08:00")!
        var trip = Trip(purpose: "Work", vehicle: "Van", start: start, automatic: false, timeZoneID: "Australia/Perth")
        trip.end = start.addingTimeInterval(20)
        trip.correctedKm = 2
        XCTAssertEqual(trip.km(in: FinancialYear.interval(2026)), 1, accuracy: 0.0001)
        trip.excluded = true
        XCTAssertEqual(trip.km(in: FinancialYear.interval(2026)), 0)
    }

    @MainActor func testDescriptionPersistsAndCorruptFileIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        XCTAssertTrue(store.rememberTripDescription("Supply pickup"))
        XCTAssertEqual(WorkStore(root: root).lastTripDescription, "Supply pickup")
        let broken = Data("not-json".utf8)
        try broken.write(to: store.file)
        let recovered = WorkStore(root: root)
        XCTAssertTrue(recovered.loadFailed)
        XCTAssertFalse(recovered.save())
        XCTAssertEqual(try Data(contentsOf: store.file), broken)
    }

    @MainActor func testAccountantExportKeepsOdometerAndEscapesSpreadsheetFormula() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        let start = iso.date(from: "2026-09-14T08:00:00+08:00")!
        var trip = Trip(purpose: "=1+1", vehicle: "Van", start: start, automatic: false, timeZoneID: "Australia/Perth")
        trip.end = start.addingTimeInterval(600)
        trip.odometerStart = 128450
        trip.odometerEnd = 128460
        store.data.trips = [trip]
        let csv = try String(contentsOf: store.csvExport(year: 2026), encoding: .utf8)
        XCTAssertTrue(csv.contains("\"'=1+1\""))
        XCTAssertTrue(csv.contains("128450.0"))
        XCTAssertTrue(csv.contains("128460.0"))
        XCTAssertTrue(csv.contains("2026-09-14T00:00:00Z"))
    }

    @MainActor func testBackupRestorePreservesPreferencesDocumentsAndExistingIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: otherRoot) }
        let source = WorkStore(root: root)
        XCTAssertTrue(source.rememberTripDescription("Supply pickup"))
        source.data.schedule.enabled = true
        source.data.schedule.vehicle = "TEST-14"
        let document = Data("%PDF-1.4\nfixture bytes for storage round-trip\n%%EOF".utf8)
        let invoice = Invoice(supplier: "Test supplier", number: "1", date: Date(), total: "110.00", gst: "10.00", notes: "", pdfFilename: "test.pdf")
        try source.saveInvoice(invoice, pdf: document)
        let backup = try source.exportBackup()
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = WorkStore(root: otherRoot)
        try restored.restoreBackup(backup)
        XCTAssertEqual(restored.lastTripDescription, "Supply pickup")
        XCTAssertEqual(restored.data.schedule.vehicle, "TEST-14")
        XCTAssertFalse(restored.data.schedule.enabled)
        XCTAssertEqual(try Data(contentsOf: restored.pdfURL(restored.data.invoices[0])), document)
        restored.data.invoices[0].notes = "Keep local edit"
        try restored.restoreBackup(backup)
        XCTAssertEqual(restored.data.invoices.count, 1)
        XCTAssertEqual(restored.data.invoices[0].notes, "Keep local edit")
    }
}


@MainActor private final class FakeOwnerAuthenticator: OwnerAuthenticating {
    var allowed = true
    var duringAuthentication: (() -> Void)?
    private(set) var cancelled = false
    private(set) var calls = 0
    func authenticate(reason: String) async throws -> Bool {
        calls += 1
        duringAuthentication?()
        return allowed
    }
    func cancel() { cancelled = true }
}

final class AppLockTests: XCTestCase {
    @MainActor func testFaceIDPromptsAutomaticallyOncePerLock() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = FakeOwnerAuthenticator()
        let lock = AppLock(preferenceFile: directory.appendingPathComponent("lock.json"), makeAuthenticator: { auth })
        await lock.autoUnlockIfNeeded()
        XCTAssertEqual(auth.calls, 0, "No prompt while app lock is off")
        await lock.setEnabled(true)
        lock.enteredBackground(); lock.becameActive()
        let before = auth.calls
        auth.allowed = false
        await lock.autoUnlockIfNeeded()
        XCTAssertEqual(auth.calls, before + 1, "Opening the locked app asks for Face ID")
        XCTAssertFalse(lock.canShowRecords)
        await lock.autoUnlockIfNeeded()
        XCTAssertEqual(auth.calls, before + 1, "A cancelled prompt is not repeated automatically")
        auth.allowed = true
        await lock.unlock()
        XCTAssertTrue(lock.canShowRecords, "Unlock button still works")
        lock.enteredBackground(); lock.becameActive()
        await lock.autoUnlockIfNeeded()
        XCTAssertEqual(auth.calls, before + 3, "Each new lock asks again")
        XCTAssertTrue(lock.canShowRecords)
    }
    @MainActor func testEnablePersistUnlockAndBackgroundLock() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("lock.json")
        let auth = FakeOwnerAuthenticator()
        let lock = AppLock(preferenceFile: path, makeAuthenticator: { auth })
        XCTAssertTrue(lock.canShowRecords)
        await lock.setEnabled(true)
        XCTAssertTrue(lock.enabled)
        XCTAssertTrue(lock.isUnlocked)
        lock.enteredBackground()
        XCTAssertFalse(lock.canShowRecords)
        lock.becameActive()
        auth.allowed = false
        await lock.unlock()
        XCTAssertFalse(lock.canShowRecords)
        auth.allowed = true
        await lock.unlock()
        XCTAssertTrue(lock.canShowRecords)
        let reloaded = AppLock(preferenceFile: path, makeAuthenticator: { auth })
        XCTAssertTrue(reloaded.enabled)
        XCTAssertFalse(reloaded.isUnlocked)
        auth.allowed = false
        await reloaded.setEnabled(false)
        XCTAssertTrue(reloaded.enabled)
        auth.allowed = true
        await reloaded.setEnabled(false)
        XCTAssertFalse(reloaded.enabled)
        XCTAssertFalse(AppLock(preferenceFile: path).enabled)
    }

    @MainActor func testBackgroundCancelsPendingUnlockAndIgnoresLateSuccess() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = FakeOwnerAuthenticator()
        let lock = AppLock(preferenceFile: directory.appendingPathComponent("lock.json"), makeAuthenticator: { auth })
        await lock.setEnabled(true)
        lock.lockNow()
        auth.duringAuthentication = { lock.enteredBackground() }
        await lock.unlock()
        XCTAssertTrue(auth.cancelled)
        XCTAssertFalse(lock.busy)
        XCTAssertFalse(lock.canShowRecords)
        lock.becameActive()
        XCTAssertFalse(lock.canShowRecords)
    }

    @MainActor func testCorruptPreferenceRequiresAuthentication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("lock.json")
        try Data("broken".utf8).write(to: path)
        let lock = AppLock(preferenceFile: path)
        XCTAssertTrue(lock.enabled)
        XCTAssertFalse(lock.canShowRecords)
    }

    @MainActor func testFailedEnableDoesNotCreatePreference() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("lock.json")
        let auth = FakeOwnerAuthenticator(); auth.allowed = false
        let lock = AppLock(preferenceFile: path, makeAuthenticator: { auth })
        await lock.setEnabled(true)
        XCTAssertFalse(lock.enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }
}

final class ReceiptTests: XCTestCase {
    func testReceiptSuggestionSeparatesTotalsFromItems() {
        let result = ReceiptSuggestion.parse("HARDWARE STORE\n22/09/2026 14:35\nHammer $22.00\nBolts $11.00\nSubtotal $30.00\nGST $3.00\nTOTAL $33.00\nEFTPOS $33.00")
        XCTAssertEqual(result.total, "33.00")
        XCTAssertEqual(result.gst, "3.00")
        XCTAssertEqual(result.items, "Hammer | 22.00\nBolts | 11.00")
        XCTAssertNotNil(result.date)
    }
    func testTotalIncludesGSTLineIsGSTNotTotal() {
        let result = ReceiptSuggestion.parse("BUNNINGS WAREHOUSE\nTAX INVOICE\nScrews 50pk $12.98\nSilicone $8.50\nTOTAL $21.48\nTOTAL INCLUDES GST $1.95\nEFTPOS $21.48\n08/10/2026 09:12")
        XCTAssertEqual(result.total, "21.48")
        XCTAssertEqual(result.gst, "1.95")
        let fuel = ReceiptSuggestion.parse("SERVO\nUnleaded 45.20L $88.14\nTotal $88.14\nGST included in total $8.01\n8/10/26")
        XCTAssertEqual(fuel.total, "88.14")
        XCTAssertEqual(fuel.gst, "8.01")
        XCTAssertNotNil(fuel.date)
        XCTAssertEqual(ReceiptSuggestion.parse("SUPPLIER\nService $100.00\nGST $10.00\nTotal incl GST $110.00").total, "110.00")
    }
    @MainActor func testEditingReceiptReplacesOldFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        var invoice = Invoice(supplier: "Shop", number: "1", date: Date(), total: "33.00", gst: "3.00", notes: "", pdfFilename: "receipt-old.pdf")
        try store.saveInvoice(invoice, pdf: Data("%PDF-old".utf8))
        let oldPDF = store.pdfURL(invoice), oldJSON = store.receiptURL(invoice)
        invoice.pdfFilename = "receipt-new.pdf"; invoice.total = "34.00"
        try store.saveInvoice(invoice, pdf: Data("%PDF-new".utf8))
        XCTAssertEqual(store.data.invoices.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldJSON.path))
        XCTAssertEqual(try Data(contentsOf: store.pdfURL(invoice)), Data("%PDF-new".utf8))
    }
    @MainActor func testOldFreeTextVehiclesBecomeVehicles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var old = WorkData(); old.schedule.vehicle = "Hilux"
        old.trips = [Trip(purpose: "Work", vehicle: "Hilux", start: Date(), automatic: false, timeZoneID: "Australia/Perth"),
                     Trip(purpose: "Work", vehicle: "Ranger", start: Date(), automatic: false, timeZoneID: "Australia/Perth")]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: root.appendingPathComponent("worklog.json"))
        let store = WorkStore(root: root)
        XCTAssertEqual(store.vehicles.map(\.name), ["Hilux", "Ranger"])
        XCTAssertEqual(store.currentVehicle?.name, "Hilux")
        XCTAssertEqual(store.data.trips[1].vehicleID, store.vehicles[1].id)
    }
    @MainActor func testCurrentVehicleIsRememberedAfterReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        let hilux = Vehicle(name: "Hilux"), ranger = Vehicle(name: "Ranger", registration: "1XYZ987")
        XCTAssertTrue(store.saveVehicle(hilux)); XCTAssertTrue(store.saveVehicle(ranger))
        XCTAssertEqual(store.currentVehicle?.id, hilux.id)
        XCTAssertTrue(store.selectVehicle(ranger.id))
        XCTAssertEqual(WorkStore(root: root).currentVehicle?.id, ranger.id)
    }
    @MainActor func testOdometerCheckSpotsForgottenVehicleSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        let hilux = Vehicle(name: "Hilux", startingOdometer: 54_200), ranger = Vehicle(name: "Ranger", startingOdometer: 128_390)
        store.saveVehicle(hilux); store.saveVehicle(ranger)
        var trip = Trip(purpose: "Work", vehicle: "Hilux", start: Date(), automatic: false, timeZoneID: "Australia/Perth")
        trip.vehicleID = hilux.id; trip.odometerStart = 54_300; trip.odometerEnd = 54_320
        store.data.trips = [trip]
        XCTAssertNil(store.odometerCheck(reading: 54_335, vehicleID: hilux.id))
        let wrongCar = try XCTUnwrap(store.odometerCheck(reading: 128_450, vehicleID: hilux.id))
        XCTAssertEqual(wrongCar.suggested?.id, ranger.id)
        let lower = try XCTUnwrap(store.odometerCheck(reading: 54_000, vehicleID: hilux.id))
        XCTAssertNil(lower.suggested)
        XCTAssertNil(store.odometerCheck(reading: 128_400, vehicleID: ranger.id))
        XCTAssertThrowsError(try store.deleteVehicle(hilux.id))
    }
    @MainActor func testHomeAndWorkChecksFlagCommuteAndBreak() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        store.data.home = Place(address: "Home", latitude: -32.250, longitude: 148.600)
        store.data.workplace = Place(address: "Depot", latitude: -32.240, longitude: 148.630)
        func point(_ lat: Double, _ lon: Double, _ date: Date) -> GPSPoint {
            var p = GPSPoint(CLLocation(latitude: lat, longitude: lon)); p.date = date; p.accuracy = 10; return p
        }
        func trip(from: (Double, Double), to: (Double, Double), endingAt end: Date) -> Trip {
            var t = Trip(purpose: "Drive", vehicle: "", start: end.addingTimeInterval(-900), automatic: false, timeZoneID: "Australia/Perth")
            t.end = end; t.points = [point(from.0, from.1, t.start), point(to.0, to.1, end)]; return t
        }
        let home = (-32.250, 148.600), work = (-32.240, 148.630), client = (-32.300, 148.700)
        // Monday 14 Sep 2026, schedule Mon–Fri 07:00–17:00 Perth.
        let iso = ISO8601DateFormatter()
        let morning = iso.date(from: "2026-09-14T07:20:00+08:00")!, noon = iso.date(from: "2026-09-14T12:10:00+08:00")!, evening = iso.date(from: "2026-09-14T17:20:00+08:00")!
        XCTAssertEqual(store.placeAssessment(trip(from: home, to: work, endingAt: morning))?.kind, .commute)
        XCTAssertEqual(store.placeAssessment(trip(from: work, to: home, endingAt: noon))?.kind, .homeBreak)
        XCTAssertEqual(store.placeAssessment(trip(from: client, to: home, endingAt: noon))?.kind, .homeBreak)
        XCTAssertEqual(store.placeAssessment(trip(from: work, to: home, endingAt: evening))?.kind, .commute)
        XCTAssertNil(store.placeAssessment(trip(from: work, to: client, endingAt: noon)))
        var confirmed = trip(from: work, to: home, endingAt: noon); confirmed.placeReviewed = true
        XCTAssertNil(store.placeAssessment(confirmed))
    }
    @MainActor func testContinueLastTripKeepsStopAsPause() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        let now = Date()
        var older = Trip(purpose: "Older", vehicle: "", start: now.addingTimeInterval(-7200), automatic: false, timeZoneID: "Australia/Perth")
        older.end = now.addingTimeInterval(-6000)
        var pickup = Trip(purpose: "Supply pickup", vehicle: "", start: now.addingTimeInterval(-3600), automatic: false, timeZoneID: "Australia/Perth")
        pickup.end = now.addingTimeInterval(-1800); pickup.odometerStart = 1000; pickup.odometerEnd = 1020; pickup.correctedKm = nil
        store.data.trips = [pickup, older]; XCTAssertTrue(store.save())
        XCTAssertEqual(store.continuableTrip(now: now)?.id, pickup.id)
        XCTAssertNil(store.continuableTrip(now: now.addingTimeInterval(13 * 3600)), "Too old to continue")
        XCTAssertTrue(store.reopenTrip(pickup.id, at: now))
        let active = try XCTUnwrap(store.data.active)
        XCTAssertEqual(active.id, pickup.id)
        XCTAssertNil(active.end); XCTAssertNil(active.odometerEnd); XCTAssertEqual(active.odometerStart, 1000)
        XCTAssertEqual(active.pauses?.first?.duration ?? 0, 1800, accuracy: 1)
        XCTAssertFalse(store.data.trips.contains { $0.id == pickup.id })
        XCTAssertNil(store.continuableTrip(now: now), "Nothing to continue while a trip is recording")
        XCTAssertFalse(store.reopenTrip(older.id, at: now))
        XCTAssertEqual(WorkStore(root: root).data.active?.id, pickup.id, "Saved immediately")
    }
    @MainActor func testEncryptedBackupNeedsTheRightPassword() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = WorkStore(root: base.appendingPathComponent("source"))
        source.data.trips = [Trip(purpose: "Secret supplier run", vehicle: "", start: Date().addingTimeInterval(-600), end: Date(), automatic: false, timeZoneID: "Australia/Perth")]
        XCTAssertTrue(source.save())
        XCTAssertThrowsError(try source.exportBackup(password: "short"))
        let backup = try source.exportBackup(password: "correct horse 42")
        let bytes = try Data(contentsOf: backup)
        XCTAssertNil(String(data: bytes, encoding: .utf8)?.range(of: "Secret supplier run"), "Trip details must not be readable in the file")
        XCTAssertTrue(BackupCrypto.isEncrypted(bytes))
        let target = WorkStore(root: base.appendingPathComponent("target"))
        XCTAssertThrowsError(try target.restoreBackup(backup)) { XCTAssertEqual($0 as? StoreError, .passwordNeeded) }
        XCTAssertThrowsError(try target.restoreBackup(backup, password: "wrong password")) { XCTAssertEqual($0 as? StoreError, .wrongPassword) }
        XCTAssertTrue(target.data.trips.isEmpty)
        try target.restoreBackup(backup, password: "correct horse 42")
        XCTAssertEqual(target.data.trips.first?.purpose, "Secret supplier run")
    }
    func testOldFilesAppFolderMovesToPrivateStorage() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Documents/Worklog"), secure = base.appendingPathComponent("Library/Application Support/Worklog")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("worklog.json"))
        XCTAssertEqual(WorkStore.moveLegacyStorage(from: legacy, to: secure), secure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secure.appendingPathComponent("worklog.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(WorkStore.moveLegacyStorage(from: legacy, to: secure), secure, "Second launch keeps the private folder")
    }
    @MainActor func testDeletingTripAndReceiptIsPermanent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        let keep = Trip(purpose: "Keep", vehicle: "", start: Date(), automatic: false, timeZoneID: "Australia/Perth")
        let remove = Trip(purpose: "Remove", vehicle: "", start: Date(), automatic: false, timeZoneID: "Australia/Perth")
        store.data.trips = [keep, remove]; XCTAssertTrue(store.save())
        let invoice = Invoice(supplier: "Shop", number: "1", date: Date(), total: "10.00", gst: "", notes: "", pdfFilename: "receipt-delete.pdf")
        try store.saveInvoice(invoice, pdf: Data("%PDF-delete".utf8))
        try store.deleteTrip(remove.id)
        try store.deleteInvoice(invoice.id)
        let reopened = WorkStore(root: root)
        XCTAssertEqual(reopened.data.trips.map(\.id), [keep.id])
        XCTAssertTrue(reopened.data.invoices.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pdfURL(invoice).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.receiptURL(invoice).path))
    }
    func testNoAssumedGSTOrTotal() {
        let result = ReceiptSuggestion.parse("SHOP\nBread $5.00\nSubtotal $5.00")
        XCTAssertEqual(result.gst, "")
        XCTAssertEqual(result.total, "")
    }
    @MainActor func testReceiptPersistsWithOwnTransactionFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkStore(root: root)
        var invoice = Invoice(supplier: "Shop", number: "1", date: Date(), total: "33.00", gst: "3.00", notes: "", pdfFilename: "receipt-test.pdf")
        invoice.items = "Hammer | 22.00\nBolts | 11.00"; invoice.receiptReviewed = true
        try store.saveInvoice(invoice, pdf: Data("%PDF-test".utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.receiptURL(invoice))) as? [String: Any])
        XCTAssertEqual(object["items"] as? String, invoice.items)
        XCTAssertEqual(WorkStore(root: root).data.invoices.first?.items, invoice.items)
        let old = try JSONEncoder().encode(Invoice(supplier: "Old", number: "", date: Date(), total: "1", gst: "", notes: "", pdfFilename: "old.pdf"))
        XCTAssertNil(try JSONDecoder().decode(Invoice.self, from: old).items)
    }
}
