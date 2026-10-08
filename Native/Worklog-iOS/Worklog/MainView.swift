import SwiftUI
import CoreLocation
import VisionKit
import UniformTypeIdentifiers

private let ink = Color(red: 0.09, green: 0.13, blue: 0.22)
private let blue = Color(red: 0.09, green: 0.24, blue: 0.93)
private let surface = Color(red: 0.96, green: 0.97, blue: 0.99)

struct MainView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Trips", systemImage: "car.side") }
            InvoicesView().tabItem { Label("Invoices", systemImage: "doc.text.viewfinder") }
            ScheduleView().tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }
            StorageView().tabItem { Label("Storage", systemImage: "externaldrive") }
        }
    }
}
struct DashboardView: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @State private var year = FinancialYear.startYear()
    @State private var starting = false
    @State private var startingOdometer = ""
    @State private var purpose = ""
    @State private var share: ShareFiles?
    var interval: DateInterval { FinancialYear.interval(year, timeZone: store.data.schedule.timeZoneID) }
    var trips: [Trip] { store.data.trips.filter { ($0.end ?? $0.start) > interval.start && $0.start < interval.end }.sorted { $0.start > $1.start } }
    var years: [Int] { Array(Set([year, FinancialYear.startYear(), FinancialYear.startYear()-1] + store.data.trips.map { FinancialYear.startYear(for: $0.start) } + store.data.invoices.map { FinancialYear.startYear(for: $0.date) })).sorted(by: >) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YOUR WORK KILOMETRES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("1 July \(String(year)) – 30 June \(String(year+1))").font(.subheadline)
                        }
                        Spacer()
                        Picker("Financial year", selection: $year) { ForEach(years, id: \.self) { y in Text("FY \(String(y))–\(String(y+1).suffix(2))").tag(y) } }.pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Financial year total").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(trips.reduce(0) { $0 + $1.km(in: interval) }, format: .number.precision(.fractionLength(1))).font(.system(size: 50, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5)
                            Text("work km").foregroundStyle(.secondary)
                        }
                        HStack { Label("\(trips.count) trips", systemImage: "car.side"); Spacer(); Text("Saved on iPhone") }.font(.caption).foregroundStyle(.secondary)
                    }.padding(23).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    recorderCard
                    if recorder.authorization != .authorizedAlways && store.data.schedule.enabled {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Always location needed").font(.headline)
                            Text("Scheduled recording needs Always and Precise Location. Keep the app enabled and reopen after a restart or force-close.").font(.subheadline)
                            Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        }.padding().background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    }
                    HStack { Text("Trip log").font(.headline); Spacer(); Button { do { share = ShareFiles(urls: try store.accountantExport(year: year)) } catch { store.error = error.localizedDescription } } label: { Label("Accountant", systemImage: "square.and.arrow.up").font(.subheadline) } }
                    if trips.isEmpty {
                        ContentUnavailableView("Your first work trip starts here", systemImage: "car.side", description: Text("Start a work trip or enable your work schedule. Saved trips include kilometres, dates and start/finish times."))
                    } else {
                        ForEach(trips) { trip in
                            NavigationLink { TripDetailView(tripID: trip.id) } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(trip.purpose).font(.headline).foregroundStyle(ink)
                                        Text(trip.start, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                        if !trip.reviewReasons.isEmpty { Label("Review GPS coverage", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                                    }
                                    Spacer()
                                    Text("\(trip.km(in: interval), specifier: "%.2f") km").font(.headline).foregroundStyle(ink)
                                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }
                }.padding(20)
            }.background(surface).navigationTitle("worklog.")
            .sheet(isPresented: $starting) {
                NavigationStack {
                    Form {
                        Section { TripDescriptionField(purpose: $purpose); TextField("Starting odometer in km (optional)", text: $startingOdometer).keyboardType(.decimalPad) } footer: { Text("Your last description is ready for the next trip. Add the job or customer name if needed.") }
                        Section { Text("Start before driving. Manual trips are saved as work trips, including outside scheduled hours.").font(.subheadline) }
                    }.navigationTitle("Start work trip").toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { starting = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Start") {
                                let reading = Double(startingOdometer)
                                if !startingOdometer.isEmpty && (reading == nil || !(reading?.isFinite ?? false) || (reading ?? -1) < 0) {
                                    store.error = "Enter a valid starting odometer in kilometres."; return
                                }
                                if recorder.startManual(purpose: purpose, startingOdometer: reading) { starting = false }
                            }.disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(item: $share) { ShareSheet(urls: $0.urls) }
        }
    }
    var recorderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(store.data.active == nil ? "WORK TRIP RECORDER" : "RECORDING WORK TRIP").font(.caption.weight(.semibold)); Spacer(); Image(systemName: "location.fill") }.foregroundStyle(.white.opacity(0.7))
            Text("\((store.data.active?.metres ?? 0)/1000, specifier: "%.2f") km").font(.system(size: 43, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            if let trip = store.data.active {
                Text(trip.purpose).foregroundStyle(.white.opacity(0.85))
                if let odometer = trip.odometerStart { Text("Starting odometer: \(odometer, specifier: "%.1f") km").font(.caption).foregroundStyle(.white.opacity(0.7)) }
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(trip.start, style: .timer).monospacedDigit().foregroundStyle(.white.opacity(0.7)) }
                Button { recorder.finish(cooldown: true) } label: { Label("Finish & save trip", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { purpose = store.lastTripDescription; startingOdometer = ""; starting = true } label: { Label("Start work trip", systemImage: "play.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(blue)
            }
            Text(recorder.status).font(.caption).foregroundStyle(.white.opacity(0.7))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(ink, in: RoundedRectangle(cornerRadius: 19))
    }
}

struct TripDetailView: View {
    @EnvironmentObject var store: WorkStore
    let tripID: UUID
    @State private var purpose = ""
    @State private var odometerStart = ""
    @State private var odometerEnd = ""
    @State private var excluded = false
    @State private var corrected = ""
    @State private var reason = ""
    @State private var message = ""
    var trip: Trip? { store.data.trips.first { $0.id == tripID } }
    var body: some View {
        Form {
            if let t = trip {
                Section("Work trip") {
                    LabeledContent("Distance", value: String(format: "%.2f km", t.km))
                    LabeledContent("GPS distance", value: String(format: "%.3f km", t.metres/1000))
                    LabeledContent("Started", value: t.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Finished", value: (t.end ?? t.start).formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Vehicle", value: t.vehicle.isEmpty ? "Not entered" : t.vehicle)
                    LabeledContent("Recording", value: t.automatic ? "Scheduled" : "Manual")
                    LabeledContent("Time zone", value: t.timeZoneID)
                }
                if !t.reviewReasons.isEmpty { Section("Review needed") { ForEach(t.reviewReasons, id: \.self) { Text($0).foregroundStyle(.orange) } } }
                Section("Accountant details") {
                    TextField("Odometer at start (km)", text: $odometerStart).keyboardType(.decimalPad)
                    TextField("Odometer at finish (km)", text: $odometerEnd).keyboardType(.decimalPad)
                    Toggle("Personal / exclude from work total", isOn: $excluded)
                    Button("Save accountant details") {
                        let first = Double(odometerStart), last = Double(odometerEnd)
                        if (!odometerStart.isEmpty && (first == nil || !(first?.isFinite ?? false) || (first ?? -1) < 0)) || (!odometerEnd.isEmpty && (last == nil || !(last?.isFinite ?? false) || (last ?? -1) < 0)) { message = "Enter valid odometer readings."; return }
                        if let first, let last, last < first { message = "Finish reading cannot be below start."; return }
                        update { $0.odometerStart = first; $0.odometerEnd = last; $0.excluded = excluded }
                    }
                }
                Section("Trip description") { TripDescriptionField(purpose: $purpose); Button("Save purpose") { if store.rememberTripDescription(purpose) { update { $0.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines) } } }.disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Section {
                    TextField("Corrected kilometres", text: $corrected).keyboardType(.decimalPad)
                    TextField("Reason / source of correct distance", text: $reason)
                    Button("Save distance correction") {
                        guard let km = Double(corrected), km.isFinite, km >= 0, !reason.trimmingCharacters(in: .whitespaces).isEmpty else { message = "Enter a valid distance and reason."; return }
                        update { $0.correctedKm = km; $0.correctionReason = reason; $0.correctedAt = Date() }
                    }
                } header: { Text("Correct missing GPS distance") } footer: { Text("The original GPS record is retained. Corrections crossing 1 July are allocated by elapsed time; review against your records.") }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Trip details").onAppear { if let t = trip { purpose = t.purpose; odometerStart = t.odometerStart.map { String($0) } ?? ""; odometerEnd = t.odometerEnd.map { String($0) } ?? ""; excluded = t.excluded ?? false; corrected = String(format: "%.3f", t.km); reason = t.correctionReason } }
    }
    func update(_ change: (inout Trip) -> Void) { guard let i = store.data.trips.firstIndex(where: { $0.id == tripID }) else { return }; let original = store.data.trips[i]; change(&store.data.trips[i]); if store.save() { message = "Saved." } else { store.data.trips[i] = original } }
}

struct ScheduleView: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @State private var draft = WorkSchedule()
    @State private var saved = false
    let days: [(Int, String)] = [(2,"Monday"),(3,"Tuesday"),(4,"Wednesday"),(5,"Thursday"),(6,"Friday"),(7,"Saturday"),(1,"Sunday")]
    var body: some View {
        NavigationStack {
            Form {
                Section { Toggle("Scheduled driving capture", isOn: $draft.enabled) } footer: { Text("When enabled, the app watches for driving during the days and times below. Only scheduled driving positions are saved. Manual trips can be recorded at any time.") }
                Section("Workdays") { ForEach(days, id: \.0) { day in Toggle(day.1, isOn: Binding(get: { draft.weekdays.contains(day.0) }, set: { if $0 { draft.weekdays.insert(day.0) } else { draft.weekdays.remove(day.0) } })) } }
                Section {
                    DatePicker("Start", selection: minuteBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker("Finish", selection: minuteBinding(start: false), displayedComponents: .hourAndMinute)
                    Picker("Time zone", selection: $draft.timeZoneID) {
                        Text("Perth (WA)").tag("Australia/Perth"); Text("Sydney").tag("Australia/Sydney"); Text("Brisbane").tag("Australia/Brisbane"); Text("Adelaide").tag("Australia/Adelaide"); Text("Darwin").tag("Australia/Darwin")
                    }
                } header: { Text("Work hours") } footer: { Text("A finish before the start time means an overnight shift. Selected days are the days a shift begins. Schedule and financial-year boundaries use the selected time zone.") }
                Section("Trip defaults") { TextField("Vehicle / registration", text: $draft.vehicle); TextField("Work purpose", text: $draft.purpose) }
                Section {
                    Button("Save schedule") {
                        recorder.applySchedule(draft); saved = store.data.schedule == draft
                    }.disabled(draft.weekdays.isEmpty || draft.startMinute == draft.endMinute || draft.purpose.trimmingCharacters(in: .whitespaces).isEmpty)
                    if saved { Label("Schedule saved", systemImage: "checkmark.circle").foregroundStyle(.green) }
                    Button("Enable background location") { recorder.requestAlways() }
                    Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                Section("Recording behaviour") {
                    Text("Driving is detected from consecutive GPS speeds above about 9 km/h. A trip finishes after about 3 minutes stopped or at shift end. Review trips for personal travel, passengers and GPS gaps.")
                    Text("Choose Always and Precise Location. Avoid force-closing the app. Restart it after rebooting. iOS can delay updates; exact start times and complete coverage are not guaranteed.")
                    Text("Monitoring uses background GPS while enabled, including between shifts to detect time boundaries. Only in-shift driving points are retained. This uses battery; turn it off when you do not need it.")
                }.font(.subheadline)
            }.navigationTitle("Work schedule").onAppear { draft = store.data.schedule }
        }
    }
    func minuteBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = start ? draft.startMinute : draft.endMinute
            return Calendar.current.date(bySettingHour: minutes/60, minute: minutes%60, second: 0, of: Date())!
        }, set: {
            let minutes = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
            if start { draft.startMinute = minutes } else { draft.endMinute = minutes }; saved = false
        })
    }
}

struct TripDescriptionField: View {
    @EnvironmentObject var store: WorkStore
    @Binding var purpose: String
    var body: some View {
        Picker("Quick select", selection: Binding(get: {
            store.tripDescriptionChoices.contains(purpose) ? purpose : ""
        }, set: { value in
            if !value.isEmpty { purpose = value; store.rememberTripDescription(value) }
        })) {
            Text("Choose a description").tag("")
            ForEach(store.tripDescriptionChoices, id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.menu)
        TextField("Trip description", text: $purpose, axis: .vertical)
            .onSubmit { store.rememberTripDescription(purpose) }
    }
}
