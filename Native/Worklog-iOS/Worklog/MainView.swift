import SwiftUI
import CoreLocation
import VisionKit
import UniformTypeIdentifiers
import MapKit

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
    var secure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(label)
            if secure {
                SecureField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary))
                    .textContentType(.password)
                    .foregroundStyle(Theme.textPrimary)
                    .modifier(FieldBox())
            } else {
                TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary), axis: multiline ? .vertical : .horizontal)
                    .keyboardType(keyboard)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(multiline ? 2...5 : 1...1)
                    .modifier(FieldBox())
            }
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
            HoursView().tabItem { Label("Hours", systemImage: "clock.fill") }.tag(1)
            InvoicesView().tabItem { Label("Receipts", systemImage: "doc.text.viewfinder") }.tag(2)
            ScheduleView().tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }.tag(3)
            StorageView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(4)
        }
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @State private var starting = false
    @State private var startingOdometer = ""
    @State private var purpose = ""
    @State private var addingVehicle = false
    @State private var addingVehicleFromStart = false
    @State private var odometerWarning: OdometerCheck?
    @State private var finishing = false
    @State private var finishOdometer = ""
    @State private var openTripLog = false
    var trips: [Trip] { store.data.trips.sorted { $0.start > $1.start } }
    var thisWeekTrips: [Trip] {
        let tz = store.data.schedule.timeZoneID
        return TripCalendar.trips(trips, inWeek: TripCalendar.weekStart(of: Date(), timeZoneID: tz), timeZoneID: tz)
    }
    var reviewCount: Int { trips.filter { !$0.reviewReasons.isEmpty || store.placeAssessment($0) != nil }.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                    if trips.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "road.lanes").font(.system(size: 34)).foregroundStyle(Theme.accent)
                            Text("Your first work trip starts here").font(.headline).foregroundStyle(Theme.textPrimary)
                            Text("Start a trip above or switch on your work schedule. Each trip saves kilometres, dates and times.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).cardStyle(padding: 28)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            // Same look as the Start work trip button.
                            Button { openTripLog = true } label: { Label("Trip log", systemImage: "list.bullet.rectangle.portrait.fill") }
                                .buttonStyle(PrimaryButtonStyle())
                            HStack(spacing: 8) {
                                StatChip(icon: "calendar", text: "This week " + TripCalendar.workKm(thisWeekTrips).formatted(.number.precision(.fractionLength(1))) + " km", color: Theme.mint)
                                if reviewCount > 0 { StatChip(icon: "exclamationmark.triangle.fill", text: "\(reviewCount) to review", color: Theme.warning) }
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
            .sheet(isPresented: $finishing) { finishSheet }
            .navigationDestination(isPresented: $openTripLog) { TripLogView() }
            .onAppear {
                if DemoMode.flag("-WorklogShowStart") { purpose = store.lastTripDescription; starting = true }
                if DemoMode.flag("-WorklogOpenTripLog") { openTripLog = true }
            }
        }
    }

    /// Asks for the finishing odometer, which the ATO logbook needs for every journey.
    var finishSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let trip = store.data.active {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(trip.metres / 1000, format: .number.precision(.fractionLength(1))).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                            Text("km by GPS").font(.headline).foregroundStyle(Theme.mint)
                        }
                        Text(trip.purpose + (trip.vehicle.isEmpty ? "" : " · " + trip.vehicle)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        if let start = trip.odometerStart { Text("Starting odometer " + start.formatted(.number.precision(.fractionLength(0))) + " km").font(.subheadline).foregroundStyle(Theme.textSecondary) }
                    }
                    ThemedTextField(label: "Finishing odometer (km)", prompt: "Read it from the dashboard", text: $finishOdometer, keyboard: .decimalPad)
                    Text("The ATO logbook needs the odometer at the start and end of each journey. The suggested number is the start reading plus the GPS distance — check it against your dashboard.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Button {
                        let clean = finishOdometer.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                        var reading: Double?
                        if !clean.isEmpty {
                            guard let value = Double(clean), value.isFinite, value >= 0 else { store.error = "Enter the finishing odometer in kilometres."; return }
                            if let start = store.data.active?.odometerStart, value < start { store.error = "The finishing odometer can't be lower than the starting odometer."; return }
                            reading = value
                        }
                        recorder.finish(cooldown: true, odometerEnd: reading)
                        finishing = false
                    } label: { Label("Finish & save trip", systemImage: "stop.fill") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.danger), foreground: .white))
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Finish trip").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep recording") { finishing = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
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
                Button {
                    // Suggest start odometer + GPS distance; the driver checks it against the dashboard.
                    finishOdometer = trip.odometerStart.map { String(format: "%.0f", ($0 + trip.metres / 1000).rounded()) } ?? ""
                    finishing = true
                } label: { Label("Finish & save trip", systemImage: "stop.fill") }
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
                if let last = store.continuableTrip() {
                    // Drive back after a stop (e.g. picking up parts) as part of the same trip.
                    Button { recorder.continueLastTrip() } label: {
                        VStack(spacing: 3) {
                            Label("Continue last trip", systemImage: "arrow.uturn.backward")
                            (Text(last.purpose) + Text(" · stopped ") + Text(last.end ?? last.start, style: .relative) + Text(" ago"))
                                .font(.caption.weight(.medium)).lineLimit(1).opacity(0.85)
                        }
                    }.buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                }
            }
            Label(recorder.status, systemImage: "location.fill").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .cardStyle(padding: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(store.data.active == nil ? Theme.accent.opacity(0.35) : Theme.danger.opacity(0.5), lineWidth: 1))
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
                    ThemedTextField(label: "Starting odometer (km)", prompt: store.currentVehicle.flatMap { store.lastOdometer(for: $0.id) }.map { "Last recorded " + $0.formatted(.number.precision(.fractionLength(0))) + " km" } ?? "Needed for the ATO logbook — e.g. 128450", text: $startingOdometer, keyboard: .decimalPad)
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

