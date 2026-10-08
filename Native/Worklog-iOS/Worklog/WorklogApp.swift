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
                .tint(Color(red: 0.09, green: 0.24, blue: 0.93))
        }
    }
}

// App Intents run in the main app. UI and Siri share one writer and one GPS recorder.
// Siri actions use authenticationPolicy .requiresAuthentication, so iOS only runs them after the
// iPhone itself is unlocked (Face ID or passcode). They deliberately do not also require
// Worklog's own app lock: that lock still guards the app's screens, which stay locked when Siri opens the app.
@MainActor final class WorklogRuntime {
    static let shared = WorklogRuntime()
    let store = WorkStore()
    let lock = AppLock()
    lazy var recorder = TripRecorder(store: store)
    private init() {}
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

    static var parameterSummary: some ParameterSummary {
        Summary("Start a work trip for \(\.$tripPurpose) at \(\.$startingOdometer) kilometres")
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
        try await requestConfirmation(result: .result(dialog: "Start a work trip for \(purpose), with the odometer at \(reading) kilometres?"))
        guard recorder.startManual(purpose: purpose, startingOdometer: startingOdometer) else {
            return .result(dialog: "Trip not started. \(recorder.status)")
        }
        return .result(dialog: "Started your work trip for \(purpose). Starting odometer \(reading) kilometres saved. Waiting for GPS.")
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
        try await requestConfirmation(result: .result(dialog: "Start \(tripDescription), with starting odometer \(reading) kilometres?"))
        guard recorder.startManual(purpose: tripDescription, startingOdometer: startingOdometer) else {
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
    }
}
