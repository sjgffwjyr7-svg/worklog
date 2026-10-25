import SwiftUI
import AppIntents
import VisionKit
import PDFKit
import UniformTypeIdentifiers

/// Adds up AUD amounts stored as text, without floating-point rounding.
func audTotal(_ values: [String]) -> String {
    let value = values.reduce(Decimal.zero) { $0 + (Decimal(string: $1, locale: Locale(identifier: "en_US_POSIX")) ?? 0) }
    let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "AUD"; formatter.locale = Locale(identifier: "en_AU")
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0.00"
}

func receiptCount(_ n: Int) -> String { n == 1 ? "1 receipt" : "\(n) receipts" }

/// The Receipts tab: the current financial year by month, with earlier years kept in year folders.
/// On 1 July the page starts the new year empty; nothing is deleted.
struct InvoicesView: View {
    @EnvironmentObject var store: WorkStore
    @State private var adding = false
    @State private var openMonth: Date?
    @State private var openYear: Int?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let current = FinancialYear.startYear(for: Date(), timeZone: tz)
        let span = FinancialYear.interval(current, timeZone: tz)
        let receipts = store.data.invoices.filter { span.contains($0.date) }
        let months = TripCalendar.monthStarts(receipts.map(\.date), timeZoneID: tz)
        let otherYears = Set(store.data.invoices.map { FinancialYear.startYear(for: $0.date, timeZone: tz) }).subtracting([current]).sorted(by: >)
        let thisMonth = TripCalendar.monthStart(of: Date(), timeZoneID: tz)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            FieldLabel("This financial year · AUD")
                            Spacer()
                            StatChip(icon: "calendar", text: "FY \(String(current))–\(String(current + 1).suffix(2))", color: Theme.accent)
                        }
                        Text(audTotal(receipts.map { $0.total }))
                            .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                            .minimumScaleFactor(0.5).lineLimit(1)
                        HStack(spacing: 10) {
                            StatChip(icon: "percent", text: "GST \(audTotal(receipts.map { $0.gst }))", color: Theme.mint)
                            StatChip(icon: "doc.text.fill", text: receiptCount(receipts.count), color: Theme.accent)
                        }
                        Text("1 July \(String(current)) – 30 June \(String(current + 1)). A new year starts fresh on 1 July; earlier years stay in Previous years. Includes private and reimbursed purchases, so it is not a deduction total.")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Button { adding = true } label: { Label("Scan tax receipt", systemImage: "doc.viewfinder") }
                        .buttonStyle(PrimaryButtonStyle()).buttonRow()
                }
                if receipts.isEmpty {
                    ContentUnavailableView("No receipts this year", systemImage: "doc.text.viewfinder", description: Text("Scan a tax invoice into a PDF and keep its supplier, date and amount together."))
                        .listRowBackground(Color.clear)
                } else {
                    Section("This year by month") {
                        ForEach(months, id: \.self) { month in
                            let monthReceipts = receiptsIn(TripCalendar.monthInterval(of: month, timeZoneID: tz))
                            Button { openMonth = month } label: {
                                LogFolderRow(title: month.formatted(.dateTime.month(.wide).year(), in: tz), subtitle: receiptCount(monthReceipts.count),
                                             count: monthReceipts.count, highlight: month == thisMonth ? "This month" : nil,
                                             amount: audTotal(monthReceipts.map { $0.total }), emptyText: "No receipts")
                            }.buttonStyle(.plain).buttonRow()
                        }
                    }
                }
                if !otherYears.isEmpty {
                    Section("Previous years") {
                        ForEach(otherYears, id: \.self) { year in
                            let yearReceipts = receiptsIn(FinancialYear.interval(year, timeZone: tz))
                            Button { openYear = year } label: {
                                LogFolderRow(title: "FY \(String(year))–\(String(year + 1).suffix(2))", subtitle: "1 July \(String(year)) – 30 June \(String(year + 1)) · " + receiptCount(yearReceipts.count),
                                             count: yearReceipts.count, amount: audTotal(yearReceipts.map { $0.total }), emptyText: "No receipts")
                            }.buttonStyle(.plain).buttonRow()
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Receipts")
            .sheet(isPresented: $adding) { AddInvoiceView() }
            .navigationDestination(item: $openMonth) { ReceiptMonthView(month: $0) }
            .navigationDestination(item: $openYear) { ReceiptYearView(year: $0) }
            .onAppear {
                if DemoMode.flag("-WorklogShowAddReceipt") { adding = true }
                if DemoMode.flag("-WorklogOpenReceiptMonth"), openMonth == nil { openMonth = months.first }
            }
        }
    }
    func receiptsIn(_ span: DateInterval) -> [Invoice] { store.data.invoices.filter { $0.date >= span.start && $0.date < span.end } }
}

