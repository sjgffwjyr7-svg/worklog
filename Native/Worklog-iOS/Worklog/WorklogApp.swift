import SwiftUI
import AppIntents

@main @MainActor struct WorklogApp: App {
    @StateObject private var store: WorkStore
    @StateObject private var recorder: TripRecorder
    init() {
        let runtime = WorklogRuntime.shared
        _store = StateObject(wrappedValue: runtime.store)
        _recorder = StateObject(wrappedValue: runtime.recorder)
        WorklogShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            WorklogGate().environmentObject(store).environmentObject(recorder)
                .environmentObject(WorklogRuntime.shared.lock)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

// App Intents run in the main app. UI and Siri share one writer and one GPS recorder.
// Siri actions use authenticationPolicy .requiresAuthentication, so iOS only runs them after the
// iPhone itself is unlocked (Face ID or passcode). They deliberately do not also require
// Worklog's own app lock: that lock still guards the app's screens, which stay locked when Siri opens the app.
@MainActor final class WorklogRuntime {
    static let shared = WorklogRuntime()
    let store = DemoMode.makeStore()
    let lock = AppLock()
    lazy var recorder = TripRecorder(store: store)
    private init() {}
}

// Screenshot support for CI: debug builds launched with -WorklogDemo use a throwaway store
// filled with sample records. Release builds always use the real store and ignore these flags.
enum DemoMode {
    static func flag(_ name: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(name)
        #else
        return false
        #endif
    }
    static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-WorklogTab"), i + 1 < args.count, let tab = Int(args[i + 1]) { return tab }
        #endif
        return 0
    }
    @MainActor static func makeStore() -> WorkStore {
        guard flag("-WorklogDemo") else { return WorkStore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorklogDemo-\(UUID().uuidString)")
        let store = WorkStore(root: root)
        let now = Date(), hour: TimeInterval = 3600, day: TimeInterval = 86400
        func trip(_ purpose: String, daysAgo: Double, km: Double, review: Bool = false, automatic: Bool = false) -> Trip {
            var t = Trip(purpose: purpose, vehicle: "Hilux · 1ABC234", start: now - daysAgo * day, automatic: automatic, timeZoneID: "Australia/Perth")
            t.end = t.start + hour; t.correctedKm = km; t.correctionReason = "Demo"
            if purpose.hasPrefix("Site") { t.vehicle = "Ranger · 1XYZ987" }
            if review { t.review("GPS gap over 60 seconds; missing distance not estimated") }
            return t
        }
        let hilux = Vehicle(name: "Hilux", registration: "1ABC234", startingOdometer: 54_200)
        let ranger = Vehicle(name: "Ranger", registration: "1XYZ987", startingOdometer: 128_390)
        store.data.vehicles = [hilux, ranger]; store.data.currentVehicleID = hilux.id
        store.data.home = Place(address: "12 Wheelers Lane, Dubbo, NSW, 2830", latitude: -32.2569, longitude: 148.6011)
        store.data.workplace = Place(address: "Farm West depot, Narromine, NSW, 2821", latitude: -32.2333, longitude: 148.2400)
        store.data.trips = [trip("Supply pickup — Bunnings", daysAgo: 0.2, km: 18.4), trip("Site visit — Narromine farm", daysAgo: 1, km: 62.7, automatic: true),
                            trip("Customer visit — Smith & Co", daysAgo: 2, km: 34.1, review: true), trip("Workshop visit", daysAgo: 4, km: 12.9),
                            trip("Training — Dubbo TAFE", daysAgo: 6, km: 8.3)]
        for i in store.data.trips.indices { store.data.trips[i].vehicleID = store.data.trips[i].vehicle.hasPrefix("Ranger") ? ranger.id : hilux.id }
        store.data.trips[0].odometerStart = 54_310; store.data.trips[0].odometerEnd = 54_328
        store.data.lastTripDescription = "Supply pickup — Bunnings"
        store.data.invoices = [Invoice(supplier: "Bunnings Warehouse", number: "8841", date: now - 0.3 * day, total: "21.48", gst: "1.95", notes: "", category: ExpenseCategories.all[2], pdfFilename: "demo-1.pdf"),
                               Invoice(supplier: "Ampol Dubbo", number: "", date: now - 2 * day, total: "88.14", gst: "8.01", notes: "", category: ExpenseCategories.all[0], pdfFilename: "demo-2.pdf"),
                               Invoice(supplier: "Telstra", number: "T-2231", date: now - 9 * day, total: "65.00", gst: "5.91", notes: "", category: ExpenseCategories.all[3], pdfFilename: "demo-3.pdf"),
                               Invoice(supplier: "Repco", number: "R-118", date: now - 200 * day, total: "142.50", gst: "12.95", notes: "", category: ExpenseCategories.all[0], pdfFilename: "demo-4.pdf")]
        store.save()
        return store
    }
}

enum SiriTripPurpose: String, AppEnum {
    case lastUsed, supplyPickup, siteVisit, customerVisit, workshopVisit, training, custom
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Trip description"
    static var caseDisplayRepresentations: [SiriTripPurpose: DisplayRepresentation] = [
        .lastUsed: "Last description", .supplyPickup: "Supply pickup", .siteVisit: "Site visit",
        .customerVisit: "Customer visit", .workshopVisit: "Workshop visit", .training: "Training", .custom: "Custom"
    ]
    var text: String {
        switch self {
        case .lastUsed, .custom: return ""
        case .supplyPickup: return "Supply pickup"
        case .siteVisit: return "Site visit"
        case .customerVisit: return "Customer visit"
        case .workshopVisit: return "Workshop visit"
        case .training: return "Training"
        }
    }
}

struct VehicleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Vehicle"
    static var defaultQuery = VehicleQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ vehicle: Vehicle) { id = vehicle.id; name = vehicle.displayName }
}