// MARK: - Deleting

extension Trip {
    /// Shown in the delete confirmation so the driver can check it's the right trip.
    var deleteSummary: String {
        var lines = [purpose, start.formatted(date: .abbreviated, time: .shortened), String(format: "%.1f km", km)]
        if !vehicle.isEmpty { lines.append(vehicle) }
        return lines.joined(separator: "\n") + "\n\nThis can't be undone."
    }
}

extension Invoice {
    var deleteSummary: String {
        var lines = [supplier, date.formatted(date: .abbreviated, time: .shortened)]
        if let amount = Double(total) { lines.append(amount.formatted(.currency(code: "AUD"))) }
        if !number.isEmpty { lines.append("Invoice \(number)") }
        return lines.joined(separator: "\n") + "\n\nThe scanned PDF is deleted too. This can't be undone."
    }
}

/// Small red bin button used on every trip and receipt.
struct DeleteIconButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                .frame(width: 38, height: 38)
                .background(Theme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Delete")
    }
}

struct StatChip: View {
    let icon: String, text: String, color: Color
    var body: some View {
        // A plain HStack, not Label: inside List rows Label takes the row's icon layout and stretches.
        HStack(spacing: 5) { Image(systemName: icon); Text(text) }
            .font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}

struct TripDetailView: View {
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
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
                    ForEach(Array((t.pauses ?? []).enumerated()), id: \.offset) { _, stop in
                        LabeledContent("Stop", value: "\(stop.start.formatted(date: .omitted, time: .shortened)) – \(stop.end.formatted(date: .omitted, time: .shortened)) · \(Int(stop.duration / 60)) min")
                    }
                } header: { Text("Work trip") }
                if let check = store.placeAssessment(t) {
                    Section {
                        Label(check.message, systemImage: check.kind == .homeBreak ? "cup.and.saucer.fill" : "house.fill").foregroundStyle(Theme.warning)
                        Button { excluded = true; update { $0.excluded = true; $0.placeReviewed = true } } label: { Label("Mark private", systemImage: "person.fill") }
                            .buttonStyle(PrimaryButtonStyle()).buttonRow()
                        Button { update { $0.placeReviewed = true } } label: { Label("It was work", systemImage: "briefcase.fill") }
                            .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
                    } header: { Text(check.kind == .homeBreak ? "Break at home?" : "Commute?") }
                }
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
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete trip", systemImage: "trash") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.danger.opacity(0.16)), foreground: Theme.danger)).buttonRow()
                }
            }
        }
        .alert("Delete this trip?", isPresented: $confirmDelete, presenting: trip) { t in
            Button("Delete trip", role: .destructive) {
                do { try store.deleteTrip(t.id); dismiss() } catch { store.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0.deleteSummary) }
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
                    Text("Driving is detected from consecutive GPS speeds above about 9 km/h. A scheduled trip finishes after about 15 minutes stopped or at shift end, so short stops stay part of one trip. Trips you start yourself run until you tap Finish. Review trips for personal travel, passengers and GPS gaps.")
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
    @State private var make = ""
    @State private var model = ""
    @State private var engine = ""
    @State private var odometer = ""
    @State private var hasLogbook = false
    @State private var logbookStart = Date()
    @State private var logbookEnd = Date().addingTimeInterval(84 * 86400)
    @State private var logbookStartOdo = ""
    @State private var logbookEndOdo = ""
    @State private var year = FinancialYear.startYear()
    @State private var yearStartOdo = ""
    @State private var yearEndOdo = ""
    @State private var error: String?
    var weeks: Double { logbookEnd.timeIntervalSince(logbookStart) / (7 * 86400) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThemedTextField(label: "Vehicle name", prompt: "e.g. Hilux, Work ute", text: $name)
                    HStack(spacing: 12) {
                        ThemedTextField(label: "Make", prompt: "e.g. Toyota", text: $make)
                        ThemedTextField(label: "Model", prompt: "e.g. Hilux SR5", text: $model)
                    }
                    HStack(spacing: 12) {
                        ThemedTextField(label: "Engine capacity", prompt: "e.g. 2.8 L", text: $engine)
                        ThemedTextField(label: "Registration", prompt: "e.g. 1ABC234", text: $registration)
                    }
                    ThemedTextField(label: "Current odometer (km)", prompt: "Helps spot the wrong vehicle", text: $odometer, keyboard: .decimalPad)

                    Text("ATO LOGBOOK PERIOD").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent).padding(.top, 8)
                    Toggle("I'm keeping a logbook period", isOn: $hasLogbook).tint(Theme.accent)
                    if hasLogbook {
                        DatePicker("Starts", selection: $logbookStart, displayedComponents: .date)
                        DatePicker("Ends", selection: $logbookEnd, in: logbookStart..., displayedComponents: .date)
                        HStack(spacing: 12) {
                            ThemedTextField(label: "Odometer at start", prompt: "km", text: $logbookStartOdo, keyboard: .decimalPad)
                            ThemedTextField(label: "Odometer at end", prompt: "km", text: $logbookEndOdo, keyboard: .decimalPad)
                        }
                        Label(String(format: "%.1f weeks", weeks) + (weeks < WorkStore.logbookMinimumWeeks ? " — must be at least 12 continuous weeks" : ""),
                              systemImage: weeks < WorkStore.logbookMinimumWeeks ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(weeks < WorkStore.logbookMinimumWeeks ? Theme.warning : Theme.mint)
                    }
                    Text("Record every trip, business and private, during a representative 12-week period. Your business-use percentage is the work km divided by the total km shown by the odometer readings. A logbook is valid for 5 years unless your driving changes.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)

                    Text("FINANCIAL YEAR ODOMETER").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent).padding(.top, 8)
                    DropdownField(label: "Financial year", selection: $year, options: Array((FinancialYear.startYear() - 5...FinancialYear.startYear()).reversed()),
                                  title: { "FY \(String($0))–\(String($0 + 1).suffix(2))" })
                    HStack(spacing: 12) {
                        ThemedTextField(label: "On 1 July \(String(year))", prompt: "km", text: $yearStartOdo, keyboard: .decimalPad)
                        ThemedTextField(label: "On 30 June \(String(year + 1))", prompt: "km", text: $yearEndOdo, keyboard: .decimalPad)
                    }
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
                guard let v = existing else { loadYear(); return }
                name = v.name; registration = v.registration; make = v.make ?? ""; model = v.model ?? ""; engine = v.engineCapacity ?? ""
                odometer = v.startingOdometer.map { String(format: "%.0f", $0) } ?? ""
                if let start = v.logbookStart { hasLogbook = true; logbookStart = start; logbookEnd = v.logbookEnd ?? start.addingTimeInterval(84 * 86400) }
                logbookStartOdo = v.logbookStartOdometer.map { String(format: "%.0f", $0) } ?? ""
                logbookEndOdo = v.logbookEndOdometer.map { String(format: "%.0f", $0) } ?? ""
                loadYear()
            }
            .onChange(of: year) { _, _ in loadYear() }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }
    func loadYear() {
        let reading = existing?.yearOdometers?[String(year)]
        yearStartOdo = reading?.start.map { String(format: "%.0f", $0) } ?? ""
        yearEndOdo = reading?.end.map { String(format: "%.0f", $0) } ?? ""
    }
    /// Empty text is nil; anything else must be a non-negative number.
    func reading(_ text: String) -> Double?? {
        let clean = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if clean.isEmpty { return .some(nil) }
        guard let value = Double(clean), value.isFinite, value >= 0 else { return nil }
        return .some(value)
    }
    func save() {
        guard let current = reading(odometer), let lbStart = reading(logbookStartOdo), let lbEnd = reading(logbookEndOdo),
              let fyStart = reading(yearStartOdo), let fyEnd = reading(yearEndOdo) else { error = "Enter odometer readings as numbers of kilometres."; return }
        if let a = lbStart, let b = lbEnd, b < a { error = "The logbook end odometer can't be lower than the start."; return }
        if let a = fyStart, let b = fyEnd, b < a { error = "The 30 June odometer can't be lower than 1 July."; return }
        var vehicle = existing ?? Vehicle(name: "")
        vehicle.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.registration = registration.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        vehicle.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.engineCapacity = engine.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.startingOdometer = current
        vehicle.logbookStart = hasLogbook ? logbookStart : nil
        vehicle.logbookEnd = hasLogbook ? logbookEnd : nil
        vehicle.logbookStartOdometer = hasLogbook ? lbStart : nil
        vehicle.logbookEndOdometer = hasLogbook ? lbEnd : nil
        var years = vehicle.yearOdometers ?? [:]
        years[String(year)] = YearOdometer(start: fyStart, end: fyEnd)
        vehicle.yearOdometers = years
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

// MARK: - Home and work

struct PlacesSettingsSection: View {
    @EnvironmentObject var store: WorkStore
    @State private var editingHome: Bool?
    var body: some View {
        Section {
            row(title: "Home", icon: "house.fill", place: store.data.home) { editingHome = true }
            row(title: "Work", icon: "briefcase.fill", place: store.data.workplace) { editingHome = false }
        } header: { Text("Home & work") } footer: {
            Text("Trips between home and work are tagged Commute?, and trips ending at home during work hours are tagged Break?, so you can mark them private. Addresses stay on this iPhone.")
        }
        .sheet(item: Binding(get: { editingHome.map { PlaceKind(home: $0) } }, set: { editingHome = $0?.home })) { PlaceEditorView(home: $0.home) }
    }
    func row(title: String, icon: String, place: Place?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(place?.address ?? "Not set — tap to add").font(.caption).foregroundStyle(place == nil ? Theme.textTertiary : Theme.textSecondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct PlaceKind: Identifiable { let home: Bool; var id: Bool { home } }

struct PlaceEditorView: View {
    let home: Bool
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var recorder: TripRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var found: Place?
    @State private var radius = 250.0
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThemedTextField(label: home ? "Home address" : "Work address", prompt: "Street, town, state", text: $address, multiline: true)
                    HStack(spacing: 12) {
                        Button { Task { await lookUp() } } label: { Label("Find address", systemImage: "magnifyingglass") }
                            .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                            .disabled(busy || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button { Task { await useCurrentLocation() } } label: { Label("I'm here now", systemImage: "location.fill") }
                            .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                            .disabled(busy)
                    }
                    if busy { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }
                    if let found {
                        let centre = CLLocationCoordinate2D(latitude: found.latitude, longitude: found.longitude)
                        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: radius * 6, longitudinalMeters: radius * 6))) {
                            Marker(home ? "Home" : "Work", systemImage: home ? "house.fill" : "briefcase.fill", coordinate: centre).tint(Theme.accent)
                            MapCircle(center: centre, radius: radius).foregroundStyle(Theme.accent.opacity(0.18)).stroke(Theme.accent, lineWidth: 1.5)
                        }
                        .id("\(found.latitude),\(found.longitude),\(radius)")
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        DropdownField(label: "Counts as \(home ? "home" : "work") within", selection: $radius, options: [100.0, 250.0, 500.0, 1000.0],
                                      title: { $0 >= 1000 ? "1 km" : "\(Int($0)) m" })
                    }
                    if let message { Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    Button { save() } label: { Label("Save \(home ? "home" : "work")", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(found == nil)
                        .opacity(found == nil ? 0.45 : 1)
                    if (home ? store.data.home : store.data.workplace) != nil {
                        Button(role: .destructive) { store.savePlace(nil, home: home); dismiss() } label: { Label("Remove", systemImage: "trash") }
                            .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.danger))
                    }
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(home ? "Home" : "Work").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let saved = home ? store.data.home : store.data.workplace { found = saved; address = saved.address; radius = saved.radius }
            }
        }
        .presentationBackground(Theme.background)
    }
    func lookUp() async {
        busy = true; message = nil; defer { busy = false }
        do {
            let marks = try await CLGeocoder().geocodeAddressString(address, in: nil, preferredLocale: Locale(identifier: "en_AU"))
            guard let mark = marks.first, let location = mark.location else { message = "Address not found. Add the town and state."; return }
            found = Place(address: format(mark) ?? address, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radius: radius)
            message = "Check the pin is in the right spot before saving."
        } catch { message = "Address not found. Check the spelling, or use “I'm here now” when you're there." }
    }
    func useCurrentLocation() async {
        guard let here = recorder.lastKnownLocation, here.horizontalAccuracy >= 0, here.horizontalAccuracy <= 100 else {
            recorder.requestPermission()
            message = "Your location isn't available yet. Allow location, wait a moment outside, then try again."; return
        }
        busy = true; defer { busy = false }
        let mark = try? await CLGeocoder().reverseGeocodeLocation(here).first
        let text = mark.flatMap(format) ?? String(format: "%.5f, %.5f", here.coordinate.latitude, here.coordinate.longitude)
        address = text
        found = Place(address: text, latitude: here.coordinate.latitude, longitude: here.coordinate.longitude, radius: radius)
        message = "Using where you are now (±\(Int(here.horizontalAccuracy)) m)."
    }
    func format(_ mark: CLPlacemark) -> String? {
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, mark.locality, mark.administrativeArea, mark.postalCode].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    func save() {
        guard var place = found else { return }
        place.radius = radius
        if store.savePlace(place, home: home) { dismiss() } else { message = "Not saved. Check device storage." }
    }
}