private struct MoneyHeader: View {
    let amount: String
    let caption: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(amount).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
        }.padding(.bottom, 6)
    }
}

struct ReceiptRow: View {
    let invoice: Invoice
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.supplier).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(invoice.category ?? "Uncategorised").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Text(invoice.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(Theme.textTertiary)
            }.layoutPriority(1)
            Spacer(minLength: 8)
            if let amount = Double(invoice.total) { Text(amount, format: .currency(code: "AUD")).font(.headline.monospacedDigit()).foregroundStyle(Theme.mint).fixedSize() }
        }.contentShape(Rectangle())
    }
}

/// A previous financial year: its months.
struct ReceiptYearView: View {
    @EnvironmentObject var store: WorkStore
    let year: Int
    @State private var openMonth: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = FinancialYear.interval(year, timeZone: tz)
        let receipts = store.data.invoices.filter { span.contains($0.date) }
        let months = TripCalendar.monthStarts(receipts.map(\.date), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                MoneyHeader(amount: audTotal(receipts.map { $0.total }), caption: receiptCount(receipts.count))
                ForEach(months, id: \.self) { month in
                    let m = TripCalendar.monthInterval(of: month, timeZoneID: tz)
                    let monthReceipts = receipts.filter { $0.date >= m.start && $0.date < m.end }
                    Button { openMonth = month } label: {
                        LogFolderRow(title: month.formatted(.dateTime.month(.wide).year(), in: tz), subtitle: receiptCount(monthReceipts.count),
                                     count: monthReceipts.count, amount: audTotal(monthReceipts.map { $0.total }), emptyText: "No receipts")
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("FY \(String(year))–\(String(year + 1).suffix(2))").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openMonth) { ReceiptMonthView(month: $0) }
    }
}

/// A month's receipts by Monday–Sunday week.
struct ReceiptMonthView: View {
    @EnvironmentObject var store: WorkStore
    let month: Date
    @State private var openWeek: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let span = TripCalendar.monthInterval(of: month, timeZoneID: tz)
        let receipts = store.data.invoices.filter { $0.date >= span.start && $0.date < span.end }
        let weeks = TripCalendar.weekStarts(receipts.map(\.date), timeZoneID: tz)
        let thisWeek = TripCalendar.weekStart(of: Date(), timeZoneID: tz)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                MoneyHeader(amount: audTotal(receipts.map { $0.total }), caption: receiptCount(receipts.count))
                ForEach(weeks, id: \.self) { week in
                    let weekReceipts = receipts.filter { TripCalendar.weekStart(of: $0.date, timeZoneID: tz) == week }
                    let last = TripCalendar.days(inWeek: week, timeZoneID: tz).last ?? week
                    let partWeek = !span.contains(week) || !span.contains(last)
                    Button { openWeek = week } label: {
                        LogFolderRow(title: week.formatted(.dateTime.day().month(), in: tz) + " – " + last.formatted(.dateTime.day().month(), in: tz),
                                     subtitle: (partWeek ? "Part week · " : "Mon to Sun · ") + receiptCount(weekReceipts.count),
                                     count: weekReceipts.count, highlight: week == thisWeek ? "This week" : nil,
                                     amount: audTotal(weekReceipts.map { $0.total }), emptyText: "No receipts")
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(month.formatted(.dateTime.month(.wide).year(), in: tz)).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openWeek) { ReceiptWeekView(weekStart: $0, within: span) }
        .onAppear { if DemoMode.flag("-WorklogOpenReceiptWeek"), openWeek == nil { openWeek = weeks.first } }
    }
}

/// A week's days (only those in the month it was opened from).
struct ReceiptWeekView: View {
    @EnvironmentObject var store: WorkStore
    let weekStart: Date
    let within: DateInterval
    @State private var openDay: Date?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let cal = TripCalendar.calendar(tz)
        let receipts = store.data.invoices.filter { $0.date >= within.start && $0.date < within.end && TripCalendar.weekStart(of: $0.date, timeZoneID: tz) == weekStart }
        let allDays = TripCalendar.days(inWeek: weekStart, timeZoneID: tz)
        let days = allDays.filter { within.contains($0) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                MoneyHeader(amount: audTotal(receipts.map { $0.total }), caption: "spent this week")
                ForEach(days, id: \.self) { day in
                    let dayReceipts = receipts.filter { cal.isDate($0.date, inSameDayAs: day) }
                    Button { openDay = day } label: {
                        LogFolderRow(title: day.formatted(.dateTime.weekday(.wide), in: tz),
                                     subtitle: day.formatted(.dateTime.day().month(.wide).year(), in: tz) + (dayReceipts.isEmpty ? "" : " · " + receiptCount(dayReceipts.count)),
                                     count: dayReceipts.count, highlight: cal.isDateInToday(day) ? "Today" : nil,
                                     amount: audTotal(dayReceipts.map { $0.total }), emptyText: "No receipts")
                    }.buttonStyle(.plain).disabled(dayReceipts.isEmpty)
                }
                if days.count < 7 { Text("The rest of this week is in the next or previous month.").font(.footnote).foregroundStyle(Theme.textTertiary) }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Mon \(weekStart.formatted(.dateTime.day().month(), in: tz)) – Sun \((allDays.last ?? weekStart).formatted(.dateTime.day().month(), in: tz))")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { ReceiptDayView(day: $0) }
        .onAppear {
            if DemoMode.flag("-WorklogOpenReceiptDay"), openDay == nil { openDay = days.last { d in receipts.contains { cal.isDate($0.date, inSameDayAs: d) } } }
        }
    }
}

/// A day's receipts, each with open and delete.
struct ReceiptDayView: View {
    @EnvironmentObject var store: WorkStore
    let day: Date
    @State private var pendingDelete: Invoice?
    var tz: String { store.data.schedule.timeZoneID }
    var body: some View {
        let cal = TripCalendar.calendar(tz)
        let receipts = store.data.invoices.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                MoneyHeader(amount: audTotal(receipts.map { $0.total }), caption: receiptCount(receipts.count))
                if receipts.isEmpty { Text("No receipts on this day.").foregroundStyle(Theme.textSecondary) }
                ForEach(receipts) { invoice in
                    HStack(spacing: 10) {
                        NavigationLink { InvoiceDetailView(initialInvoice: invoice) } label: { ReceiptRow(invoice: invoice) }.buttonStyle(.plain)
                        DeleteIconButton { pendingDelete = invoice }
                    }.cardStyle(padding: 14)
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(), in: tz)).navigationBarTitleDisplayMode(.inline)
        .alert("Delete this receipt?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { invoice in
            Button("Delete receipt", role: .destructive) { do { try store.deleteInvoice(invoice.id) } catch { store.error = error.localizedDescription } }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0.deleteSummary) }
    }
}