struct VehicleQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [VehicleEntity] {
        await MainActor.run { WorklogRuntime.shared.store.vehicles.filter { identifiers.contains($0.id) }.map(VehicleEntity.init) }
    }
    func entities(matching string: String) async throws -> [VehicleEntity] {
        await MainActor.run {
            WorklogRuntime.shared.store.vehicles.filter { $0.name.localizedCaseInsensitiveContains(string) || $0.registration.localizedCaseInsensitiveContains(string) || string.localizedCaseInsensitiveContains($0.name) }.map(VehicleEntity.init)
        }
    }
    func suggestedEntities() async throws -> [VehicleEntity] {
        await MainActor.run { WorklogRuntime.shared.store.vehicles.map(VehicleEntity.init) }
    }
}

@MainActor enum SiriVehiclePlan {
    /// Chooses the vehicle for a Siri trip. When the spoken odometer matches another vehicle better and the
    /// driver did not name a vehicle, the trip moves to that vehicle and Siri says so in the confirmation.
    static func plan(reading: Double, requested: UUID?) -> (vehicleID: UUID?, name: String, note: String) {
        let store = WorklogRuntime.shared.store
        let chosen = requested ?? store.currentVehicle?.id
        let name = store.vehicle(chosen)?.displayName ?? ""
        guard let check = store.odometerCheck(reading: reading, vehicleID: chosen) else { return (chosen, name, "") }
        if requested == nil, let suggested = check.suggested {
            return (suggested.id, suggested.displayName, "That reading is close to the \(suggested.displayName)'s last odometer, so I'll record this trip in the \(suggested.displayName). ")
        }
        return (chosen, name, check.message + " ")
    }
}

struct SelectVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Change vehicle"
    static var description = IntentDescription("Choose the vehicle you are driving. Worklog remembers it for the next trips, and a trip already recording moves to it.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Vehicle", requestValueDialog: "Which vehicle are you driving?")
    var vehicle: VehicleEntity

    static var parameterSummary: some ParameterSummary { Summary("Drive the \(\.$vehicle)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = WorklogRuntime.shared.store
        _ = WorklogRuntime.shared.recorder // Apply any cold-launch interrupted-trip recovery first.
        guard store.selectVehicle(vehicle.id) else { return .result(dialog: "The vehicle was not changed. Open Worklog to check your vehicles.") }
        if store.data.active != nil { return .result(dialog: "Now driving the \(vehicle.name). The trip that is recording has moved to it.") }
        return .result(dialog: "Now driving the \(vehicle.name). Worklog will use it for your next trips.")
    }
}