// MARK: - Trip log (weeks → days → trips)

struct TripRow: View {
    @EnvironmentObject var store: WorkStore
    let trip: Trip
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.automatic ? "calendar.badge.clock" : "car.side.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.purpose).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                (Text(trip.start, format: .dateTime.hour().minute()) + Text(trip.end.map { " – " + $0.formatted(.dateTime.hour().minute()) } ?? "") + Text(trip.vehicle.isEmpty ? "" : " · \(trip.vehicle)"))
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                HStack(spacing: 8) {
                    if let check = store.placeAssessment(trip) { Label(check.short, systemImage: check.kind == .homeBreak ? "cup.and.saucer.fill" : "house.fill").font(.caption2.weight(.semibold)).foregroundStyle(Theme.warning) }
                    if !trip.reviewReasons.isEmpty { Label("Review GPS", systemImage: "exclamationmark.triangle.fill").font(.caption2.weight(.semibold)).foregroundStyle(Theme.warning) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.km, format: .number.precision(.fractionLength(1))).font(.headline.monospacedDigit()).foregroundStyle(trip.excluded == true ? Theme.textTertiary : Theme.mint)
                Text(trip.excluded == true ? "private" : "km").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }.contentShape(Rectangle())
    }
}

/// Folder-style row used for weeks and days.
struct LogFolderRow: View {
    let title: String
    let subtitle: String
    var km: Double = 0
    let count: Int
    var highlight: String? = nil
    /// When set (e.g. "$128.40"), shown instead of kilometres — used by the receipt folders.
    var amount: String? = nil
    var emptyText = "No trips"
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: count == 0 ? "folder" : "folder.fill").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(count == 0 ? Theme.textTertiary : Theme.accent)
                .frame(width: 42, height: 42).background((count == 0 ? Theme.field : Theme.accent.opacity(0.14)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(count == 0 ? Theme.textTertiary : Theme.textPrimary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if let highlight { StatChip(icon: "star.fill", text: highlight, color: Theme.mint).padding(.top, 2) }
            }.layoutPriority(1)
            Spacer(minLength: 8)
            if count > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount {
                        Text(amount).font(.headline.monospacedDigit()).foregroundStyle(Theme.mint)
                    } else {
                        Text(km, format: .number.precision(.fractionLength(1))).font(.headline.monospacedDigit()).foregroundStyle(Theme.mint)
                        Text("km").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }.fixedSize()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            } else {
                Text(emptyText).font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }.contentShape(Rectangle()).cardStyle(padding: 14)
    }
}

