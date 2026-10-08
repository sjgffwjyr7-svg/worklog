import SwiftUI
import CoreLocation
import VisionKit
import UniformTypeIdentifiers

// MARK: - Theme

enum Theme {
    static let background = Color(red: 0.047, green: 0.051, blue: 0.063)   // #0C0D10
    static let card = Color(red: 0.106, green: 0.114, blue: 0.137)         // #1B1D23
    static let field = Color(red: 0.149, green: 0.161, blue: 0.192)        // #262931
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 1.0, green: 0.690, blue: 0.125)         // amber #FFB020
    static let accentDeep = Color(red: 1.0, green: 0.478, blue: 0.161)     // orange #FF7A29
    static let mint = Color(red: 0.204, green: 0.871, blue: 0.627)         // #34DEA0
    static let danger = Color(red: 1.0, green: 0.302, blue: 0.290)         // #FF4D4A
    static let warning = Color(red: 1.0, green: 0.769, blue: 0.290)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
    static let hero = LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    /// Dark background for Form and List screens.
    func themedForm() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
    /// A full-width button standing on its own inside a Form, so a tap only triggers that button.
    func buttonRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
    func cardStyle(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.textSecondary)
    }
}

private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }
}

/// Modern drop-down: label above a filled field showing the current choice; tapping opens a menu with a checkmark.
struct DropdownField<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var isPlaceholder: (Value) -> Bool = { _ in false }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(label)
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { Text(title($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title(selection))
                        .foregroundStyle(isPlaceholder(selection) ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                }
                .contentShape(Rectangle())
                .modifier(FieldBox())
            }
            .buttonStyle(.plain)
        }
    }
}

extension DropdownField where Value == String {
    init(_ label: String, selection: Binding<String>, options: [String], placeholder: String = "Select") {
        self.init(label: label, selection: selection, options: options,
                  title: { $0.isEmpty ? placeholder : $0 }, isPlaceholder: { $0.isEmpty })
    }
}

struct ThemedTextField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var multiline = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(label)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary), axis: multiline ? .vertical : .horizontal)
                .keyboardType(keyboard)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(multiline ? 2...5 : 1...1)
                .modifier(FieldBox())
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.hero)
    var foreground: Color = .black
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Compact capsule drop-down for picking an Australian financial year.
struct FinancialYearMenu: View {
    @Binding var year: Int
    let years: [Int]
    var body: some View {
        Menu {
            Picker("Financial year", selection: $year) {
                ForEach(years, id: \.self) { y in Text("FY \(String(y))–\(String(y + 1).suffix(2))").tag(y) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("FY \(String(year))–\(String(year + 1).suffix(2))").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.14), in: Capsule())
        }
    }
}

// MARK: - Screens

