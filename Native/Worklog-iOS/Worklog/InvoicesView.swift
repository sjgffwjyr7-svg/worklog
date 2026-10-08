import SwiftUI
import AppIntents
import VisionKit
import PDFKit
import UniformTypeIdentifiers

struct InvoicesView: View {
    @EnvironmentObject var store: WorkStore
    @State private var adding = false
    @State private var year = FinancialYear.startYear()
    var receipts: [Invoice] {
        let span = FinancialYear.interval(year, timeZone: store.data.schedule.timeZoneID)
        return store.data.invoices.filter { $0.date >= span.start && $0.date < span.end }.sorted { $0.date > $1.date }
    }
    var years: [Int] {
        Array(Set([year, FinancialYear.startYear(), FinancialYear.startYear() - 1] + store.data.invoices.map { FinancialYear.startYear(for: $0.date) })).sorted(by: >)
    }
    func sum(_ values: [String]) -> String {
        let value = values.reduce(Decimal.zero) { $0 + (Decimal(string: $1, locale: Locale(identifier: "en_US_POSIX")) ?? 0) }
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "AUD"; formatter.locale = Locale(identifier: "en_AU")
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "A$0.00"
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            FieldLabel("Total spent · AUD")
                            Spacer()
                            FinancialYearMenu(year: $year, years: years)
                        }
                        Text(sum(receipts.map { $0.total }))
                            .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                            .minimumScaleFactor(0.5).lineLimit(1)
                        HStack(spacing: 10) {
                            StatChip(icon: "percent", text: "GST \(sum(receipts.map { $0.gst }))", color: Theme.mint)
                            StatChip(icon: "doc.text.fill", text: "\(receipts.count) receipts", color: Theme.accent)
                        }
                        Text("Includes private and reimbursed purchases. It is not a deduction total.").font(.caption).foregroundStyle(Theme.textTertiary)
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
                    Section("Receipts") {
                        ForEach(receipts) { invoice in
                            NavigationLink { InvoiceDetailView(initialInvoice: invoice) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "doc.text.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                                        .frame(width: 40, height: 40).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(invoice.supplier).font(.headline).lineLimit(1)
                                        Text(invoice.category ?? "Uncategorised").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                        Text(invoice.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer(minLength: 8)
                                    if let amount = Double(invoice.total) { Text(amount, format: .currency(code: "AUD")).font(.headline.monospacedDigit()).foregroundStyle(Theme.mint) }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Receipts")
            .sheet(isPresented: $adding) { AddInvoiceView() }
            .onAppear { if DemoMode.flag("-WorklogShowAddReceipt") { adding = true } }
        }
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
                    else if let image = UIImage(data: bytes), let page = PDFPage(image: image) { let document = PDFDocument(); document.insert(page, at: 0); pdf = document.dataRepresentation() }
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
        }.themedForm().navigationTitle("Receipt").navigationBarTitleDisplayMode(.inline).sheet(isPresented: $editing, onDismiss: { pdf = try? Data(contentsOf: store.pdfURL(invoice)) }) { AddInvoiceView(existing: invoice) }.task { do { pdf = try Data(contentsOf: store.pdfURL(invoice)) } catch { store.error = "The original invoice could not be opened: \(error.localizedDescription)" } }
        .sheet(item: $share) { ShareSheet(urls: $0.urls) }
    }
}

struct StorageView: View {
    @EnvironmentObject var store: WorkStore
    @State private var share: ShareFiles?
    @State private var importing = false
    @State private var notice = ""
    var body: some View {
        NavigationStack {
            Form {
                VehiclesSettingsSection()
                AppLockSettings()
                Section("On this iPhone") {
                    LabeledContent("Work trips", value: "\(store.data.trips.count)")
                    LabeledContent("Invoices", value: "\(store.data.invoices.count)")
                    Text("Records and scanned PDFs live on this iPhone. GPS works without mobile data. No records expire automatically. Keep dated backups on your QNAP and another device for the period your accountant requires. Deleting the app removes local records.").font(.subheadline)
                }
                Section {
                    Button { do { share = ShareFiles(urls: [try store.exportBackup()]) } catch { store.error = error.localizedDescription } } label: { Label("Save full backup", systemImage: "externaldrive.fill.badge.checkmark") }
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
                do { try store.restoreBackup(result.get()); notice = "Missing records restored. Existing records were kept." } catch { store.error = error.localizedDescription }
            }
        }
    }
}