extension Date {
    /// Formats in the schedule's time zone so a Monday-midnight week start never shows as Sunday.
    func formatted(_ style: Date.FormatStyle, in timeZoneID: String) -> String {
        var style = style
        style.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return formatted(style)
    }
}

func tripCount(_ n: Int) -> String { n == 1 ? "1 trip" : "\(n) trips" }

/// Trips for one vehicle (or all), shared by the trip log screens.
@MainActor private func logTrips(_ store: WorkStore, vehicleFilter: UUID?) -> [Trip] {
    store.data.trips.filter { vehicleFilter == nil || $0.vehicleID == vehicleFilter }
}

private struct LogHeader: View {
    let km: Double
    let caption: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(km, format: .number.precision(.fractionLength(1))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
        }.padding(.bottom, 6)
    }
}

/// Top of the trip log: financial years with their work kilometres.
struct TripLogView: View {
    @EnvironmentObject var store: WorkStore
    @State private var vehicleFilter: UUID?
    @State private var openYear: Int?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let all = logTrips(store, vehicleFilter: vehicleFilter)
        let years = TripCalendar.financialYears(all, timeZoneID: tz)
        let current = FinancialYear.startYear(for: Date(), timeZone: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.vehicles.count > 1 {
                    Menu {
                        Picker("Vehicle", selection: $vehicleFilter) {
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
                    }.padding(.bottom, 6)
                }
                if years.isEmpty { Text("No trips recorded yet.").foregroundStyle(Theme.textSecondary) }
                ForEach(years, id: \.self) { year in
                    let span = FinancialYear.interval(year, timeZone: tz)
                    let yearTrips = all.filter { span.contains($0.start) }
                    Button { openYear = year } label: {
                        LogFolderRow(title: "FY \(String(year))–\(String(year + 1).suffix(2))",
                                     subtitle: "1 July \(String(year)) – 30 June \(String(year + 1)) · " + tripCount(yearTrips.count),
                                     km: TripCalendar.workKm(yearTrips), count: yearTrips.count, highlight: year == current ? "This year" : nil)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Trip log")
        .navigationDestination(item: $openYear) { TripYearView(year: $0, vehicleFilter: vehicleFilter) }
        .onAppear { if DemoMode.flag("-WorklogOpenYear"), openYear == nil { openYear = years.first } }
    }
}

struct TripYearView: View {
    @EnvironmentObject var store: WorkStore
    let year: Int
    let vehicleFilter: UUID?
    @State private var openMonth: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = FinancialYear.interval(year, timeZone: tz)
        let yearTrips = logTrips(store, vehicleFilter: vehicleFilter).filter { span.contains($0.start) }
        let months = TripCalendar.months(yearTrips, timeZoneID: tz)
        let thisMonth = TripCalendar.monthStart(of: Date(), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                LogHeader(km: TripCalendar.workKm(yearTrips), caption: "work km · " + tripCount(yearTrips.count))
                ForEach(months, id: \.self) { month in
                    let monthTrips = TripCalendar.trips(yearTrips, within: TripCalendar.monthInterval(of: month, timeZoneID: tz))
                    Button { openMonth = month } label: {
                        LogFolderRow(title: month.formatted(.dateTime.month(.wide).year(), in: tz), subtitle: tripCount(monthTrips.count),
                                     km: TripCalendar.workKm(monthTrips), count: monthTrips.count, highlight: month == thisMonth ? "This month" : nil)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("FY \(String(year))–\(String(year + 1).suffix(2))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openMonth) { TripMonthView(month: $0, vehicleFilter: vehicleFilter) }
        .onAppear { if DemoMode.flag("-WorklogOpenMonth"), openMonth == nil { openMonth = months.first } }
    }
}

struct TripMonthView: View {
    @EnvironmentObject var store: WorkStore
    let month: Date
    let vehicleFilter: UUID?
    @State private var openWeek: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = TripCalendar.monthInterval(of: month, timeZoneID: tz)
        let monthTrips = TripCalendar.trips(logTrips(store, vehicleFilter: vehicleFilter), within: span)
        let weeks = TripCalendar.weeks(monthTrips, timeZoneID: tz)
        let thisWeek = TripCalendar.weekStart(of: Date(), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                LogHeader(km: TripCalendar.workKm(monthTrips), caption: "work km · " + tripCount(monthTrips.count))
                ForEach(weeks, id: \.self) { week in
                    let weekTrips = TripCalendar.trips(monthTrips, inWeek: week, timeZoneID: tz)
                    let last = TripCalendar.days(inWeek: week, timeZoneID: tz).last ?? week
                    let partWeek = !span.contains(week) || !span.contains(last)
                    Button { openWeek = week } label: {
                        LogFolderRow(title: week.formatted(.dateTime.day().month(), in: tz) + " – " + last.formatted(.dateTime.day().month(), in: tz),
                                     subtitle: (partWeek ? "Part week · " : "Mon to Sun · ") + tripCount(weekTrips.count),
                                     km: TripCalendar.workKm(weekTrips), count: weekTrips.count, highlight: week == thisWeek ? "This week" : nil)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(month.formatted(.dateTime.month(.wide).year(), in: tz))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openWeek) { TripWeekView(weekStart: $0, within: span, vehicleFilter: vehicleFilter) }
        .onAppear { if DemoMode.flag("-WorklogOpenWeek"), openWeek == nil { openWeek = weeks.first } }
    }
}

struct TripWeekView: View {
    @EnvironmentObject var store: WorkStore
    let weekStart: Date
    /// The month this week was opened from; a week crossing months shows only that month's days.
    let within: DateInterval
    let vehicleFilter: UUID?
    @State private var openDay: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let weekTrips = TripCalendar.trips(TripCalendar.trips(logTrips(store, vehicleFilter: vehicleFilter), within: within), inWeek: weekStart, timeZoneID: tz)
        let allDays = TripCalendar.days(inWeek: weekStart, timeZoneID: tz)
        let days = allDays.filter { within.contains($0) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                LogHeader(km: TripCalendar.workKm(weekTrips), caption: "work km this week")
                ForEach(days, id: \.self) { day in
                    let dayTrips = TripCalendar.trips(weekTrips, onDay: day, timeZoneID: tz)
                    Button { openDay = day } label: {
                        LogFolderRow(title: day.formatted(.dateTime.weekday(.wide), in: tz), subtitle: day.formatted(.dateTime.day().month(.wide).year(), in: tz) + (dayTrips.isEmpty ? "" : " · " + tripCount(dayTrips.count)),
                                     km: TripCalendar.workKm(dayTrips), count: dayTrips.count,
                                     highlight: TripCalendar.calendar(tz).isDateInToday(day) ? "Today" : nil)
                    }.buttonStyle(.plain).disabled(dayTrips.isEmpty)
                }
                if days.count < 7 {
                    Text("The rest of this week is in the next or previous month.").font(.footnote).foregroundStyle(Theme.textTertiary)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Mon \(weekStart.formatted(.dateTime.day().month(), in: tz)) – Sun \((allDays.last ?? weekStart).formatted(.dateTime.day().month(), in: tz))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { TripDayView(day: $0, vehicleFilter: vehicleFilter) }
        .onAppear {
            if DemoMode.flag("-WorklogOpenDay"), openDay == nil { openDay = days.last { !TripCalendar.trips(weekTrips, onDay: $0, timeZoneID: tz).isEmpty } }
        }
    }
}

struct TripDayView: View {
    @EnvironmentObject var store: WorkStore
    let day: Date
    let vehicleFilter: UUID?
    @State private var pendingDelete: Trip?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let dayTrips = TripCalendar.trips(logTrips(store, vehicleFilter: vehicleFilter), onDay: day, timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                LogHeader(km: TripCalendar.workKm(dayTrips), caption: "work km · " + tripCount(dayTrips.count))
                if dayTrips.isEmpty { Text("No trips on this day.").foregroundStyle(Theme.textSecondary) }
                ForEach(dayTrips) { trip in
                    HStack(spacing: 10) {
                        NavigationLink { TripDetailView(tripID: trip.id) } label: { TripRow(trip: trip) }.buttonStyle(.plain)
                        DeleteIconButton { pendingDelete = trip }
                    }.cardStyle(padding: 14)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(), in: tz))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this trip?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { trip in
            Button("Delete trip", role: .destructive) { do { try store.deleteTrip(trip.id) } catch { store.error = error.localizedDescription } }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0.deleteSummary) }
        .onAppear { if DemoMode.flag("-WorklogShowDelete"), pendingDelete == nil { pendingDelete = dayTrips.first } }
    }
}

// MARK: - Hours worked

/// The place picked last time, so clocking on is one tap (also used by Siri).
enum LastShiftPlace {
    static var value: ShiftPlace {
        get { ShiftPlace(rawValue: UserDefaults.standard.string(forKey: "lastShiftPlace") ?? "") ?? .workplace }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lastShiftPlace") }
    }
}

/// Seconds worked by shifts starting inside a span, counting a shift still in progress.
@MainActor func workedSeconds(_ store: WorkStore, in span: DateInterval, place: ShiftPlace? = nil, now: Date = Date()) -> TimeInterval {
    (store.shifts + (store.data.activeShift.map { [$0] } ?? []))
        .filter { $0.start >= span.start && $0.start < span.end && (place == nil || $0.place == place) }
        .reduce(0) { $0 + $1.workedSeconds(at: now) }
}

struct HoursView: View {
    @EnvironmentObject var store: WorkStore
    @State private var place = LastShiftPlace.value
    @State private var notes = ""
    @State private var openLog = false
    @State private var adding = false
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    shiftCard
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let cal = TripCalendar.calendar(tz)
                        let today = cal.dateInterval(of: .day, for: context.date) ?? DateInterval(start: context.date, duration: 86400)
                        let week = DateInterval(start: TripCalendar.weekStart(of: context.date, timeZoneID: tz), duration: 7 * 86400)
                        let fy = FinancialYear.interval(FinancialYear.startYear(for: context.date, timeZone: tz), timeZone: tz)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                StatChip(icon: "sun.max.fill", text: "Today " + hoursText(workedSeconds(store, in: today, now: context.date)), color: Theme.mint)
                                StatChip(icon: "calendar", text: "This week " + hoursText(workedSeconds(store, in: week, now: context.date)), color: Theme.accent)
                            }
                            HStack(spacing: 10) {
                                StatChip(icon: "briefcase.fill", text: "This year " + hoursText(workedSeconds(store, in: fy, now: context.date)), color: Theme.mint)
                                StatChip(icon: "house.fill", text: "From home " + hoursText(workedSeconds(store, in: fy, place: .home, now: context.date)), color: Theme.accent)
                            }
                        }
                    }
                    Button { openLog = true } label: { Label("Timesheet", systemImage: "list.bullet.rectangle.portrait.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button { adding = true } label: { Label("Add hours manually", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                    Text("Working-from-home hours are totalled separately for the ATO's fixed-rate method, which needs a record of the actual hours you worked at home.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }.padding(.horizontal, 18).padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationTitle("Hours")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(isPresented: $openLog) { HoursLogView() }
            .sheet(isPresented: $adding) { ShiftEditorView(existing: nil) }
            .onAppear { if DemoMode.flag("-WorklogOpenHoursLog") { openLog = true } }
        }
    }

    var shiftCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let shift = store.data.activeShift {
                let onBreak = shift.breakStart != nil
                HStack(spacing: 8) {
                    Circle().fill(onBreak ? Theme.warning : Theme.mint).frame(width: 9, height: 9)
                    Text(onBreak ? "ON BREAK" : "ON SHIFT").font(.caption.weight(.bold)).tracking(1).foregroundStyle(onBreak ? Theme.warning : Theme.mint)
                    Spacer()
                    Text(shift.place.rawValue).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hoursText(shift.workedSeconds(at: context.date))).font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("Clocked on " + shift.start.formatted(date: .omitted, time: .shortened) + " · breaks " + hoursText(shift.breakSeconds(at: context.date)))
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        if context.date.timeIntervalSince(shift.start) > 14 * 3600 {
                            Label("Still clocked on after 14 hours. Clock off, then correct the finish time in the timesheet.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(Theme.warning)
                        }
                    }
                }
                if !shift.notes.isEmpty { Text(shift.notes).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                Button { if onBreak { store.endBreak() } else { store.startBreak() } } label: {
                    Label(onBreak ? "End break" : "Start break", systemImage: onBreak ? "play.fill" : "cup.and.saucer.fill")
                }.buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent))
                Button { store.clockOff() } label: { Label("Clock off", systemImage: "stop.fill") }
                    .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.danger), foreground: .white))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to start work?").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Text("Clock on to record your hours.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "clock.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                DropdownField(label: "Where are you working?", selection: $place, options: ShiftPlace.allCases, title: { $0.rawValue })
                ThemedTextField(label: "Notes", prompt: "Optional — job or customer", text: $notes)
                Button {
                    if store.clockOn(place: place, notes: notes) { LastShiftPlace.value = place; notes = "" }
                } label: { Label("Clock on", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle(padding: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(store.data.activeShift == nil ? Theme.accent.opacity(0.35) : Theme.mint.opacity(0.5), lineWidth: 1))
    }
}