struct AddInvoiceView: View {
    var existing: Invoice? = nil
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = false
    @State private var initialized = false
    @State private var recognizing = false
    @State private var items = ""
    @State private var recognizedText = ""
    @State private var reviewed = false
    @State private var importing = false
    @State private var pdf: Data?
    @State private var category = ExpenseCategories.all.last!
    @State private var customCategory = ""
    @State private var abn = ""
    @State private var workPercent = ""
    @State private var reimbursed = ""
    @State private var taxStatus = "Needs accountant review"
    @State private var supplier = ""
    @State private var number = ""
    @State private var date = Date()
    @State private var total = ""
    @State private var gst = ""
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if VNDocumentCameraViewController.isSupported {
                        Button { scanner = true } label: { Label(pdf == nil ? "Scan tax receipt" : "Replace scan", systemImage: "doc.text.viewfinder") }
                            .buttonStyle(PrimaryButtonStyle()).disabled(recognizing).buttonRow()
                    }
                    Button { importing = true } label: { Label("Import photo or PDF", systemImage: "folder") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).disabled(recognizing).buttonRow()
                    if let pdf { Label("\(PDFDocument(data: pdf)?.pageCount ?? 0) pages ready", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint); PDFPreview(data: pdf).frame(height: 230) }
                } footer: { Text("The camera detects, crops and straightens the receipt. Text is read on this iPhone after capture. Check suggested items, date, total and GST before saving. Unread amounts stay blank; GST is never calculated from the total.") }
                if recognizing { ProgressView("Reading receipt on this iPhone…").tint(Theme.accent) }
                Section("Items purchased") {
                    TextEditor(text: $items).frame(minHeight: 120).scrollContentBackground(.hidden)
                        .padding(8).background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("One line per item: description | line total AUD. Correct missed items, quantities, discounts and prices against the original.").font(.caption)
                    DisclosureGroup("Recognized receipt text") { Text(recognizedText.isEmpty ? "No text recognized" : recognizedText).font(.caption).textSelection(.enabled) }
                }
                Section("Receipt details") {
                    VStack(spacing: 14) {
                        ThemedTextField(label: "Supplier", prompt: "e.g. Bunnings Dubbo", text: $supplier)
                        ThemedTextField(label: "Invoice number", prompt: "Optional", text: $number)
                        HStack(spacing: 12) {
                            ThemedTextField(label: "Total AUD", prompt: "0.00", text: $total, keyboard: .decimalPad)
                            ThemedTextField(label: "GST AUD", prompt: "Optional", text: $gst, keyboard: .decimalPad)
                        }
                        ThemedTextField(label: "Notes", prompt: "Optional", text: $notes, multiline: true)
                    }.padding(.vertical, 6)
                    DatePicker("Invoice date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    VStack(spacing: 14) {
                        DropdownField(label: "Category", selection: $category, options: ExpenseCategories.all, title: { $0 })
                        ThemedTextField(label: "Custom category / description", prompt: "Optional", text: $customCategory)
                        ThemedTextField(label: "Supplier ABN", prompt: "If shown on the receipt", text: $abn, keyboard: .numberPad)
                        HStack(spacing: 12) {
                            ThemedTextField(label: "Work use %", prompt: "Blank if unsure", text: $workPercent, keyboard: .decimalPad)
                            ThemedTextField(label: "Reimbursed AUD", prompt: "0.00", text: $reimbursed, keyboard: .decimalPad)
                        }
                        DropdownField(label: "Accountant review", selection: $taxStatus, options: ["Needs accountant review", "Proposed claim — unconfirmed", "Exclude / private"], title: { $0 })
                    }.padding(.vertical, 6)
                } header: { Text("Tax classification") } footer: {
                    Text("Categories and GST entries do not confirm a deduction or GST credit. Your accountant reviews eligibility and private-use adjustments.")
                }
                Section {
                    Toggle("I checked the items, date, total and GST", isOn: $reviewed)
                }
                if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Theme.warning) }
            }.themedForm().navigationTitle(existing == nil ? "Tax receipt" : "Edit tax receipt").navigationBarTitleDisplayMode(.inline).onAppear {
                guard !initialized else { return }; initialized = true
                if existing == nil && VNDocumentCameraViewController.isSupported { scanner = true }
                if let i = existing, pdf == nil {
                    items = i.items ?? ""; recognizedText = i.recognizedText ?? ""; reviewed = i.receiptReviewed ?? false
                    supplier = i.supplier; number = i.number; date = i.date; total = i.total; gst = i.gst; notes = i.notes
                    category = i.category ?? ExpenseCategories.all.last!; customCategory = i.customCategory ?? ""; abn = i.abn ?? ""
                    workPercent = i.workPercent ?? ""; reimbursed = i.reimbursed ?? ""; taxStatus = i.taxStatus ?? "Needs accountant review"
                    do { pdf = try Data(contentsOf: store.pdfURL(i)) } catch { self.error = error.localizedDescription }
                }
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold).disabled(recognizing || !reviewed || total.isEmpty || pdf == nil || supplier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.fullScreenCover(isPresented: $scanner) {
                InvoiceScanner(completed: { pdf = $0; scanner = false; recognize($0) }, cancelled: { scanner = false }, failed: { error = $0; scanner = false }).ignoresSafeArea()
            }.fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bytes = try Data(contentsOf: url)
                    guard bytes.count <= 50 * 1024 * 1024 else { error = "Use a file smaller than 50 MB."; return }
                    if let document = PDFDocument(data: bytes), document.pageCount > 0 { pdf = bytes }
                    else if let image = UIImage(data: bytes), let compressed = ReceiptCompression.pdf(from: [image]) { pdf = compressed }
                    else { error = "This photo or PDF could not be opened."; return }
                    if let pdf { recognize(pdf) }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func recognize(_ bytes: Data) {
        recognizing = true; reviewed = false; error = nil
        Task { @MainActor in
            defer { recognizing = false }
            do {
                let text = try await ReceiptOCR.recognize(bytes)
                recognizedText = text
                let suggestion = ReceiptSuggestion.parse(text)
                supplier = suggestion.supplier; total = suggestion.total; gst = suggestion.gst; items = suggestion.items
                if let found = suggestion.date { date = found }
                error = "Check all suggested fields. If the receipt has no time, set the transaction time manually. Missing or unclear details must be entered before saving."
            } catch { self.error = "Text could not be read. The scan is kept; enter its details manually. " + error.localizedDescription }
        }
    }
    func save() {
        guard let pdf, reviewed, !total.isEmpty else { return }
        for amount in [total, gst] where !amount.isEmpty { guard let number = Double(amount), number.isFinite, number >= 0 else { error = "Enter valid non-negative invoice amounts."; return } }
        if let tax = Double(gst), let amount = Double(total), tax > amount { error = "GST cannot exceed the total."; return }
        if !workPercent.isEmpty { guard let value = Double(workPercent), value.isFinite, (0...100).contains(value) else { error = "Use percentage must be between 0 and 100."; return } }
        if !reimbursed.isEmpty { guard let value = Double(reimbursed), value.isFinite, value >= 0 else { error = "Enter a valid reimbursement amount."; return } }
        var invoice = Invoice(supplier: supplier.trimmingCharacters(in: .whitespacesAndNewlines), number: number, date: date, total: total, gst: gst, notes: notes, pdfFilename: "invoice-\(UUID().uuidString).pdf")
        invoice.items = items; invoice.recognizedText = recognizedText; invoice.receiptReviewed = reviewed
        invoice.category = category; invoice.customCategory = customCategory; invoice.abn = abn
        invoice.workPercent = workPercent; invoice.reimbursed = reimbursed; invoice.taxStatus = taxStatus
        if let existing { invoice.id = existing.id; invoice.captured = existing.captured }
        let stamp = ISO8601DateFormatter().string(from: invoice.date).replacingOccurrences(of: ":", with: "-")
        invoice.pdfFilename = "receipt-\(stamp)-\(invoice.id.uuidString)-\(UUID().uuidString).pdf"
        do { try store.saveInvoice(invoice, pdf: pdf); dismiss() } catch { self.error = error.localizedDescription }
    }
}
struct InvoiceDetailView: View {
    @EnvironmentObject var store: WorkStore
    let initialInvoice: Invoice
    var invoice: Invoice { store.data.invoices.first { $0.id == initialInvoice.id } ?? initialInvoice }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var pdf: Data?
    @State private var share: ShareFiles?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invoice.supplier).font(.title2.weight(.bold))
                    if let amount = Double(invoice.total) { Text(amount, format: .currency(code: "AUD")).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.mint) }
                }.padding(.vertical, 6)
                LabeledContent("Date", value: invoice.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Recorded", value: invoice.captured.formatted(date: .abbreviated, time: .shortened))
                if let items = invoice.items, !items.isEmpty { Text(items) }
                LabeledContent("Invoice number", value: invoice.number)
                LabeledContent("Total AUD", value: invoice.total.isEmpty ? "Not entered" : invoice.total)
                LabeledContent("GST AUD", value: invoice.gst.isEmpty ? "Not entered" : invoice.gst)
                LabeledContent("Category", value: invoice.category ?? "Other / custom category")
                LabeledContent("Review", value: invoice.taxStatus ?? "Needs accountant review")
                if !invoice.notes.isEmpty { Text(invoice.notes) }
            }
            Section {
                Button { editing = true } label: { Label("Edit receipt and tax details", systemImage: "pencil") }
                    .buttonStyle(PrimaryButtonStyle()).buttonRow()
            }
            if let pdf { Section("Original") { PDFPreview(data: pdf).frame(height: 430) } }
            Section {
                Button { share = ShareFiles(urls: [store.pdfURL(invoice)]) } label: { Label("Save to Files / Qfile Pro", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
            } footer: { Text("Choose Save to Files or Qfile Pro, then complete the upload to your QNAP. Check Qfile Pro for upload success.") }
            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete receipt", systemImage: "trash") }
                    .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.danger.opacity(0.16)), foreground: Theme.danger)).buttonRow()
            }
        }
        .alert("Delete this receipt?", isPresented: $confirmDelete) {
            Button("Delete receipt", role: .destructive) {
                do { try store.deleteInvoice(invoice.id); dismiss() } catch { store.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(invoice.deleteSummary) }
        .themedForm().navigationTitle("Receipt").navigationBarTitleDisplayMode(.inline).sheet(isPresented: $editing, onDismiss: { pdf = try? Data(contentsOf: store.pdfURL(invoice)) }) { AddInvoiceView(existing: invoice) }.task { do { pdf = try Data(contentsOf: store.pdfURL(invoice)) } catch { store.error = "The original invoice could not be opened: \(error.localizedDescription)" } }
        .sheet(item: $share) { ShareSheet(urls: $0.urls) }
    }
}

