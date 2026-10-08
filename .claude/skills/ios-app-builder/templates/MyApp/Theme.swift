import SwiftUI

// Shared design kit: dark theme, amber/mint accents, drop-down fields, primary buttons, stat chips.
// Copy into a new app as Theme.swift and add it to the app target.

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