struct ShiftRow: View {
    let shift: WorkShift
    let tz: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shift.place == .home ? "house.fill" : shift.place == .road ? "car.side.fill" : "briefcase.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.start.formatted(.dateTime.hour().minute(), in: tz) + " – " + (shift.end?.formatted(.dateTime.hour().minute(), in: tz) ?? "now"))
                    .font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(shift.place.rawValue + (shift.breakSeconds() > 0 ? " · breaks " + hoursText(shift.breakSeconds()) : "") + (shift.manual ? " · added manually" : ""))
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if !shift.notes.isEmpty { Text(shift.notes).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1) }
            }.layoutPriority(1)
            Spacer(minLength: 8)
            Text(hoursText(shift.workedSeconds())).font(.headline.monospacedDigit()).foregroundStyle(Theme.mint).fixedSize()
        }.contentShape(Rectangle())
    }
}

/// Timesheet: financial years → months → Monday–Sunday weeks → days → shifts.
struct HoursLogView: View {
    @EnvironmentObject var store: WorkStore
    @State private var openYear: Int?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let years = Array(Set(store.shifts.map { FinancialYear.startYear(for: $0.start, timeZone: tz) })).sorted(by: >)
        let current = FinancialYear.startYear(for: Date(), timeZone: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if years.isEmpty { Text("No hours recorded yet. Clock on to start.").foregroundStyle(Theme.textSecondary) }
                ForEach(years, id: \.self) { year in
                    let span = FinancialYear.interval(year, timeZone: tz)
                    let count = store.shifts.filter { span.contains($0.start) }.count
                    Button { openYear = year } label: {
                        LogFolderRow(title: "FY \(String(year))–\(String(year + 1).suffix(2))",
                                     subtitle: "From home " + hoursText(workedSeconds(store, in: span, place: .home)) + " · \(count) shift\(count == 1 ? "" : "s")",
                                     count: count, highlight: year == current ? "This year" : nil, amount: hoursText(workedSeconds(store, in: span)), emptyText: "No hours")
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Timesheet")
        .navigationDestination(item: $openYear) { HoursYearView(year: $0) }
        .onAppear { if DemoMode.flag("-WorklogOpenHoursYear"), openYear == nil { openYear = years.first } }
    }
}

struct HoursYearView: View {
    @EnvironmentObject var store: WorkStore
    let year: Int
    @State private var openMonth: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = FinancialYear.interval(year, timeZone: tz)
        let months = TripCalendar.monthStarts(store.shifts.filter { span.contains($0.start) }.map(\.start), timeZoneID: tz)
        let thisMonth = TripCalendar.monthStart(of: Date(), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HoursHeader(seconds: workedSeconds(store, in: span), caption: "worked this year")
                ForEach(months, id: \.self) { month in
                    let m = TripCalendar.monthInterval(of: month, timeZoneID: tz)
                    let count = store.shifts.filter { m.contains($0.start) }.count
                    Button { openMonth = month } label: {
                        LogFolderRow(title: month.formatted(.dateTime.month(.wide).year(), in: tz), subtitle: "\(count) shift\(count == 1 ? "" : "s")",
                                     count: count, highlight: month == thisMonth ? "This month" : nil, amount: hoursText(workedSeconds(store, in: m)), emptyText: "No hours")
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("FY \(String(year))–\(String(year + 1).suffix(2))").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openMonth) { HoursMonthView(month: $0) }
        .onAppear { if DemoMode.flag("-WorklogOpenHoursMonth"), openMonth == nil { openMonth = months.first } }
    }
}

struct HoursMonthView: View {
    @EnvironmentObject var store: WorkStore
    let month: Date
    @State private var openWeek: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = TripCalendar.monthInterval(of: month, timeZoneID: tz)
        let monthShifts = store.shifts.filter { span.contains($0.start) }
        let weeks = TripCalendar.weekStarts(monthShifts.map(\.start), timeZoneID: tz)
        let thisWeek = TripCalendar.weekStart(of: Date(), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HoursHeader(seconds: workedSeconds(store, in: span), caption: "worked this month")
                ForEach(weeks, id: \.self) { week in
                    let last = TripCalendar.days(inWeek: week, timeZoneID: tz).last ?? week
                    let weekShifts = monthShifts.filter { TripCalendar.weekStart(of: $0.start, timeZoneID: tz) == week }
                    let partWeek = !span.contains(week) || !span.contains(last)
                    Button { openWeek = week } label: {
                        LogFolderRow(title: week.formatted(.dateTime.day().month(), in: tz) + " – " + last.formatted(.dateTime.day().month(), in: tz),
                                     subtitle: (partWeek ? "Part week · " : "Mon to Sun · ") + "\(weekShifts.count) shift\(weekShifts.count == 1 ? "" : "s")",
                                     count: weekShifts.count, highlight: week == thisWeek ? "This week" : nil,
                                     amount: hoursText(weekShifts.reduce(0) { $0 + $1.workedSeconds() }), emptyText: "No hours")
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(month.formatted(.dateTime.month(.wide).year(), in: tz)).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openWeek) { HoursWeekView(weekStart: $0, within: span) }
        .onAppear { if DemoMode.flag("-WorklogOpenHoursWeek"), openWeek == nil { openWeek = weeks.first } }
    }
}

struct HoursWeekView: View {
    @EnvironmentObject var store: WorkStore
    let weekStart: Date
    let within: DateInterval
    @State private var openDay: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let cal = TripCalendar.calendar(tz)
        let weekShifts = store.shifts.filter { within.contains($0.start) && TripCalendar.weekStart(of: $0.start, timeZoneID: tz) == weekStart }
        let allDays = TripCalendar.days(inWeek: weekStart, timeZoneID: tz)
        let days = allDays.filter { within.contains($0) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HoursHeader(seconds: weekShifts.reduce(0) { $0 + $1.workedSeconds() }, caption: "worked this week")
                ForEach(days, id: \.self) { day in
                    let dayShifts = weekShifts.filter { cal.isDate($0.start, inSameDayAs: day) }
                    Button { openDay = day } label: {
                        LogFolderRow(title: day.formatted(.dateTime.weekday(.wide), in: tz),
                                     subtitle: day.formatted(.dateTime.day().month(.wide).year(), in: tz) + (dayShifts.isEmpty ? "" : " · \(dayShifts.count) shift\(dayShifts.count == 1 ? "" : "s")"),
                                     count: dayShifts.count, highlight: cal.isDateInToday(day) ? "Today" : nil,
                                     amount: hoursText(dayShifts.reduce(0) { $0 + $1.workedSeconds() }), emptyText: "No hours")
                    }.buttonStyle(.plain).disabled(dayShifts.isEmpty)
                }
                if days.count < 7 { Text("The rest of this week is in the next or previous month.").font(.footnote).foregroundStyle(Theme.textTertiary) }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Mon \(weekStart.formatted(.dateTime.day().month(), in: tz)) – Sun \((allDays.last ?? weekStart).formatted(.dateTime.day().month(), in: tz))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { HoursDayView(day: $0) }
        .onAppear { if DemoMode.flag("-WorklogOpenHoursDay"), openDay == nil { openDay = days.last { d in weekShifts.contains { cal.isDate($0.start, inSameDayAs: d) } } } }
    }
}

struct HoursDayView: View {
    @EnvironmentObject var store: WorkStore
    let day: Date
    @State private var editing: WorkShift?
    @State private var pendingDelete: WorkShift?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let cal = TripCalendar.calendar(tz)
        let dayShifts = store.shifts.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HoursHeader(seconds: dayShifts.reduce(0) { $0 + $1.workedSeconds() }, caption: "worked")
                if dayShifts.isEmpty { Text("No hours on this day.").foregroundStyle(Theme.textSecondary) }
                ForEach(dayShifts) { shift in
                    HStack(spacing: 10) {
                        Button { editing = shift } label: { ShiftRow(shift: shift, tz: tz) }.buttonStyle(.plain)
                        DeleteIconButton { pendingDelete = shift }
                    }.cardStyle(padding: 14)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(), in: tz)).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ShiftEditorView(existing: $0) }
        .alert("Delete these hours?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { shift in
            Button("Delete hours", role: .destructive) { do { try store.deleteShift(shift.id) } catch { store.error = error.localizedDescription } }
            Button("Cancel", role: .cancel) {}
        } message: { shift in Text(deleteMessage(shift)) }
    }
    func deleteMessage(_ shift: WorkShift) -> String {
        let started: String = shift.start.formatted(date: .abbreviated, time: .shortened)
        let finished: String = shift.end?.formatted(date: .omitted, time: .shortened) ?? ""
        let worked: String = hoursText(shift.workedSeconds())
        return "\(started) – \(finished)\n\(worked) · \(shift.place.rawValue)\n\nThis can't be undone."
    }
}

private struct HoursHeader: View {
    let seconds: TimeInterval
    let caption: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(hoursText(seconds)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
        }.padding(.bottom, 6)
    }
}