struct StorageView: View {
    @EnvironmentObject var store: WorkStore
    @State private var share: ShareFiles?
    @State private var importing = false
    @State private var notice = ""
    @State private var exportYear = FinancialYear.startYear()
    @State private var backupPassword: BackupPasswordView.Mode?
    @State private var openTests = false
    var thisYearKm: Double {
        let tz = store.data.schedule.timeZoneID
        let span = FinancialYear.interval(FinancialYear.startYear(for: Date(), timeZone: tz), timeZone: tz)
        return TripCalendar.workKm(store.data.trips.filter { span.contains($0.start) })
    }
    var exportYears: [Int] {
        Array(Set([FinancialYear.startYear(), FinancialYear.startYear() - 1] + store.data.trips.map { FinancialYear.startYear(for: $0.start) } + store.data.invoices.map { FinancialYear.startYear(for: $0.date) })).sorted(by: >)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { TripLogView() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "list.bullet.rectangle.portrait.fill").foregroundStyle(Theme.accent)
                                .frame(width: 38, height: 38).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trip log & kilometre totals").font(.headline)
                                Text("This financial year: " + thisYearKm.formatted(.number.precision(.fractionLength(1))) + " work km").font(.caption).foregroundStyle(Theme.mint)
                            }
                        }
                    }
                } header: { Text("Logbook") } footer: { Text("Totals by financial year, month, week and day.") }
                Section {
                    DropdownField(label: "Financial year", selection: $exportYear, options: exportYears,
                                  title: { "FY \(String($0))–\(String($0 + 1).suffix(2)) · 1 July \(String($0)) – 30 June \(String($0 + 1))" }).padding(.vertical, 6)
                    let checklist = store.atoChecklist(year: exportYear)
                    if checklist.isEmpty {
                        Label("ATO record check: nothing missing", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.mint)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("ATO record check: \(checklist.count) to fix", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Theme.warning)
                            ForEach(checklist, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(Theme.warning)
                                    Text(item).font(.footnote).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Text("Fix vehicle details in Settings → Vehicles and odometer readings in each trip.").font(.caption).foregroundStyle(Theme.textTertiary)
                        }.padding(.vertical, 4)
                    }
                    Button { do { share = ShareFiles(urls: try store.accountantExport(year: exportYear)) } catch { store.error = error.localizedDescription } } label: {
                        Label("Export for accountant", systemImage: "square.and.arrow.up")
                    }.buttonStyle(PrimaryButtonStyle()).buttonRow()
                } header: { Text("Accountant") } footer: {
                    Text("Exports the trip log (all vehicles and each vehicle), receipt register, notes and the original receipt PDFs for the year. Send them by email, AirDrop, Files or Qfile Pro.")
                }
                VehiclesSettingsSection()
                PlacesSettingsSection()
                AppLockSettings()
                Section {
                    NavigationLink { TestCentreView() } label: {
                        Label("Test centre — app checks & practice Siri", systemImage: "checkmark.seal")
                    }
                } header: { Text("Testing") }
                Section("On this iPhone") {
                    LabeledContent("Work trips", value: "\(store.data.trips.count)")
                    LabeledContent("Invoices", value: "\(store.data.invoices.count)")
                    let used = store.storageUsed()
                    LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: used.records + used.receipts, countStyle: .file))
                    Text("Trip records \(ByteCountFormatter.string(fromByteCount: used.records, countStyle: .file)) (compressed) · receipts \(ByteCountFormatter.string(fromByteCount: used.receipts, countStyle: .file))")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                    Text("Records and scanned receipts are kept in Worklog's private, encrypted storage on this iPhone. They can't be browsed from the Files app or a computer. No records expire automatically. Keep dated encrypted backups on your QNAP and another device for the period your accountant requires. Deleting the app removes local records.").font(.subheadline)
                }
                Section {
                    Button { backupPassword = .create } label: { Label("Save encrypted backup", systemImage: "lock.doc.fill") }
                        .buttonStyle(PrimaryButtonStyle()).buttonRow()
                    Button { importing = true } label: { Label("Restore an iOS backup", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PrimaryButtonStyle(fill: AnyShapeStyle(Theme.field), foreground: Theme.accent)).buttonRow()
                }
                Section("Siri commands") {
                    Text("Say: Start a supply pickup trip in Worklog. Siri asks for the starting odometer, then confirms the description and number.")
                    Text("Say: Start a work trip in Worklog. Siri asks for any trip purpose and the vehicle’s current odometer in kilometres, then reads both back before starting.")
                    Text("Say: Start a trip with my last description in Worklog to reuse it, or Set starting odometer in Worklog to correct the active trip.")
                    Text("Open Worklog once and allow precise location before testing Siri. iOS may require you to unlock the phone. Confirm while parked.").font(.footnote).foregroundStyle(.secondary)
                    ShortcutsLink()
                }
                Section("Home QNAP") {
                    Text("Use the share menu to save a backup or invoice to Files. In Qfile Pro, select your NAS and folder, then Upload → Other to choose the saved file.")
                    Text("QNAP is not directly connected. Transfers are manual and completed in Qfile Pro. Browser and native iOS backups use different formats.").font(.footnote).foregroundStyle(.secondary)
                    Link("QNAP upload instructions", destination: URL(string: "https://docs.qnap.com/application/qfile-pro/4.x/en-us/uploading-files-and-folders-ios-B6EF3FB6.html")!)
                }
                Section("Privacy") {
                    Text("No advertising, analytics or cloud account. The app requests camera access to scan invoices and location access to measure work trips. Scheduled monitoring retains positions only during recorded work trips.")
                }
                if !notice.isEmpty { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint) }
            }.themedForm().navigationTitle("Settings").sheet(item: $share) { ShareSheet(urls: $0.urls) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    do { try store.restoreBackup(url); notice = "Missing records restored. Existing records were kept." }
                    catch StoreError.passwordNeeded {
                        // Let the file picker finish closing before showing the password sheet.
                        Task { try? await Task.sleep(for: .milliseconds(500)); backupPassword = .unlock(url) }
                    }
                } catch { store.error = error.localizedDescription }
            }
            .navigationDestination(isPresented: $openTests) { TestCentreView() }
            .onAppear { if DemoMode.flag("-WorklogOpenTestCentre") { openTests = true } }
            .sheet(item: $backupPassword) { mode in
                BackupPasswordView(mode: mode) { password in
                    switch mode {
                    case .create: share = ShareFiles(urls: [try store.exportBackup(password: password)])
                    case .unlock(let url): try store.restoreBackup(url, password: password); notice = "Missing records restored. Existing records were kept."
                    }
                }
            }
        }
    }
}

