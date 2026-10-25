import SwiftUI
import CoreLocation
import LocalAuthentication
import VisionKit
import Speech
import AVFoundation

// MARK: - App checks

struct CheckResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
}

/// Function tests that run on the phone against a throwaway practice store, never the real records.
@MainActor enum AppSelfTest {
    static func run() -> [CheckResult] {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("WorklogSelfTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        var n = 0
        func store() -> WorkStore { n += 1; return WorkStore(root: base.appendingPathComponent("s\(n)")) }
        func check(_ name: String, _ body: () throws -> (Bool, String)) -> CheckResult {
            do { let (ok, detail) = try body(); return CheckResult(name: name, passed: ok, detail: detail) }
            catch { return CheckResult(name: name, passed: false, detail: "Error: \(error.localizedDescription)") }
        }
        let tz = "Australia/Perth"
        let now = Date()
        return [
            check("Records save and reopen (compressed)") {
                let s = store()
                var trip = Trip(purpose: "Self-test", vehicle: "", start: now.addingTimeInterval(-3600), end: now, automatic: false, timeZoneID: tz)
                for i in 0..<500 {
                    var p = GPSPoint(CLLocation(latitude: -32.25 + Double(i) * 0.0001, longitude: 148.6))
                    p.segmentMetres = 11; trip.points.append(p)
                }
                s.data.trips = [trip]
                guard s.save() else { return (false, "Save failed") }
                let reopened = WorkStore(root: s.root)
                let size = (try? Data(contentsOf: s.file).count) ?? 0
                let plain = (try? JSONEncoder().encode(s.data).count) ?? 0
                let ok = reopened.data.trips.first?.points.count == 500 && size < plain
                return (ok, "500 GPS points saved in \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) (plain \(ByteCountFormatter.string(fromByteCount: Int64(plain), countStyle: .file)))")
            },
            check("Encrypted backup and restore") {
                let a = store()
                a.data.trips = [Trip(purpose: "Backup test", vehicle: "", start: now.addingTimeInterval(-600), end: now, automatic: false, timeZoneID: tz)]
                _ = a.save()
                let url = try a.exportBackup(password: "self-test-password")
                defer { try? FileManager.default.removeItem(at: url) }
                let b = store()
                let wrongRejected = (try? b.restoreBackup(url, password: "wrong password")) == nil
                try b.restoreBackup(url, password: "self-test-password")
                let ok = wrongRejected && b.data.trips.first?.purpose == "Backup test"
                return (ok, ok ? "Wrong password refused; right password restored" : "Restore didn't match")
            },
            check("Receipt reading (total and GST)") {
                let r = ReceiptSuggestion.parse("BUNNINGS WAREHOUSE\nScrews $12.98\nSilicone $8.50\nTOTAL $21.48\nTOTAL INCLUDES GST $1.95\n08/10/2026 09:12")
                return (r.total == "21.48" && r.gst == "1.95", "Read total \(r.total), GST \(r.gst)")
            },
            check("Wrong-vehicle odometer check") {
                let s = store()
                let hilux = Vehicle(name: "Hilux", startingOdometer: 54_200), ranger = Vehicle(name: "Ranger", startingOdometer: 128_390)
                s.saveVehicle(hilux); s.saveVehicle(ranger)
                let suggestion = s.odometerCheck(reading: 128_450, vehicleID: hilux.id)?.suggested?.name
                return (suggestion == "Ranger", "128,450 km in the Hilux → suggests \(suggestion ?? "nothing")")
            },
            check("Weeks run Monday to Sunday") {
                let iso = ISO8601DateFormatter()
                let sunday = iso.date(from: "2026-09-13T16:00:00+08:00")!
                let start = TripCalendar.weekStart(of: sunday, timeZoneID: tz)
                let ok = start == iso.date(from: "2026-09-07T00:00:00+08:00")!
                return (ok, "Sunday 13 Sep belongs to the week starting \(start.formatted(.dateTime.weekday(.wide).day().month(), in: tz))")
            },
            check("Hours: clock on, breaks, clock off") {
                let s = store()
                let start = now.addingTimeInterval(-9 * 3600)
                guard s.clockOn(place: .workplace, at: start), s.startBreak(at: start.addingTimeInterval(4 * 3600)),
                      s.endBreak(at: start.addingTimeInterval(4.75 * 3600)), let shift = s.clockOff(at: start.addingTimeInterval(8.25 * 3600)) else { return (false, "A step failed") }
                return (abs(shift.workedSeconds() - 7.5 * 3600) < 1, "8 h 15 m less 45 m break = \(hoursText(shift.workedSeconds()))")
            },
            check("Continue last trip") {
                let s = store()
                var trip = Trip(purpose: "Parts pickup", vehicle: "", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800), automatic: false, timeZoneID: tz)
                trip.odometerStart = 1000
                s.data.trips = [trip]; _ = s.save()
                guard s.reopenTrip(trip.id, at: now) else { return (false, "Couldn't reopen") }
                let pause = s.data.active?.pauses?.first?.duration ?? 0
                return (abs(pause - 1800) < 1, "Reopened with a \(Int(pause / 60)) min stop recorded")
            },
            check("Commute and break-at-home tags") {
                let s = store()
                s.data.home = Place(address: "Home", latitude: -32.25, longitude: 148.60)
                s.data.workplace = Place(address: "Depot", latitude: -32.24, longitude: 148.63)
                func point(_ lat: Double, _ lon: Double, _ d: Date) -> GPSPoint { var p = GPSPoint(CLLocation(latitude: lat, longitude: lon)); p.date = d; p.accuracy = 10; return p }
                let iso = ISO8601DateFormatter()
                let morning = iso.date(from: "2026-09-14T07:20:00+08:00")!
                var commute = Trip(purpose: "Drive", vehicle: "", start: morning.addingTimeInterval(-900), end: morning, automatic: false, timeZoneID: tz)
                commute.points = [point(-32.25, 148.60, commute.start), point(-32.24, 148.63, morning)]
                let kind = s.placeAssessment(commute)?.kind
                return (kind == .commute, kind == .commute ? "Home → work tagged Commute?" : "Not tagged")
            },
            check("ATO record check finds missing details") {
                let s = store()
                let car = Vehicle(name: "Test ute")
                s.saveVehicle(car)
                var trip = Trip(purpose: "Site visit", vehicle: "Test ute", start: now.addingTimeInterval(-3600), end: now, automatic: false, timeZoneID: tz)
                trip.vehicleID = car.id; s.data.trips = [trip]
                let issues = s.atoChecklist(year: FinancialYear.startYear(for: now, timeZone: s.data.schedule.timeZoneID))
                let ok = issues.contains { $0.contains("registration") } && issues.contains { $0.contains("logbook period") }
                return (ok, "\(issues.count) items flagged for an incomplete vehicle")
            },
            check("Delete is permanent") {
                let s = store()
                let trip = Trip(purpose: "Delete me", vehicle: "", start: now.addingTimeInterval(-60), end: now, automatic: false, timeZoneID: tz)
                s.data.trips = [trip]; _ = s.save()
                try s.deleteTrip(trip.id)
                let gone = WorkStore(root: s.root).data.trips.isEmpty
                return (gone, gone ? "Trip removed and stays removed after reopening" : "Trip came back")
            },
            check("Receipt photos compress") {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let photo = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 4000), format: format).image { ctx in
                    UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 4000))
                    for row in 0..<60 { ("Line \(row)  Bolts M8 zinc  $\(row).95" as NSString).draw(at: CGPoint(x: 100, y: 100 + row * 60), withAttributes: [.font: UIFont.systemFont(ofSize: 40)]) }
                }
                guard let pdf = ReceiptCompression.pdf(from: [photo]) else { return (false, "Couldn't build the PDF") }
                return (pdf.count < 700_000, "A 12-megapixel page stored in \(ByteCountFormatter.string(fromByteCount: Int64(pdf.count), countStyle: .file))")
            },
        ]
    }

    /// Read-only checks of the phone's settings that Worklog depends on.
    static func phoneChecks(recorder: TripRecorder, lock: AppLock) -> [CheckResult] {
        var results: [CheckResult] = []
        let context = LAContext()
        var error: NSError?
        let passcode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        results.append(CheckResult(name: "iPhone passcode", passed: passcode, detail: passcode ? "Set — your records are encrypted with it" : "No passcode: set one in Settings → Face ID & Passcode. Encryption depends on it."))
        let biometric = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        results.append(CheckResult(name: "Face ID", passed: biometric, detail: biometric ? (context.biometryType == .faceID ? "Available" : "Touch ID available") : "Not set up — the passcode is used instead"))
        results.append(CheckResult(name: "Worklog app lock", passed: lock.enabled, detail: lock.enabled ? "On" : "Off — turn on in Settings → App security"))
        let auth = recorder.authorization
        results.append(CheckResult(name: "Location permission", passed: auth == .authorizedAlways,
                                   detail: auth == .authorizedAlways ? "Always — scheduled trips can record while locked" : auth == .authorizedWhenInUse ? "While using — manual trips work; choose Always for scheduled trips" : "Not allowed — trips can't record. Allow in Settings → Worklog → Location"))
        let precise = CLLocationManager().accuracyAuthorization == .fullAccuracy
        results.append(CheckResult(name: "Precise location", passed: precise, detail: precise ? "On" : "Off — kilometres will be less accurate"))
        let scanner = VNDocumentCameraViewController.isSupported
        results.append(CheckResult(name: "Receipt scanner camera", passed: scanner, detail: scanner ? "Available" : "Not available on this device"))
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        results.append(CheckResult(name: "Free storage", passed: free > 1_000_000_000, detail: ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free"))
        return results
    }
}

// MARK: - Practice Siri

/// Rehearses Worklog's voice commands: same phrases, follow-up questions and replies as the real Siri actions.
/// In practice mode it works on a copy of your data, so nothing real changes.
@MainActor final class PracticeSiri: ObservableObject {
    struct Line: Identifiable { let id = UUID(); let fromUser: Bool; let text: String }
    enum Pending {
        case tripPurpose
        case tripOdometer(purpose: String)
        case confirmTrip(purpose: String, odometer: Double, vehicleID: UUID?)
        case confirmContinue(UUID)
        case vehicleName
        case odometerForActive
    }
    @Published var lines: [Line] = []
    @Published var practice = true { didSet { pending = nil; if practice { makeSandbox() } } }
    var speakReplies = true
    private(set) var pending: Pending?
    let realStore: WorkStore
    let recorder: TripRecorder?
    private(set) var sandbox: WorkStore
    private let synth = AVSpeechSynthesizer()
    var store: WorkStore { practice ? sandbox : realStore }

    init(realStore: WorkStore, recorder: TripRecorder?) {
        self.realStore = realStore; self.recorder = recorder
        sandbox = WorkStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("WorklogPractice-\(UUID().uuidString)"))
        makeSandbox()
    }
    private func makeSandbox() {
        try? FileManager.default.removeItem(at: sandbox.root)
        sandbox = WorkStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("WorklogPractice-\(UUID().uuidString)"))
        sandbox.data = realStore.data
        sandbox.save()
    }

    func hear(_ raw: String) {
        let said = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        lines.append(Line(fromUser: true, text: said))
        reply(respond(to: Self.normalise(said)))
    }
    private func reply(_ text: String) {
        lines.append(Line(fromUser: false, text: text))
        guard speakReplies else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
    /// Lower-case, without "hey Siri", "in Worklog" or trailing punctuation.
    static func normalise(_ text: String) -> String {
        var t = text.lowercased().replacingOccurrences(of: "’", with: "'")
        for junk in ["hey siri,", "hey siri", "siri,", "in worklog", "in work log", "on worklog"] { t = t.replacingOccurrences(of: junk, with: " ") }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        return t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func number(in text: String) -> Double? {
        let digits = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "").filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }
    static func isYes(_ t: String) -> Bool { ["yes", "yeah", "yep", "yup", "confirm", "ok", "okay", "sure", "do it", "start", "go"].contains { t == $0 || t.hasPrefix($0 + " ") } }
    static func isNo(_ t: String) -> Bool { ["no", "nope", "cancel", "stop", "don't", "never mind"].contains { t == $0 || t.hasPrefix($0 + " ") } }

    func respond(to t: String) -> String {
        if let pending { return answer(t, to: pending) }
        let s = store
        if t.contains("finish work") || t.contains("clock off") || t.contains("end my shift") || t.contains("finish my shift") {
            guard s.data.activeShift != nil else { return "You're not clocked on. Say start work in Worklog to begin, or add the hours in the app." }
            guard let shift = s.clockOff() else { return "Work wasn't finished because saving failed." }
            let tz = s.data.schedule.timeZoneID
            let week = DateInterval(start: TripCalendar.weekStart(of: Date(), timeZoneID: tz), duration: 7 * 86400)
            let weekSeconds = s.shifts.filter { week.contains($0.start) }.reduce(0) { $0 + $1.workedSeconds() }
            return "Clocked off. You worked \(hoursText(shift.workedSeconds())) this shift, and \(hoursText(weekSeconds)) so far this week."
        }
        if (t.contains("start work") && !t.contains("trip")) || t.contains("clock on") || t.contains("start my shift") {
            if let shift = s.data.activeShift { return "You're already clocked on since \(shift.start.formatted(date: .omitted, time: .shortened))." }
            let place = LastShiftPlace.value
            guard s.clockOn(place: place) else { return "Work wasn't started because saving failed." }
            return "Clocked on at \(Date().formatted(date: .omitted, time: .shortened)), \(place.rawValue.lowercased()). Say finish work in Worklog when you're done."
        }
        if t.contains("start my break") || t.contains("take a break") || t.contains("start break") {
            guard let shift = s.data.activeShift else { return "You're not clocked on." }
            guard shift.breakStart == nil else { return "You're already on a break." }
            return s.startBreak() ? "Break started. Say end my break in Worklog when you're back." : "The break wasn't saved."
        }
        if t.contains("end my break") || t.contains("back to work") || t.contains("end break") {
            guard let started = s.data.activeShift?.breakStart else { return "You're not on a break." }
            return s.endBreak() ? "Welcome back. That break was \(hoursText(Date().timeIntervalSince(started)))." : "The break wasn't saved."
        }
        if (t.contains("continue") && t.contains("trip")) || t.contains("resume my trip") || t.contains("head back") {
            guard s.data.active == nil else { return "A trip is already recording." }
            guard let trip = s.continuableTrip(), let end = trip.end else { return "There's no trip from the last 12 hours to continue. Say start a work trip in Worklog instead." }
            pending = .confirmContinue(trip.id)
            return "Continue your trip for \(trip.purpose), which stopped \(hoursText(Date().timeIntervalSince(end))) ago?"
        }
        if t.contains("trip") && (t.contains("start") || t.contains("record")) {
            guard s.data.active == nil else { return "A trip is already recording. Finish it before starting another." }
            if t.contains("last description") {
                let last = s.lastTripDescription
                guard !last.isEmpty else { pending = .tripPurpose; return "What is the purpose of this work trip?" }
                pending = .tripOdometer(purpose: last)
                return "What is the vehicle's current odometer reading in kilometres?"
            }
            if let purpose = Self.purpose(in: t) {
                pending = .tripOdometer(purpose: purpose)
                return "What is the vehicle's current odometer reading in kilometres?"
            }
            pending = .tripPurpose
            return "What is the purpose of this work trip?"
        }
        if t.contains("vehicle") || t.hasPrefix("i'm driving") || t.hasPrefix("im driving") || t.hasPrefix("switch to") {
            if let match = vehicle(named: t) { return selectVehicle(match) }
            pending = .vehicleName
            let names = s.vehicles.map(\.name).joined(separator: ", ")
            return names.isEmpty ? "You haven't added any vehicles yet. Add one in Settings." : "Which vehicle are you driving? \(names)."
        }
        if t.contains("starting odometer") || t.contains("starting kilometres") {
            guard s.data.active != nil else { return "There is no active trip. Start a trip first." }
            pending = .odometerForActive
            return "What is the starting odometer reading in kilometres?"
        }
        return "Sorry, that isn't a Worklog command. Try: start work, finish work, start a work trip, continue my trip, or change vehicle."
    }

    /// "start a trip for supply pickup" / "start a supply pickup trip" → "Supply pickup".
    static func purpose(in t: String) -> String? {
        var found: String?
        if let r = t.range(of: " for ") { found = String(t[r.upperBound...]) }
        else if let a = t.range(of: "start a "), let b = t.range(of: " trip", range: a.upperBound..<t.endIndex) {
            let middle = String(t[a.upperBound..<b.lowerBound])
            if !["work", "new", ""].contains(middle) { found = middle.replacingOccurrences(of: "work ", with: "") }
        }
        guard let value = found?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private func answer(_ t: String, to state: Pending) -> String {
        let s = store
        switch state {
        case .tripPurpose:
            if Self.isNo(t) { pending = nil; return "OK, nothing was started." }
            let purpose = t.prefix(1).uppercased() + t.dropFirst()
            pending = .tripOdometer(purpose: purpose)
            return "What is the vehicle's current odometer reading in kilometres?"
        case .tripOdometer(let purpose):
            if Self.isNo(t) { pending = nil; return "OK, nothing was started." }
            guard let reading = Self.number(in: t), reading >= 0 else { return "Give the vehicle's current odometer reading as a number of kilometres." }
            var vehicleID = s.currentVehicle?.id, note = ""
            if let check = s.odometerCheck(reading: reading, vehicleID: vehicleID) {
                if let suggested = check.suggested {
                    vehicleID = suggested.id
                    note = "That reading is close to the \(suggested.displayName)'s last odometer, so I'll record this trip in the \(suggested.displayName). "
                } else { note = check.message + " " }
            }
            pending = .confirmTrip(purpose: purpose, odometer: reading, vehicleID: vehicleID)
            let inVehicle = s.vehicle(vehicleID).map { " in the \($0.displayName)" } ?? ""
            return "\(note)Start a work trip for \(purpose)\(inVehicle), with the odometer at \(reading.formatted(.number.grouping(.automatic))) kilometres?"
        case .confirmTrip(let purpose, let odometer, let vehicleID):
            pending = nil
            guard Self.isYes(t) else { return "OK, nothing was started." }
            if practice {
                var trip = Trip(purpose: purpose, vehicle: s.vehicle(vehicleID)?.displayName ?? "", start: Date(), automatic: false, timeZoneID: s.data.schedule.timeZoneID)
                trip.odometerStart = odometer; trip.vehicleID = vehicleID
                s.data.active = trip
                guard s.save() else { return "Trip not started. Saving failed." }
            } else {
                guard let recorder, recorder.startManual(purpose: purpose, startingOdometer: odometer, vehicleID: vehicleID) else { return "Trip not started. \(recorder?.status ?? "")" }
            }
            let inVehicle = s.vehicle(vehicleID).map { " in the \($0.displayName)" } ?? ""
            return "Started your work trip for \(purpose)\(inVehicle). Starting odometer \(odometer.formatted(.number.grouping(.automatic))) kilometres saved." + (practice ? " (Practice — no GPS recorded.)" : " Waiting for GPS.")
        case .confirmContinue(let id):
            pending = nil
            guard Self.isYes(t) else { return "OK, the trip stays finished." }
            let ok = practice ? s.reopenTrip(id) : (recorder?.continueLastTrip() ?? false)
            return ok ? "Continuing the trip. The stop has been noted" + (practice ? " (practice)." : " and GPS recording has resumed.") : "Trip not continued."
        case .vehicleName:
            pending = nil
            guard let match = vehicle(named: t) else { return "I couldn't find that vehicle. Your vehicles are: \(s.vehicles.map(\.name).joined(separator: ", "))." }
            return selectVehicle(match)
        case .odometerForActive:
            pending = nil
            guard let reading = Self.number(in: t), reading >= 0, var active = s.data.active else { return "No odometer reading was saved." }
            active.odometerStart = reading; s.data.active = active
            return s.save() ? "Starting odometer saved as \(reading.formatted(.number.grouping(.automatic))) kilometres." : "The odometer was not saved."
        }
    }
    private func vehicle(named t: String) -> Vehicle? {
        store.vehicles.first { t.contains($0.name.lowercased()) || (!$0.registration.isEmpty && t.replacingOccurrences(of: " ", with: "").contains($0.registration.lowercased())) }
    }
    private func selectVehicle(_ v: Vehicle) -> String {
        guard store.selectVehicle(v.id) else { return "The vehicle was not changed." }
        return "Now driving the \(v.displayName)." + (store.data.active != nil ? " The trip that is recording has moved to it." : " Worklog will use it for your next trips.")
    }
}

/// Live speech-to-text for Practice Siri, on the iPhone where supported.
@MainActor final class SpeechListener: ObservableObject {
    @Published var listening = false
    @Published var transcript = ""
    @Published var problem: String?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        problem = nil; transcript = ""
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { problem = "Allow microphone and speech recognition for Worklog in iPhone Settings, or type the command."; return }
        guard let recognizer, recognizer.isAvailable else { problem = "Speech recognition isn't available right now. Type the command instead."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if done { self.finish() }
                }
            }
        } catch { problem = "Couldn't start listening: \(error.localizedDescription)"; finish() }
    }
    /// Stops listening; the caller reads `transcript`.
    func finish() {
        guard listening || engine.isRunning else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel()
        request = nil; task = nil; listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Screens

struct TestCentreView: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @EnvironmentObject var lock: AppLock
    @State private var results: [CheckResult] = []
    @State private var phone: [CheckResult] = []
    @State private var running = false
    @State private var openSiri = false
    var body: some View {
        List {
            Section {
                Button { runChecks() } label: { Label(running ? "Running…" : "Run all app checks", systemImage: "checkmark.seal.fill") }
                    .buttonStyle(PrimaryButtonStyle()).buttonRow().disabled(running)
                if !results.isEmpty {
                    let passed = results.filter(\.passed).count
                    Label("\(passed) of \(results.count) passed", systemImage: passed == results.count ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.headline).foregroundStyle(passed == results.count ? Theme.mint : Theme.danger)
                    ForEach(results) { ResultRow(result: $0) }
                }
            } header: { Text("App checks") } footer: { Text("Function tests run on a temporary practice copy. Your real trips, receipts and hours are never changed.") }
            Section("Phone checks") {
                ForEach(phone) { ResultRow(result: $0, warnOnly: true) }
            }
            Section {
                Button { openSiri = true } label: { Label("Practice Siri", systemImage: "waveform") }
                    .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
            } footer: { Text("Rehearse Worklog's voice commands by speaking or typing. It follows the same steps and replies as Siri. Testing that Siri itself hears the phrase needs the real Siri.") }
        }
        .themedForm()
        .navigationTitle("Test centre")
        .navigationDestination(isPresented: $openSiri) { PracticeSiriView(realStore: store, recorder: recorder) }
        .onAppear {
            phone = AppSelfTest.phoneChecks(recorder: recorder, lock: lock)
            if DemoMode.flag("-WorklogRunChecks"), results.isEmpty { runChecks() }
            if DemoMode.flag("-WorklogOpenPracticeSiri") { openSiri = true }
        }
    }
    func runChecks() {
        running = true
        results = AppSelfTest.run()
        running = false
    }
}