/// Add hours you forgot to clock, or correct a shift.
struct ShiftEditorView: View {
    let existing: WorkShift?
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var finish = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var breakMinutes = "30"
    @State private var place = LastShiftPlace.value
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Finish", selection: $finish, in: start..., displayedComponents: [.date, .hourAndMinute])
                    ThemedTextField(label: "Breaks (minutes)", prompt: "e.g. 30", text: $breakMinutes, keyboard: .numberPad)
                    DropdownField(label: "Where you worked", selection: $place, options: ShiftPlace.allCases, title: { $0.rawValue })
                    ThemedTextField(label: "Notes", prompt: "Optional — job or customer", text: $notes)
                    let minutes = Double(breakMinutes) ?? 0
                    Text("Hours worked: " + hoursText(max(0, finish.timeIntervalSince(start) - minutes * 60)))
                        .font(.headline).foregroundStyle(Theme.mint)
                    if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Theme.warning) }
                    Button { save() } label: { Label("Save hours", systemImage: "checkmark") }.buttonStyle(PrimaryButtonStyle())
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "Add hours" : "Edit hours").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard let s = existing else { return }
                start = s.start; finish = s.end ?? Date(); place = s.place; notes = s.notes
                breakMinutes = String(Int((s.breakSeconds() / 60).rounded()))
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }
    func save() {
        guard let minutes = Int(breakMinutes.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : breakMinutes.trimmingCharacters(in: .whitespaces)), minutes >= 0 else { error = "Enter break minutes as a whole number."; return }
        guard finish > start else { error = "The finish must be after the start."; return }
        guard Double(minutes * 60) < finish.timeIntervalSince(start) else { error = "Breaks can't be as long as the shift."; return }
        var shift = existing ?? WorkShift(start: start, timeZoneID: store.data.schedule.timeZoneID, manual: true)
        let keepBreaks = existing.map { Int(($0.breakSeconds() / 60).rounded()) == minutes && $0.start == start && $0.end == finish } ?? false
        shift.start = start; shift.end = finish; shift.place = place; shift.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keepBreaks {
            // A single break placed mid-shift; only its length matters for hours worked.
            let middle = start.addingTimeInterval((finish.timeIntervalSince(start) - Double(minutes * 60)) / 2)
            shift.breaks = minutes > 0 ? [DateInterval(start: middle, duration: Double(minutes * 60))] : []
        }
        if existing != nil && !keepBreaks { shift.manual = true }
        guard store.saveShift(shift) else { error = "The hours were not saved. Check device storage."; return }
        LastShiftPlace.value = place
        dismiss()
    }
}
