import Foundation
import CoreLocation

struct WorkSchedule: Codable, Equatable {
    var enabled = false
    var weekdays: Set<Int> = [2, 3, 4, 5, 6] // Calendar: Sunday = 1
    var startMinute = 7 * 60
    var endMinute = 17 * 60
    var timeZoneID = "Australia/Perth"
    var vehicle = ""
    var purpose = "Scheduled work driving"
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return value
    }
    func window(at date: Date) -> DateInterval? {
        guard startMinute != endMinute, !weekdays.isEmpty else { return nil }
        let cal = calendar, today = cal.startOfDay(for: date)
        for shiftDay in [today, cal.date(byAdding: .day, value: -1, to: today)!] {
            guard weekdays.contains(cal.component(.weekday, from: shiftDay)) else { continue }
            let finishDay = endMinute < startMinute ? cal.date(byAdding: .day, value: 1, to: shiftDay)! : shiftDay
            guard let start = cal.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: shiftDay),
                  let end = cal.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: finishDay) else { continue }
            if date >= start && date < end { return DateInterval(start: start, end: end) }
        }
        return nil
    }
}

struct GPSPoint: Codable {
    var date: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var speed: Double
    var segmentMetres: Double = 0
    var segmentStart: Date? = nil
    init(_ location: CLLocation) {
        date = location.timestamp; latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude; accuracy = location.horizontalAccuracy
        speed = location.speed
    }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var purpose: String
    var vehicle: String
    var start: Date
    var end: Date? = nil
    var automatic: Bool
    var scheduleEnd: Date? = nil
    var timeZoneID: String
    var points: [GPSPoint] = []
    var reviewReasons: [String] = []
    var odometerStart: Double? = nil
    var odometerEnd: Double? = nil
    var excluded: Bool? = nil
    var correctedKm: Double? = nil
    var correctionReason = ""
    var correctedAt: Date? = nil
    var vehicleID: UUID? = nil
    /// Set once the driver has answered the home/work check for this trip.
    var placeReviewed: Bool? = nil
    var metres: Double { points.reduce(0) { $0 + $1.segmentMetres } }
    var km: Double { correctedKm ?? metres / 1000 }
    mutating func review(_ reason: String) { if !reviewReasons.contains(reason) { reviewReasons.append(reason) } }
    func km(in interval: DateInterval) -> Double {
        if excluded == true { return 0 }
        let finish = end ?? points.last?.date ?? start
        guard finish > interval.start && start < interval.end else { return 0 }
        if start >= interval.start && finish <= interval.end { return km }
        if let correction = correctedKm {
            let overlap = max(0, min(finish, interval.end).timeIntervalSince(max(start, interval.start)))
            return correction * overlap / max(1, finish.timeIntervalSince(start))
        }
        return points.reduce(0) { total, p in
            guard let previous = p.segmentStart, p.date > previous else { return total }
            let overlap = max(0, min(p.date, interval.end).timeIntervalSince(max(previous, interval.start)))
            return total + p.segmentMetres / 1000 * overlap / p.date.timeIntervalSince(previous)
        }
    }
}

struct Invoice: Codable, Identifiable {
    var id = UUID()
    var supplier: String
    var number: String
    var date: Date
    var total: String
    var gst: String
    var notes: String
    var captured = Date()
    var category: String? = nil
    var customCategory: String? = nil
    var abn: String? = nil
    var workPercent: String? = nil
    var reimbursed: String? = nil
    var taxStatus: String? = nil
    var items: String? = nil
    var recognizedText: String? = nil
    var receiptReviewed: Bool? = nil
    var pdfFilename: String
}
struct Vehicle: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var registration = ""
    /// Odometer when the vehicle was added; later readings come from its trips.
    var startingOdometer: Double? = nil
    var displayName: String { registration.isEmpty ? name : "\(name) · \(registration)" }
}

/// A saved home or work location used to spot commuting and breaks at home.
struct Place: Codable, Equatable {
    var address: String
    var latitude: Double
    var longitude: Double
    var radius: Double = 250
    func contains(_ point: GPSPoint) -> Bool {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: point.location) <= radius + min(point.accuracy, 100)
    }
}

struct PlaceAssessment: Equatable {
    enum Kind { case commute, homeBreak }
    var kind: Kind
    var short: String
    var message: String
}

/// Result of comparing an entered odometer with each vehicle's last known reading.
struct OdometerCheck {
    var selected: Vehicle?
    var selectedLast: Double?
    var suggested: Vehicle?
    var suggestedLast: Double?
    var message: String
}

struct WorkData: Codable {
    var home: Place? = nil
    var workplace: Place? = nil
    var vehicles: [Vehicle]? = nil
    var currentVehicleID: UUID? = nil
    var lastTripDescription: String? = nil
    var recentTripDescriptions: [String]? = nil
    var schemaVersion = 1
    var schedule = WorkSchedule()
    var trips: [Trip] = []
    var invoices: [Invoice] = []
    var active: Trip? = nil
}
struct Backup: Codable {
    var format = "worklog-ios-backup"
    var version = 1
    var data: WorkData
    var documents: [String: Data]
}
enum FinancialYear {
    static func startYear(for date: Date = Date(), timeZone: String = "Australia/Perth") -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: timeZone) ?? .current
        return cal.component(.year, from: date) - (cal.component(.month, from: date) < 7 ? 1 : 0)
    }
    static func interval(_ startYear: Int, timeZone: String = "Australia/Perth") -> DateInterval {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: timeZone) ?? .current
        return DateInterval(start: cal.date(from: DateComponents(year: startYear, month: 7, day: 1))!, end: cal.date(from: DateComponents(year: startYear + 1, month: 7, day: 1))!)
    }
}

/// Monday-to-Sunday weeks for the trip log, in the schedule's time zone.
enum TripCalendar {
    static func calendar(_ timeZoneID: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }
    static func weekStart(of date: Date, timeZoneID: String) -> Date {
        let cal = calendar(timeZoneID)
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
    /// Week starts (Mondays) that contain at least one trip, newest first.
    static func weeks(_ trips: [Trip], timeZoneID: String) -> [Date] {
        Array(Set(trips.map { weekStart(of: $0.start, timeZoneID: timeZoneID) })).sorted(by: >)
    }
    /// The seven days (Monday first) of the week starting at `weekStart`.
    static func days(inWeek weekStart: Date, timeZoneID: String) -> [Date] {
        let cal = calendar(timeZoneID)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
    static func trips(_ trips: [Trip], onDay day: Date, timeZoneID: String) -> [Trip] {
        let cal = calendar(timeZoneID)
        return trips.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }
    static func trips(_ trips: [Trip], inWeek weekStart: Date, timeZoneID: String) -> [Trip] {
        trips.filter { self.weekStart(of: $0.start, timeZoneID: timeZoneID) == weekStart }
    }
    /// Work kilometres, leaving out trips marked private.
    static func workKm(_ trips: [Trip]) -> Double { trips.filter { $0.excluded != true }.reduce(0) { $0 + $1.km } }
}

enum ExpenseCategories {
    static let all = ["Vehicle — fuel, servicing & running costs", "Work travel & accommodation", "Tools & equipment", "Phone & internet", "Home office", "Protective clothing, uniforms & laundry", "Training & self-education", "Professional fees, unions & subscriptions", "Business operating expenses", "Insurance", "Investment expenses", "Rental property expenses", "Donations & gifts", "Tax-agent & tax-affairs costs", "Other / custom category"]
}