// Free-form Siri entry. Keep the preset intent below for existing shortcuts.
struct DictateWorkTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start work trip by voice"
    static var description = IntentDescription("Tell Siri the purpose of your work trip and the vehicle's current odometer in kilometres. Confirm both to start GPS recording.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Trip purpose", requestValueDialog: "What is the purpose of this work trip?")
    var tripPurpose: String

    @Parameter(title: "Current vehicle kilometres", requestValueDialog: "What is the vehicle's current odometer reading in kilometres?")
    var startingOdometer: Double

    @Parameter(title: "Vehicle")
    var vehicle: VehicleEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a work trip for \(\.$tripPurpose) at \(\.$startingOdometer) kilometres") { \.$vehicle }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let purpose = tripPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !purpose.isEmpty else { throw $tripPurpose.needsValueError("What is the purpose of this work trip?") }
        guard purpose.count <= 200 else { throw $tripPurpose.needsValueError("Give a shorter trip purpose, up to 200 characters.") }
        guard startingOdometer.isFinite && startingOdometer >= 0 else {
            throw $startingOdometer.needsValueError("Give the vehicle's current odometer reading as a non-negative number of kilometres.")
        }
        let runtime = WorklogRuntime.shared
        let recorder = runtime.recorder
        guard !runtime.store.loadFailed else { return .result(dialog: "Worklog cannot open its saved records. Open the app to resolve the storage error.") }
        guard runtime.store.data.active == nil else { return .result(dialog: "A trip is already recording. Finish it before starting another.") }
        let reading = startingOdometer.formatted(.number.grouping(.automatic))
        let plan = SiriVehiclePlan.plan(reading: startingOdometer, requested: vehicle?.id)
        let inVehicle = plan.name.isEmpty ? "" : " in the \(plan.name)"
        try await requestConfirmation(result: .result(dialog: "\(plan.note)Start a work trip for \(purpose)\(inVehicle), with the odometer at \(reading) kilometres?"))
        guard recorder.startManual(purpose: purpose, startingOdometer: startingOdometer, vehicleID: plan.vehicleID) else {
            return .result(dialog: "Trip not started. \(recorder.status)")
        }
        return .result(dialog: "Started your work trip for \(purpose)\(inVehicle). Starting odometer \(reading) kilometres saved. Waiting for GPS.")
    }
}

struct StartWorkTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start work trip"
    static var description = IntentDescription("Start a work trip with a description and starting odometer in kilometres. Opens Worklog to begin GPS recording.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Trip description", default: .lastUsed)
    var purpose: SiriTripPurpose

    @Parameter(title: "Starting odometer (km)", requestValueDialog: "What is the starting odometer reading in kilometres?")
    var startingOdometer: Double

    @Parameter(title: "Custom description", default: "", requestValueDialog: "What is the trip description?")
    var customDescription: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$purpose) at odometer \(\.$startingOdometer) km") { \.$customDescription }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard startingOdometer.isFinite && startingOdometer >= 0 else {
            throw $startingOdometer.needsValueError("Give a non-negative odometer reading in kilometres.")
        }
        let runtime = WorklogRuntime.shared
        let recorder = runtime.recorder
        guard !runtime.store.loadFailed else { return .result(dialog: "Worklog cannot open its saved records. Open the app to resolve the storage error.") }
        guard runtime.store.data.active == nil else { return .result(dialog: "A trip is already recording. Finish it before starting another.") }
        var tripDescription = purpose.text
        if purpose == .lastUsed { tripDescription = runtime.store.lastTripDescription }
        if purpose == .custom || tripDescription.isEmpty { tripDescription = customDescription.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tripDescription.isEmpty else { throw $customDescription.needsValueError("What is the description for this trip?") }
        let reading = String(startingOdometer)
        let plan = SiriVehiclePlan.plan(reading: startingOdometer, requested: nil)
        let inVehicle = plan.name.isEmpty ? "" : " in the \(plan.name)"
        try await requestConfirmation(result: .result(dialog: "\(plan.note)Start \(tripDescription)\(inVehicle), with starting odometer \(reading) kilometres?"))
        guard recorder.startManual(purpose: tripDescription, startingOdometer: startingOdometer, vehicleID: plan.vehicleID) else {
            return .result(dialog: "Trip not started. \(recorder.status)")
        }
        return .result(dialog: "Started \(tripDescription). Starting odometer \(reading) kilometres saved. Waiting for GPS.")
    }
}

