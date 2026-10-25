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
        // Rounded to useful precision (about 10 cm, 0.1 m, 0.1 s) so records stay small and compress well.
        date = Date(timeIntervalSinceReferenceDate: (location.timestamp.timeIntervalSinceReferenceDate * 10).rounded() / 10)
        latitude = (location.coordinate.latitude * 1e6).rounded() / 1e6
        longitude = (location.coordinate.longitude * 1e6).rounded() / 1e6
        accuracy = (location.horizontalAccuracy * 10).rounded() / 10
        speed = (location.speed * 10).rounded() / 10
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
    /// Stops where a finished trip was later continued (e.g. picking up parts before driving back).
    var pauses: [DateInterval]? = nil
    /// Set once the driver has answered the home/work check for this trip.
    var placeReviewed: Bool? = nil
    var metres: Double { points.reduce(0) { $0 + $1.segmentMetres } }
    var km: Double { correctedKm ?? metres / 1000 }
    /// Adds a GPS point. While parked, the latest stationary point is updated instead of adding
    /// another one, so long stops don't fill storage; distance only comes from moving points.
    mutating func addPoint(_ point: GPSPoint) {
        if point.segmentMetres == 0, points.count >= 2, let last = points.last, last.segmentMetres == 0 {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
    }
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
    // ATO logbook details.
    var make: String? = nil
    var model: String? = nil
    var engineCapacity: String? = nil
    /// The 12-week (or longer) logbook period and its odometer readings.
    var logbookStart: Date? = nil
    var logbookStartOdometer: Double? = nil
    var logbookEnd: Date? = nil
    var logbookEndOdometer: Double? = nil
    /// Odometer at the start (1 July) and end (30 June) of each financial year, keyed by the year it starts.
    var yearOdometers: [String: YearOdometer]? = nil
    var displayName: String { registration.isEmpty ? name : "\(name) · \(registration)" }
    var makeModel: String { [make, model].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ") }
}

struct YearOdometer: Codable, Hashable {
    var start: Double? = nil
    var end: Double? = nil
}

/// One vehicle's ATO logbook figures for a financial year.
struct LogbookSummary {
    var vehicle: Vehicle
    var logbookWeeks: Double?
    var logbookTotalKm: Double?
    var logbookBusinessKm: Double
    var businessPercent: Double?
    var yearStartOdometer: Double?
    var yearEndOdometer: Double?
    var yearTotalKm: Double?
    var yearWorkKm: Double
    var issues: [String]
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

/// Where a shift was worked. "Working from home" hours are totalled for the ATO's fixed-rate method.
enum ShiftPlace: String, Codable, CaseIterable {
    case workplace = "Workplace", home = "Working from home", road = "On the road", other = "Other"
}

/// One period of work: clocked on, optional breaks, clocked off.
struct WorkShift: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date? = nil
    var breaks: [DateInterval] = []
    /// Set while on a break that hasn't ended yet.
    var breakStart: Date? = nil
    var place: ShiftPlace = .workplace
    var notes = ""
    var timeZoneID: String
    var manual = false
    func breakSeconds(at now: Date = Date()) -> TimeInterval {
        breaks.reduce(0) { $0 + $1.duration } + (breakStart.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
    /// Time worked, with breaks taken out.
    func workedSeconds(at now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start) - breakSeconds(at: now))
    }
    var hours: Double { workedSeconds() / 3600 }
}

/// "7 h 30 m" for screens; decimal hours for spreadsheets.
func hoursText(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m" : "\(minutes) m"
}

struct WorkData: Codable {
    var shifts: [WorkShift]? = nil
    var activeShift: WorkShift? = nil
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
    /// Australian financial years (by starting year) that contain trips, newest first.
    static func financialYears(_ trips: [Trip], timeZoneID: String) -> [Int] {
        Array(Set(trips.map { FinancialYear.startYear(for: $0.start, timeZone: timeZoneID) })).sorted(by: >)
    }
    static func monthStart(of date: Date, timeZoneID: String) -> Date {
        let cal = calendar(timeZoneID)
        return cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date)
    }
    static func monthInterval(of month: Date, timeZoneID: String) -> DateInterval {
        calendar(timeZoneID).dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
    }
    /// Month starts that contain trips, newest first.
    static func months(_ trips: [Trip], timeZoneID: String) -> [Date] {
        Array(Set(trips.map { monthStart(of: $0.start, timeZoneID: timeZoneID) })).sorted(by: >)
    }
    static func trips(_ trips: [Trip], within span: DateInterval) -> [Trip] {
        trips.filter { $0.start >= span.start && $0.start < span.end }
    }
    /// Monday week starts for any dates (used by receipts), newest first.
    static func weekStarts(_ dates: [Date], timeZoneID: String) -> [Date] {
        Array(Set(dates.map { weekStart(of: $0, timeZoneID: timeZoneID) })).sorted(by: >)
    }
    /// Month starts for any dates (used by receipts), newest first.
    static func monthStarts(_ dates: [Date], timeZoneID: String) -> [Date] {
        Array(Set(dates.map { monthStart(of: $0, timeZoneID: timeZoneID) })).sorted(by: >)
    }
    /// Work kilometres, leaving out trips marked private.
    static func workKm(_ trips: [Trip]) -> Double { trips.filter { $0.excluded != true }.reduce(0) { $0 + $1.km } }
}

enum ExpenseCategories {
    static let all = ["Vehicle — fuel, servicing & running costs", "Work travel & accommodation", "Tools & equipment", "Phone & internet", "Home office", "Protective clothing, uniforms & laundry", "Training & self-education", "Professional fees, unions & subscriptions", "Business operating expenses", "Insurance", "Investment expenses", "Rental property expenses", "Donations & gifts", "Tax-agent & tax-affairs costs", "Other / custom category"]
}
