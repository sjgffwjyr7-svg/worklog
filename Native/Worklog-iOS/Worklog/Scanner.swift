import SwiftUI
import VisionKit
import Vision
import PDFKit
import UniformTypeIdentifiers

struct InvoiceScanner: UIViewControllerRepresentable {
    var completed: (Data) -> Void
    var cancelled: () -> Void
    var failed: (String) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: InvoiceScanner
        init(parent: InvoiceScanner) { self.parent = parent }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.cancelled() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.failed(error.localizedDescription) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.cancelled(); return }
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            guard let bytes = ReceiptCompression.pdf(from: pages) else { parent.failed("Could not save the scan. Try again."); return }
            parent.completed(bytes)
        }
    }
}
/// Scanned receipts are stored as compressed JPEG pages inside a PDF: pages are scaled to at most
/// 2,000 pixels on the long side (sharp enough to read and for text recognition) and JPEG-compressed.
/// A typical page drops from 1–3 MB to roughly 150–300 KB.
enum ReceiptCompression {
    static let maxPixels: CGFloat = 2000
    static let jpegQuality: CGFloat = 0.6
    /// 200 pixels per inch on the page, so a 2,000-pixel receipt prints at about 25 cm.
    static let pointsPerPixel: CGFloat = 72 / 200
    static func compressedPage(_ image: UIImage) -> UIImage? {
        let pixelWidth = image.size.width * image.scale, pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let factor = min(1, maxPixels / max(pixelWidth, pixelHeight))
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        // Re-reading the JPEG lets the PDF embed the compressed bytes as they are.
        return resized.jpegData(compressionQuality: jpegQuality).flatMap { UIImage(data: $0) }
    }
    static func pdf(from images: [UIImage]) -> Data? {
        let pages = images.compactMap(compressedPage)
        guard !pages.isEmpty, pages.count == images.count else { return nil }
        return UIGraphicsPDFRenderer(bounds: .zero).pdfData { context in
            for page in pages {
                let rect = CGRect(x: 0, y: 0, width: page.size.width * pointsPerPixel, height: page.size.height * pointsPerPixel)
                context.beginPage(withBounds: rect, pageInfo: [:])
                page.draw(in: rect)
            }
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if context.coordinator.data != data {
            uiView.document = PDFDocument(data: data)
            context.coordinator.data = data
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(data: data) }
    final class Coordinator {
        var data: Data
        init(data: Data) { self.data = data }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct ShareFiles: Identifiable { let id = UUID(); var urls: [URL] }


// Recognition runs locally after Apple's camera has cropped the document.
enum ReceiptOCR {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else { return "" }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                if let text = page.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                    pages.append(text); continue
                }
                let image = page.thumbnail(of: CGSize(width: 2200, height: 3000), for: .mediaBox)
                guard let cgImage = image.cgImage else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-AU", "en-US"]
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                // Join columns on the same visual row so description + price stay together.
                let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                var rows: [[VNRecognizedTextObservation]] = []
                for observation in observations {
                    if let last = rows.last, let anchor = last.first,
                       abs(anchor.boundingBox.midY - observation.boundingBox.midY) < min(anchor.boundingBox.height, observation.boundingBox.height) * 0.5 {
                        rows[rows.count - 1].append(observation)
                    } else { rows.append([observation]) }
                }
                pages.append(rows.map { row in row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") }.joined(separator: "\n"))
            }
            return pages.joined(separator: "\n")
        }.value
    }
}

struct ReceiptSuggestion {
    var supplier = ""
    var total = ""
    var gst = ""
    var items = ""
    var date: Date?
    static func parse(_ text: String) -> ReceiptSuggestion {
        var result = ReceiptSuggestion()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        result.supplier = lines.first ?? ""
        var items: [String] = []
        let price = try! NSRegularExpression(pattern: #"(?:\$\s*)?(-?\d[\d,]*\.\d{2})\s*(?:[A-Z*])?$"#)
        for line in lines {
            let lower = line.lowercased()
            // "Total includes GST $1.95" / "GST included in total" state the GST share, not the total.
            let statesGSTShare = lower.range(of: #"\bgst\b"#, options: .regularExpression) != nil
                && lower.range(of: #"\b(?:includes|including|included)\b"#, options: .regularExpression) != nil
            let isTotal = !statesGSTShare && lower.range(of: #"^(?:grand\s+total|total(?:\s+(?:aud|amount|due|incl\.?\s*gst))?|amount\s+(?:due|paid))\s*[:$\d ]"#, options: .regularExpression) != nil
            let isGST = lower.range(of: #"\b(?:gst|tax)\b"#, options: .regularExpression) != nil && !isTotal && !lower.contains("tax invoice")
            if let match = price.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(match.range(at: 1), in: line) {
                let value = String(line[range]).replacingOccurrences(of: ",", with: "")
                if isTotal { result.total = value }
                else if isGST { result.gst = value }
                else if lower.range(of: #"\b(subtotal|sub total|change|cash|eftpos|visa|mastercard|payment|balance|tender|saving|rounding|abn)\b"#, options: .regularExpression) == nil {
                    let name = String(line[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " $"))
                    if name.rangeOfCharacter(from: .letters) != nil { items.append(name + " | " + value) }
                }
            }
        }
        // Australian day/month order; do not silently invent a time from a date-only receipt.
        let dateRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2}[/-]\d{1,2}[/-](\d{4}|\d{2}))(?:\s+(\d{1,2}:\d{2}))?\b"#)
        if let match = dateRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) {
            let value = String(text[range]).replacingOccurrences(of: "-", with: "/")
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_AU"); formatter.isLenient = false
            let year = match.range(at: 2).length == 4 ? "yyyy" : "yy"
            formatter.dateFormat = match.range(at: 3).location == NSNotFound ? "d/M/\(year)" : "d/M/\(year) H:mm"
            result.date = formatter.date(from: value)
        }
        result.items = items.joined(separator: "\n")
        return result
    }
}