struct SetStartingOdometerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set starting odometer"
    static var description = IntentDescription("Set or correct the starting odometer on the current trip. Confirms the number before saving.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Starting odometer (km)", requestValueDialog: "What is the starting odometer reading in kilometres?")
    var startingOdometer: Double

    static var parameterSummary: some ParameterSummary { Summary("Set starting odometer to \(\.$startingOdometer) km") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard startingOdometer.isFinite && startingOdometer >= 0 else { throw $startingOdometer.needsValueError("Give a non-negative odometer reading in kilometres.") }
        let runtime = WorklogRuntime.shared
        _ = runtime.recorder // Apply any cold-launch interrupted-trip recovery before choosing a trip.
        guard let target = runtime.store.data.active else { return .result(dialog: "There is no active trip. Start a trip first.") }
        let reading = String(startingOdometer)
        try await requestConfirmation(result: .result(dialog: "Set the starting odometer for \(target.purpose) to \(reading) kilometres?"))
        guard var current = runtime.store.data.active, current.id == target.id else { return .result(dialog: "The active trip changed. No odometer reading was updated.") }
        let previous = current
        current.odometerStart = startingOdometer
        runtime.store.data.active = current
        guard runtime.store.save() else {
            runtime.store.data.active = previous
            return .result(dialog: "The odometer was not saved. Check storage in Worklog and try again.")
        }
        return .result(dialog: "Starting odometer saved as \(reading) kilometres.")
    }
}

struct ContinueTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue last trip"
    static var description = IntentDescription("Continue your most recent trip after a stop, such as driving back to the workshop after picking up parts. GPS recording resumes on the same trip.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = WorklogRuntime.shared
        let recorder = runtime.recorder // Also applies any cold-launch interrupted-trip recovery first.
        guard !runtime.store.loadFailed else { return .result(dialog: "Worklog cannot open its saved records. Open the app to resolve the storage error.") }
        guard runtime.store.data.active == nil else { return .result(dialog: "A trip is already recording.") }
        guard let trip = runtime.store.continuableTrip(), let end = trip.end else {
            return .result(dialog: "There's no trip from the last 12 hours to continue. Say start a work trip in Worklog instead.")
        }
        let minutes = max(1, Int(Date().timeIntervalSince(end) / 60))
        let ago = minutes >= 60 ? "\(minutes / 60) hours and \(minutes % 60) minutes" : "\(minutes) minutes"
        try await requestConfirmation(result: .result(dialog: "Continue your trip for \(trip.purpose), which stopped \(ago) ago?"))
        guard recorder.continueLastTrip() else { return .result(dialog: "Trip not continued. \(recorder.status)") }
        return .result(dialog: "Continuing \(trip.purpose). The stop has been noted and GPS recording has resumed.")
    }
}

struct WorklogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DictateWorkTripIntent(), phrases: [
            "Start a work trip in \(.applicationName)",
            "Start a trip in \(.applicationName)",
            "Record a work trip in \(.applicationName)"
        ], shortTitle: "Start trip by voice", systemImageName: "mic")
        AppShortcut(intent: StartWorkTripIntent(), phrases: [
            "Start a trip with my last description in \(.applicationName)",
            "Start a \(\.$purpose) trip in \(.applicationName)",
            "Start a trip to \(\.$purpose) in \(.applicationName)"
        ], shortTitle: "Start work trip", systemImageName: "car.side")
        AppShortcut(intent: SetStartingOdometerIntent(), phrases: [
            "Set starting odometer in \(.applicationName)",
            "Set my starting kilometres in \(.applicationName)"
        ], shortTitle: "Starting odometer", systemImageName: "gauge")
        AppShortcut(intent: ContinueTripIntent(), phrases: [
            "Continue my trip in \(.applicationName)",
            "Continue last trip in \(.applicationName)",
            "Resume my trip in \(.applicationName)",
            "Head back in \(.applicationName)"
        ], shortTitle: "Continue last trip", systemImageName: "arrow.uturn.backward")
        AppShortcut(intent: SelectVehicleIntent(), phrases: [
            "Change vehicle in \(.applicationName)",
            "Switch vehicle in \(.applicationName)",
            "I'm driving the \(\.$vehicle) in \(.applicationName)",
            "Switch to the \(\.$vehicle) in \(.applicationName)"
        ], shortTitle: "Change vehicle", systemImageName: "car.2")
    }
}