/// Asks for the password that encrypts a new backup, or that opens an encrypted one.
struct BackupPasswordView: View {
    enum Mode: Identifiable {
        case create
        case unlock(URL)
        var id: String { if case .unlock(let url) = self { return url.absoluteString }; return "create" }
    }
    let mode: Mode
    let action: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    var creating: Bool { if case .create = mode { return true }; return false }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(creating ? "Your backup is encrypted with this password (AES-256). Store it somewhere safe: without it the backup can't be opened, and Worklog can't recover it."
                                   : "This backup is encrypted. Enter the password you set when you saved it.",
                          systemImage: "lock.shield.fill")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    ThemedTextField(label: "Backup password", prompt: creating ? "At least 8 characters" : "Password", text: $password, secure: true)
                    if creating { ThemedTextField(label: "Confirm password", prompt: "Type it again", text: $confirm, secure: true) }
                    if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Theme.warning) }
                    Button {
                        if creating && password.count < 8 { error = "Use at least 8 characters."; return }
                        if creating && password != confirm { error = "The passwords don't match."; return }
                        do { try action(password); dismiss() } catch { self.error = error.localizedDescription }
                    } label: { Label(creating ? "Encrypt and save" : "Restore backup", systemImage: creating ? "lock.fill" : "lock.open.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(password.isEmpty)
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(creating ? "Encrypted backup" : "Open backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}