struct MainView: View {
    @State private var tab = DemoMode.initialTab
    var body: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Trips", systemImage: "car.side.fill") }.tag(0)
            InvoicesView().tabItem { Label("Receipts", systemImage: "doc.text.viewfinder") }.tag(1)
            ScheduleView().tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }.tag(2)
            StorageView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(3)
        }
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
    @State private var vehicleFilter: UUID?
    @State private var addingVehicle = false
    @State private var addingVehicleFromStart = false
    @State private var odometerWarning: OdometerCheck?
    var interval: DateInterval { FinancialYear.interval(year, timeZone: store.data.schedule.timeZoneID) }
    var trips: [Trip] { store.data.trips.filter { ($0.end ?? $0.start) > interval.start && $0.start < interval.end && (vehicleFilter == nil || $0.vehicleID == vehicleFilter) }.sorted { $0.start > $1.start } }
    var years: [Int] { Array(Set([year, FinancialYear.startYear(), FinancialYear.startYear()-1] + store.data.trips.map { FinancialYear.startYear(for: $0.start) } + store.data.invoices.map { FinancialYear.startYear(for: $0.date) })).sorted(by: >) }
    var totalKm: Double { trips.reduce(0) { $0 + $1.km(in: interval) } }
    var reviewCount: Int { trips.filter { !$0.reviewReasons.isEmpty }.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Work kilometres").font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Text("1 July \(String(year)) – 30 June \(String(year+1))").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        FinancialYearMenu(year: $year, years: years)
                    }
                    if store.vehicles.count > 1 {
                        Menu {
                            Picker("Vehicle log", selection: $vehicleFilter) {
                                Text("All vehicles").tag(UUID?.none)
                                ForEach(store.vehicles) { Text($0.displayName).tag(Optional($0.id)) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "car.2.fill")
                                Text(store.vehicle(vehicleFilter)?.displayName ?? "All vehicles").lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.mint.opacity(0.13), in: Capsule())
                        }
                    }
                    totalCard
                    recorderCard
                    if recorder.authorization != .authorizedAlways && store.data.schedule.enabled {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Always location needed", systemImage: "location.slash.fill").font(.headline).foregroundStyle(Theme.warning)
                            Text("Scheduled recording needs Always and Precise Location. Keep the app enabled and reopen after a restart or force-close.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        .cardStyle(padding: 18)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.warning.opacity(0.35)))
                    }
                    HStack {
                        Text("Trip log").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button { do { share = ShareFiles(urls: try store.accountantExport(year: year)) } catch { store.error = error.localizedDescription } } label: {
                            Label("Accountant", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                        }
                    }.padding(.top, 6)
                    if trips.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "road.lanes").font(.system(size: 34)).foregroundStyle(Theme.accent)
                            Text("Your first work trip starts here").font(.headline).foregroundStyle(Theme.textPrimary)
                            Text("Start a trip above or switch on your work schedule. Each trip saves kilometres, dates and times.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).cardStyle(padding: 28)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(trips) { trip in
                                NavigationLink { TripDetailView(tripID: trip.id) } label: { tripRow(trip) }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.horizontal, 18).padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationTitle("Worklog")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $starting) { startSheet }
            .sheet(isPresented: $addingVehicle) { VehicleEditorView(existing: nil) }
            .sheet(item: $share) { ShareSheet(urls: $0.urls) }
            .onAppear { if DemoMode.flag("-WorklogShowStart") { purpose = store.lastTripDescription; starting = true } }
        }
    }

    /// Starts a manual trip, first checking that the odometer suits the chosen vehicle.
    func attemptStart(vehicleID: UUID? = nil, checked: Bool = false) {
        let reading = Double(startingOdometer)
        if !startingOdometer.isEmpty && (reading == nil || !(reading?.isFinite ?? false) || (reading ?? -1) < 0) {
            store.error = "Enter a valid starting odometer in kilometres."; return
        }
        let chosen = vehicleID ?? store.currentVehicle?.id
        if !checked, let reading, let check = store.odometerCheck(reading: reading, vehicleID: chosen) { odometerWarning = check; return }
        if recorder.startManual(purpose: purpose, startingOdometer: reading, vehicleID: chosen) { starting = false }
    }

    var totalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalKm, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("km").font(.title3.weight(.semibold)).foregroundStyle(Theme.mint)
            }
            HStack(spacing: 10) {
                StatChip(icon: "car.side.fill", text: "\(trips.count) trips", color: Theme.accent)
                if reviewCount > 0 { StatChip(icon: "exclamationmark.triangle.fill", text: "\(reviewCount) to review", color: Theme.warning) }
                Spacer()
                StatChip(icon: "lock.iphone", text: "On iPhone", color: Theme.mint).fixedSize()
            }
        }.cardStyle(padding: 22)
    }

    var recorderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let trip = store.data.active {
                HStack(spacing: 8) {
                    Circle().fill(Theme.danger).frame(width: 9, height: 9)
                    Text("RECORDING").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.danger)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(trip.start, style: .timer).monospacedDigit().font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(trip.metres / 1000, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    Text("km GPS").font(.headline).foregroundStyle(Theme.mint)
                }
                VStack(alignment: .leading, spacing: 8) {
                    CurrentVehicleMenu(addingVehicle: $addingVehicle)
                    Text(trip.purpose).font(.headline).foregroundStyle(Theme.textPrimary)
                    if let odometer = trip.odometerStart {
                        Text("Starting odometer \(odometer, format: .number.precision(.fractionLength(0...1))) km").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
                Button { recorder.finish(cooldown: true) } label: { Label("Finish & save trip", systemImage: "stop.fill") }
                    .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.danger), foreground: .white))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to drive?").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Text("Start recording before you set off.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "steeringwheel").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                CurrentVehicleMenu(addingVehicle: $addingVehicle)
                Button { purpose = store.lastTripDescription; startingOdometer = ""; starting = true } label: { Label("Start work trip", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Label(recorder.status, systemImage: "location.fill").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .cardStyle(padding: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(store.data.active == nil ? Theme.accent.opacity(0.35) : Theme.danger.opacity(0.5), lineWidth: 1))
    }

    func tripRow(_ trip: Trip) -> some View {
        HStack(spacing: 14) {
            Image(systemName: trip.automatic ? "calendar.badge.clock" : "car.side.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.purpose).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                (Text(trip.start, format: .dateTime.weekday(.abbreviated).day().month().hour().minute()) + Text(trip.vehicle.isEmpty ? "" : " · \(trip.vehicle)"))
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if !trip.reviewReasons.isEmpty { Label("Review GPS coverage", systemImage: "exclamationmark.triangle.fill").font(.caption2.weight(.semibold)).foregroundStyle(Theme.warning) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.km(in: interval), format: .number.precision(.fractionLength(1))).font(.headline.monospacedDigit()).foregroundStyle(trip.excluded == true ? Theme.textTertiary : Theme.mint)
                Text(trip.excluded == true ? "private" : "km").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }.cardStyle(padding: 14)
    }

    var startSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.vehicles.isEmpty {
                        Button { addingVehicleFromStart = true } label: { Label("Add your vehicle", systemImage: "car.fill") }
                            .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                    } else {
                        VStack(alignment: .trailing, spacing: 8) {
                            DropdownField(label: "Vehicle", selection: Binding(get: { store.currentVehicle?.id }, set: { if let id = $0 { store.selectVehicle(id) } }),
                                          options: store.vehicles.map { Optional($0.id) }, title: { store.vehicle($0)?.displayName ?? "Choose a vehicle" })
                            Button { addingVehicleFromStart = true } label: { Label("Add vehicle", systemImage: "plus") }
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    TripDescriptionField(purpose: $purpose)
                    ThemedTextField(label: "Starting odometer (km)", prompt: "Optional — e.g. 128450", text: $startingOdometer, keyboard: .decimalPad)
                    Label("Your last description is ready for the next trip. Manual trips count as work trips, including outside scheduled hours.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Button { attemptStart() } label: { Label("Start recording", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Start work trip").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { starting = false } } }
            .sheet(isPresented: $addingVehicleFromStart) { VehicleEditorView(existing: nil) }
            .alert(odometerWarning?.suggested != nil ? "Different vehicle?" : "Check the odometer",
                   isPresented: Binding(get: { odometerWarning != nil }, set: { if !$0 { odometerWarning = nil } }), presenting: odometerWarning) { check in
                if let suggested = check.suggested {
                    Button("Use the \(suggested.displayName)") { attemptStart(vehicleID: suggested.id, checked: true) }
                }
                Button(check.selected.map { "Keep the \($0.displayName)" } ?? "Start anyway") { attemptStart(vehicleID: check.selected?.id, checked: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text($0.message) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}

struct StatChip: View {
    let icon: String, text: String, color: Color
    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct TripDetailView: View {
    @EnvironmentObject var store: WorkStore
    let tripID: UUID
    @State private var purpose = ""
    @State private var odometerStart = ""
    @State private var odometerEnd = ""
    @State private var excluded = false
    @State private var vehicleID: UUID?
    @State private var corrected = ""
    @State private var reason = ""
    @State private var message = ""
    var trip: Trip? { store.data.trips.first { $0.id == tripID } }
    var body: some View {
        Form {
            if let t = trip {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(t.km, format: .number.precision(.fractionLength(2))).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("km").font(.headline).foregroundStyle(Theme.mint)
                    }.padding(.vertical, 4)
                    LabeledContent("GPS distance", value: String(format: "%.3f km", t.metres/1000))
                    LabeledContent("Started", value: t.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Finished", value: (t.end ?? t.start).formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Vehicle", value: t.vehicle.isEmpty ? "Not entered" : t.vehicle)
                    LabeledContent("Recording", value: t.automatic ? "Scheduled" : "Manual")
                    LabeledContent("Time zone", value: t.timeZoneID)
                } header: { Text("Work trip") }
                if !t.reviewReasons.isEmpty { Section("Review needed") { ForEach(t.reviewReasons, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } } }
                Section("Trip description") {
                    TripDescriptionField(purpose: $purpose).padding(.vertical, 6)
                    Button("Save description") { if store.rememberTripDescription(purpose) { update { $0.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines) } } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonRow()
                }
                Section("Accountant details") {
                    DropdownField(label: "Vehicle", selection: $vehicleID, options: [nil] + store.vehicles.map { Optional($0.id) },
                                  title: { store.vehicle($0)?.displayName ?? "No vehicle" }).padding(.vertical, 6)
                    HStack(spacing: 12) {
                        ThemedTextField(label: "Odometer start", prompt: "km", text: $odometerStart, keyboard: .decimalPad)
                        ThemedTextField(label: "Odometer finish", prompt: "km", text: $odometerEnd, keyboard: .decimalPad)
                    }.padding(.vertical, 6)
                    Toggle("Personal — exclude from work total", isOn: $excluded)
                    Button("Save accountant details") {
                            let first = Double(odometerStart), last = Double(odometerEnd)
                            if (!odometerStart.isEmpty && (first == nil || !(first?.isFinite ?? false) || (first ?? -1) < 0)) || (!odometerEnd.isEmpty && (last == nil || !(last?.isFinite ?? false) || (last ?? -1) < 0)) { message = "Enter valid odometer readings."; return }
                            if let first, let last, last < first { message = "Finish reading cannot be below start."; return }
                            let chosen = store.vehicle(vehicleID)
                            update { $0.odometerStart = first; $0.odometerEnd = last; $0.excluded = excluded; $0.vehicleID = chosen?.id; $0.vehicle = chosen?.displayName ?? $0.vehicle }
                    }.buttonStyle(PrimaryButtonStyle()).buttonRow()
                }
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        ThemedTextField(label: "Corrected kilometres", prompt: "e.g. 42.5", text: $corrected, keyboard: .decimalPad)
                        ThemedTextField(label: "Reason / source", prompt: "e.g. Odometer readings", text: $reason)
                    }.padding(.vertical, 6)
                    Button("Save distance correction") {
                            guard let km = Double(corrected), km.isFinite, km >= 0, !reason.trimmingCharacters(in: .whitespaces).isEmpty else { message = "Enter a valid distance and reason."; return }
                            update { $0.correctedKm = km; $0.correctionReason = reason; $0.correctedAt = Date() }
                    }.buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
                } header: { Text("Correct missing GPS distance") } footer: { Text("The original GPS record is retained. Corrections crossing 1 July are allocated by elapsed time; review against your records.") }
                if !message.isEmpty { Label(message, systemImage: message == "Saved." ? "checkmark.circle.fill" : "info.circle").foregroundStyle(message == "Saved." ? Theme.mint : Theme.textSecondary) }
            }
        }
        .themedForm()
        .navigationTitle("Trip details")
        .onAppear { if let t = trip { purpose = t.purpose; odometerStart = t.odometerStart.map { String($0) } ?? ""; odometerEnd = t.odometerEnd.map { String($0) } ?? ""; excluded = t.excluded ?? false; vehicleID = t.vehicleID; corrected = String(format: "%.3f", t.km); reason = t.correctionReason } }
    }
    func update(_ change: (inout Trip) -> Void) { guard let i = store.data.trips.firstIndex(where: { $0.id == tripID }) else { return }; let original = store.data.trips[i]; change(&store.data.trips[i]); if store.save() { message = "Saved." } else { store.data.trips[i] = original } }
}

struct ScheduleView: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @State private var draft = WorkSchedule()
    @State private var saved = false
    let days: [(Int, String)] = [(2,"M"),(3,"T"),(4,"W"),(5,"T"),(6,"F"),(7,"S"),(1,"S")]
    let timeZones: [(String, String)] = [("Australia/Perth", "Perth (WA)"), ("Australia/Darwin", "Darwin (NT)"), ("Australia/Adelaide", "Adelaide (SA)"), ("Australia/Brisbane", "Brisbane (QLD)"), ("Australia/Sydney", "Sydney (NSW/ACT)"), ("Australia/Melbourne", "Melbourne (VIC)"), ("Australia/Hobart", "Hobart (TAS)")]
    var body: some View {
        NavigationStack {
            Form {
                Section { Toggle("Scheduled driving capture", isOn: $draft.enabled) } footer: { Text("When on, Worklog watches for driving during the days and hours below. Manual trips can be recorded at any time.") }
                Section("Workdays") {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.0) { day in
                            let on = draft.weekdays.contains(day.0)
                            Button {
                                if on { draft.weekdays.remove(day.0) } else { draft.weekdays.insert(day.0) }; saved = false
                            } label: {
                                Text(day.1).font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .foregroundStyle(on ? Color.black : Theme.textSecondary)
                                    .background(on ? AnyShapeStyle(Theme.hero) : AnyShapeStyle(Theme.field), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    DatePicker("Start", selection: minuteBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker("Finish", selection: minuteBinding(start: false), displayedComponents: .hourAndMinute)
                    DropdownField(label: "Time zone", selection: $draft.timeZoneID, options: timeZones.map { $0.0 },
                                  title: { id in timeZones.first { $0.0 == id }?.1 ?? id }).padding(.vertical, 4)
                } header: { Text("Work hours") } footer: { Text("A finish before the start time means an overnight shift. Selected days are the days a shift begins.") }
                Section("Trip defaults") {
                    VStack(spacing: 14) {
                        Label("Scheduled trips use your current vehicle: \(store.currentVehicle?.displayName ?? "none added yet"). Change it on the Trips screen or ask Siri.", systemImage: "car.fill")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                        ThemedTextField(label: "Work purpose", prompt: "e.g. Scheduled work driving", text: $draft.purpose)
                    }.padding(.vertical, 6)
                }
                Section {
                    Button { recorder.applySchedule(draft); saved = store.data.schedule == draft } label: { Label(saved ? "Schedule saved" : "Save schedule", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down") }
                        .buttonStyle(PrimaryButtonStyle(fill: saved ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Theme.hero)))
                        .disabled(draft.weekdays.isEmpty || draft.startMinute == draft.endMinute || draft.purpose.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonRow()
                    Button { recorder.requestAlways() } label: { Label("Enable background location", systemImage: "location.fill") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
                    Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: { Label("Open iPhone Settings", systemImage: "gearshape") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
                }
                Section("How recording works") {
                    Text("Driving is detected from consecutive GPS speeds above about 9 km/h. A trip finishes after about 3 minutes stopped or at shift end. Review trips for personal travel, passengers and GPS gaps.")
                    Text("Choose Always and Precise Location. Avoid force-closing the app and reopen it after a restart. iOS can delay updates, so exact start times and complete coverage are not guaranteed.")
                    Text("Monitoring uses background GPS while enabled, including between shifts. Only in-shift driving points are kept. Turn it off when you don't need it to save battery.")
                }.font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            .themedForm()
            .navigationTitle("Work schedule")
            .onAppear { draft = store.data.schedule }
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
        VStack(alignment: .leading, spacing: 14) {
            DropdownField("Quick select", selection: Binding(get: {
                store.tripDescriptionChoices.contains(purpose) ? purpose : ""
            }, set: { value in
                if !value.isEmpty { purpose = value; store.rememberTripDescription(value) }
            }), options: [""] + store.tripDescriptionChoices, placeholder: "Choose a trip purpose")
            ThemedTextField(label: "Trip description", prompt: "Add job or customer name", text: $purpose, multiline: true)
                .onSubmit { store.rememberTripDescription(purpose) }
        }
    }
}

// MARK: - Vehicles

/// Capsule menu showing the remembered current vehicle; choosing another switches it (and any recording trip).
struct CurrentVehicleMenu: View {
    @EnvironmentObject var store: WorkStore
    @Binding var addingVehicle: Bool
    var body: some View {
        Menu {
            Picker("Vehicle", selection: Binding(get: { store.currentVehicle?.id }, set: { if let id = $0 { store.selectVehicle(id) } })) {
                ForEach(store.vehicles) { Text($0.displayName).tag(Optional($0.id)) }
            }
            Divider()
            Button { addingVehicle = true } label: { Label("Add vehicle", systemImage: "plus") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text(store.currentVehicle?.displayName ?? "Add a vehicle").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.14), in: Capsule())
        }
    }
}

struct VehicleEditorView: View {
    let existing: Vehicle?
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var registration = ""
    @State private var odometer = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThemedTextField(label: "Vehicle name", prompt: "e.g. Hilux, Work ute", text: $name)
                    ThemedTextField(label: "Registration", prompt: "Optional — e.g. 1ABC234", text: $registration)
                    ThemedTextField(label: "Current odometer (km)", prompt: "Optional — helps spot the wrong vehicle", text: $odometer, keyboard: .decimalPad)
                    Text("Worklog compares each starting odometer with every vehicle's last reading and asks if it looks like you're in a different vehicle.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Theme.warning) }
                    Button { save() } label: { Label("Save vehicle", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "Add vehicle" : "Edit vehicle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard let existing else { return }
                name = existing.name; registration = existing.registration
                odometer = existing.startingOdometer.map { String($0) } ?? ""
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
    func save() {
        let reading = Double(odometer)
        if !odometer.isEmpty && (reading == nil || !(reading?.isFinite ?? false) || (reading ?? -1) < 0) { error = "Enter a valid odometer in kilometres."; return }
        var vehicle = existing ?? Vehicle(name: "")
        vehicle.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.registration = registration.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        vehicle.startingOdometer = reading
        guard store.saveVehicle(vehicle, makeCurrent: existing == nil) else { error = "The vehicle was not saved. Check device storage."; return }
        WorklogShortcuts.updateAppShortcutParameters()
        dismiss()
    }
}

struct VehiclesSettingsSection: View {
    @EnvironmentObject var store: WorkStore
    @State private var editing: Vehicle?
    @State private var adding = false
    var body: some View {
        Section {
            ForEach(store.vehicles) { vehicle in
                Button { editing = vehicle } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "car.fill").foregroundStyle(Theme.accent)
                            .frame(width: 38, height: 38).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.displayName).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(store.lastOdometer(for: vehicle.id).map { "Last odometer \($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "No odometer yet")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if vehicle.id == store.currentVehicle?.id { StatChip(icon: "checkmark", text: "Current", color: Theme.mint).fixedSize() }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        do { try store.deleteVehicle(vehicle.id); WorklogShortcuts.updateAppShortcutParameters() } catch { store.error = error.localizedDescription }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            Button { adding = true } label: { Label("Add vehicle", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
        } header: { Text("Vehicles") } footer: {
            Text("Each vehicle keeps its own trip log and export. The current vehicle is remembered when Worklog closes, and Siri can change it: “Change vehicle in Worklog”.")
        }
        .sheet(item: $editing) { VehicleEditorView(existing: $0) }
        .sheet(isPresented: $adding) { VehicleEditorView(existing: nil) }
    }
}