private struct ResultRow: View {
    let result: CheckResult
    var warnOnly = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : (warnOnly ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                .foregroundStyle(result.passed ? Theme.mint : (warnOnly ? Theme.warning : Theme.danger)).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name).font(.headline)
                Text(result.detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }.padding(.vertical, 2)
    }
}

struct PracticeSiriView: View {
    @StateObject private var siri: PracticeSiri
    @StateObject private var listener = SpeechListener()
    @State private var typed = ""
    @State private var speak = true
    let suggestions = ["Start work", "Start my break", "End my break", "Finish work", "Start a trip for supply pickup", "Continue my trip", "Change vehicle", "Set starting odometer"]

    init(realStore: WorkStore, recorder: TripRecorder?) {
        _siri = StateObject(wrappedValue: PracticeSiri(realStore: realStore, recorder: recorder))
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $siri.practice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice mode").font(.headline)
                        Text(siri.practice ? "Uses a copy — your real records don't change" : "Live — commands change your real records").font(.caption)
                            .foregroundStyle(siri.practice ? Theme.mint : Theme.warning)
                    }
                }.tint(Theme.accent)
                Toggle("Speak replies", isOn: $speak).tint(Theme.accent).font(.subheadline)
            }.padding(16).background(Theme.card)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if siri.lines.isEmpty {
                            Text("Tap the microphone and speak, or type a command — say it the way you would to Siri, for example \"Hey Siri, start work in Worklog\".")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary).padding(.vertical, 8)
                        }
                        ForEach(siri.lines) { line in
                            HStack {
                                if line.fromUser { Spacer(minLength: 40) }
                                Text(line.text)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .foregroundStyle(line.fromUser ? Color.black : Theme.textPrimary)
                                    .background(line.fromUser ? AnyShapeStyle(Theme.hero) : AnyShapeStyle(Theme.field), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                if !line.fromUser { Spacer(minLength: 40) }
                            }.id(line.id)
                        }
                    }.padding(16)
                }
                .onChange(of: siri.lines.count) { _, _ in if let last = siri.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { send(s) }.font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                }.padding(.horizontal, 16)
            }.padding(.vertical, 8)

            if let problem = listener.problem { Text(problem).font(.caption).foregroundStyle(Theme.warning).padding(.horizontal, 16) }
            if listener.listening { Text(listener.transcript.isEmpty ? "Listening…" : listener.transcript).font(.subheadline).foregroundStyle(Theme.mint).padding(.horizontal, 16) }

            HStack(spacing: 10) {
                TextField("", text: $typed, prompt: Text("Type a command or answer").foregroundStyle(Theme.textTertiary))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onSubmit { send(typed) }
                Button { send(typed) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                    .foregroundStyle(Theme.accent).disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    if listener.listening {
                        listener.finish(); let said = listener.transcript; send(said)
                    } else { Task { await listener.start() } }
                } label: {
                    Image(systemName: listener.listening ? "stop.fill" : "mic.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black).frame(width: 48, height: 48)
                        .background(listener.listening ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.hero), in: Circle())
                }
            }.padding(16).background(Theme.card)
        }
        .background(Theme.background)
        .navigationTitle("Practice Siri").navigationBarTitleDisplayMode(.inline)
        .onChange(of: speak) { _, value in siri.speakReplies = value }
        .onDisappear { listener.finish() }
        .onAppear {
            if DemoMode.flag("-WorklogPracticeDemo"), siri.lines.isEmpty {
                siri.speakReplies = false
                for said in ["Hey Siri, start a work trip in Worklog", "Supply pickup", "54 340", "Yes", "Hey Siri, start work in Worklog"] { siri.hear(said) }
            }
        }
    }
    func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        siri.hear(clean)
        typed = ""
    }
}
