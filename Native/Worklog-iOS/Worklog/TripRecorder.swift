import Foundation
import CoreLocation
import Combine

@MainActor final class TripRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    let store: WorkStore
    private let location = CLLocationManager()
    @Published var status = "Ready to record"
    @Published var authorization = CLAuthorizationStatus.notDetermined
    @Published var running = false
    private var candidate: CLLocation?
    private var anchor: GPSPoint?
    private var lastMovement: Date?
    private var cooldownUntil = Date.distantPast
    private var timer: Timer?
    private var armed = false
    /// A scheduled trip finishes after this long without movement, so short stops (parts pickup,
    /// fuel, a quick site check) stay part of one trip.
    static let stopFinishSeconds: TimeInterval = 15 * 60
    /// True between continuing a trip and its first new GPS fix, so the stop isn't flagged as a GPS gap.
    private var resuming = false
    init(store: WorkStore) {
        self.store = store
        super.init()
        location.delegate = self
        location.activityType = .automotiveNavigation
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 10
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
        authorization = location.authorizationStatus
        if var trip = store.data.active {
            trip.review("Recording interrupted by app restart. Review distance and end time.")
            trip.end = trip.points.last?.date ?? trip.start
            store.data.active = nil; store.data.trips.insert(trip, at: 0)
            if !store.save() { store.data.trips.removeFirst(); store.data.active = trip }
        }
        // Creating this object on app launch restores previously enabled monitoring.
        if store.data.schedule.enabled { armed = true; configure() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkScheduleEnd() }
        }
    }
    func requestPermission() { location.requestWhenInUseAuthorization() }
    /// Most recent fix iOS has for this app, if any; used to set home/work from where you are.
    var lastKnownLocation: CLLocation? { location.location }
    func requestAlways() {
        if authorization == .notDetermined { location.requestWhenInUseAuthorization() }
        else { location.requestAlwaysAuthorization() }
    }
    func applySchedule(_ schedule: WorkSchedule) {
        if store.data.active?.automatic == true { finish(at: Date(), reason: "Schedule changed during trip") }
        guard store.data.active == nil || store.data.active?.automatic == false else { return }
        let old = store.data.schedule
        store.data.schedule = schedule
        if !store.save() { store.data.schedule = old; return }
        candidate = nil; armed = schedule.enabled
        if schedule.enabled { requestAlways() }
        configure()
    }
    func configure() {
        guard !store.loadFailed else { status = "Saving is unavailable"; return }
        let wantsLocation = armed || store.data.active != nil
        guard wantsLocation else {
            location.stopUpdatingLocation(); location.stopMonitoringSignificantLocationChanges()
            location.allowsBackgroundLocationUpdates = false; running = false
            status = "Scheduled recording off"; return
        }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            running = false; status = "Allow location to record trips"; return
        }
        location.allowsBackgroundLocationUpdates = true
        location.startUpdatingLocation()
        if armed && authorization == .authorizedAlways { location.startMonitoringSignificantLocationChanges() }
        running = true
        status = authorization == .authorizedAlways ? "Monitoring work schedule" : "Open Settings and allow Always location for scheduled recording"
    }
    @discardableResult func startManual(purpose: String, startingOdometer: Double? = nil, vehicleID: UUID? = nil) -> Bool {
        let description = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.data.active == nil else { status = "A trip is already recording. Finish it first."; return false }
        guard !description.isEmpty else { status = "Enter a trip description."; return false }
        if let reading = startingOdometer, !reading.isFinite || reading < 0 { status = "Enter a valid starting odometer in kilometres."; return false }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { requestPermission(); status = "Allow location, then start the trip again"; return false }
        guard store.rememberTripDescription(description) else { status = "Trip was not started because local saving failed."; return false }
        let vehicle = store.vehicle(vehicleID) ?? store.currentVehicle
        var trip = Trip(purpose: description, vehicle: vehicle?.displayName ?? store.data.schedule.vehicle, start: Date(), automatic: false, timeZoneID: store.data.schedule.timeZoneID)
        trip.odometerStart = startingOdometer
        trip.vehicleID = vehicle?.id
        let previousVehicle = store.data.currentVehicleID
        store.data.active = trip
        // The vehicle used for this trip becomes the remembered current vehicle.
        if let vehicle { store.data.currentVehicleID = vehicle.id }
        guard store.save() else { store.data.active = nil; store.data.currentVehicleID = previousVehicle; status = "Trip was not saved. Check device storage and try again."; return false }
        anchor = nil; lastMovement = nil; configure(); status = "Finding GPS…"
        return true
    }
    /// Continues the most recent trip after a stop (e.g. drive to the supplier, pick up parts, drive back).
    @discardableResult func continueLastTrip() -> Bool {
        guard store.data.active == nil else { status = "A trip is already recording."; return false }
        guard let trip = store.continuableTrip() else { status = "No trip from the last 12 hours to continue. Start a new trip."; return false }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { requestPermission(); status = "Allow location, then continue the trip again"; return false }
        guard store.reopenTrip(trip.id) else { status = "Trip was not continued because local saving failed."; return false }
        anchor = nil; lastMovement = nil; candidate = nil; resuming = true
        configure(); status = "Continuing \(trip.purpose) · finding GPS…"
        return true
    }
    func finish(at date: Date = Date(), reason: String? = nil, cooldown: Bool = false) {
        guard var trip = store.data.active else { return }
        trip.end = max(trip.start, date)
        if trip.points.isEmpty { trip.review("No usable GPS positions; distance needs review") }
        if let last = trip.points.last, date.timeIntervalSince(last.date) > 60 { trip.review("GPS missing near trip end") }
        if let reason { trip.review(reason) }
        trip.points.removeAll { $0.date > (trip.end ?? date) }
        let original = store.data.active
        store.data.active = nil; store.data.trips.insert(trip, at: 0)
        guard store.save() else { store.data.trips.removeFirst(); store.data.active = original; status = "Trip not saved — retry Finish"; return }
        anchor = nil; candidate = nil; lastMovement = nil
        if cooldown { cooldownUntil = date.addingTimeInterval(180) }
        configure(); status = "Trip saved · \(String(format: "%.2f", trip.km)) km"
    }
    private func checkScheduleEnd() {
        guard let trip = store.data.active, trip.automatic else { return }
        if let end = trip.scheduleEnd, Date() >= end { finish(at: end); return }
        if let moved = lastMovement, Date().timeIntervalSince(moved) >= Self.stopFinishSeconds { finish(at: moved) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .denied || authorization == .restricted {
            if store.data.active != nil { finish(at: Date(), reason: "Location permission removed") }
            manager.stopUpdatingLocation(); running = false; status = "Location disabled. Enable it in Settings."
        } else { configure() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS unavailable: \(error.localizedDescription)"
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for fix in locations.sorted(by: { $0.timestamp < $1.timestamp }) { process(fix) }
    }
    private func process(_ fix: CLLocation) {
        // Finish an earlier drive before treating movement after a long stop as a new trip.
        if let trip = store.data.active, trip.automatic, let moved = lastMovement,
           fix.timestamp.timeIntervalSince(moved) >= Self.stopFinishSeconds {
            finish(at: moved)
        }
        // Process schedule boundaries even if accuracy is poor.
        if let active = store.data.active, active.automatic, let end = active.scheduleEnd, fix.timestamp >= end { finish(at: end) }
        guard fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 50,
              abs(fix.timestamp.timeIntervalSinceNow) <= 45 else { status = "Waiting for accurate GPS"; return }
        if store.data.active == nil {
            guard armed, authorization == .authorizedAlways, fix.timestamp >= cooldownUntil,
                  let window = store.data.schedule.window(at: fix.timestamp) else {
                candidate = nil
                status = armed ? "Waiting for scheduled work driving" : "Ready to record"
                return
            }
            // Two moving fixes reduce accidental walking/stationary starts. This is a driving heuristic,
            // not proof of the travel mode or driver identity. The user reviews the saved log.
            guard fix.speed >= 2.5 else { candidate = nil; return }
            guard let first = candidate, fix.timestamp > first.timestamp,
                  fix.timestamp.timeIntervalSince(first.timestamp) <= 30,
                  first.timestamp >= window.start,
                  fix.distance(from: first) >= 8 else { candidate = fix; return }
            let vehicle = store.currentVehicle
            var trip = Trip(purpose: store.data.schedule.purpose, vehicle: vehicle?.displayName ?? store.data.schedule.vehicle, start: first.timestamp, automatic: true, scheduleEnd: window.end, timeZoneID: store.data.schedule.timeZoneID)
            trip.vehicleID = vehicle?.id
            trip.points = [GPSPoint(first)]
            store.data.active = trip; anchor = trip.points.first; lastMovement = first.timestamp
            if !store.save() { store.data.active = nil; anchor = nil; return }
        }
        guard var trip = store.data.active else { return }
        var point = GPSPoint(fix)
        if let last = trip.points.last {
            guard point.date > last.date else { return }
            if point.date.timeIntervalSince(last.date) > 60 {
                // The first fix after continuing a trip follows a deliberate stop, not lost GPS.
                if !resuming { trip.review("GPS gap over 60 seconds; missing distance not estimated") }
                anchor = nil
            }
        }
        if let previous = anchor {
            let dt = point.date.timeIntervalSince(previous.date), metres = point.location.distance(from: previous.location)
            guard dt > 0 else { return }
            if metres / dt > 55 { trip.review("Implausible GPS jump ignored"); store.data.active = trip; store.save(); return }
            let threshold = max(8, min(20, (point.accuracy + previous.accuracy) / 4))
            if metres >= threshold {
                point.segmentMetres = metres; point.segmentStart = previous.date
                anchor = point; lastMovement = point.date
            }
        } else { anchor = point; lastMovement = point.date }
        resuming = false
        trip.points.append(point)
        store.data.active = trip
        store.save()
        status = "Recording · accuracy ±\(Int(point.accuracy)) m"
        if trip.automatic, let movement = lastMovement, point.date.timeIntervalSince(movement) >= Self.stopFinishSeconds { finish(at: movement) }
    }
}
