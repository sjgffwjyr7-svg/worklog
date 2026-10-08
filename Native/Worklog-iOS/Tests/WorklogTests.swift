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
    func authenticate(reason: String) async throws -> Bool {
        duringAuthentication?()
        return allowed
    }
    func cancel() { cancelled = true }
}

final class AppLockTests: XCTestCase {
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
