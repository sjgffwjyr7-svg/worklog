import SwiftUI
import LocalAuthentication
import UIKit

@MainActor protocol OwnerAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}

@MainActor final class AppleOwnerAuthenticator: OwnerAuthenticating {
    private let context = LAContext()
    func authenticate(reason: String) async throws -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: "WorklogAuthentication", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Set an iPhone passcode in Settings before enabling app lock."])
        }
        // iOS tries Face ID / Touch ID first; if the face isn't recognised it offers the iPhone passcode.
        context.localizedFallbackTitle = "Use iPhone passcode"
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func cancel() { context.invalidate() }
}

@MainActor final class AppLock: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var isUnlocked = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private struct Preference: Codable { var enabled: Bool }
    private let preferenceFile: URL
    private let makeAuthenticator: @MainActor () -> OwnerAuthenticating
    private var authenticator: OwnerAuthenticating?
    private var attempt = UUID()
    private var inBackground = false
    private var lockGeneration = UUID()
    private var autoPromptedGeneration: UUID?
    var canShowRecords: Bool { !enabled || isUnlocked }

    init(preferenceFile: URL? = nil,
         makeAuthenticator: @escaping @MainActor () -> OwnerAuthenticating = { AppleOwnerAuthenticator() }) {
        self.preferenceFile = preferenceFile ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorklogSecurity/app-lock.json")
        self.makeAuthenticator = makeAuthenticator
        if FileManager.default.fileExists(atPath: self.preferenceFile.path) {
            do { enabled = try JSONDecoder().decode(Preference.self, from: Data(contentsOf: self.preferenceFile)).enabled }
            catch {
                enabled = true // A damaged/unreadable preference must not bypass the lock.
                message = "Security settings could not be read. Authenticate to open Worklog."
            }
        }
    }
    @discardableResult private func authenticate(reason: String) async -> Bool {
        guard !busy, !inBackground else { return false }
        busy = true; message = nil
        let id = UUID(); attempt = id
        let auth = makeAuthenticator(); authenticator = auth
        do {
            let success = try await auth.authenticate(reason: reason)
            guard attempt == id, !inBackground else { return false }
            busy = false; authenticator = nil
            if !success { message = "Worklog remains locked. Try Face ID or your device passcode." }
            return success
        } catch {
            guard attempt == id else { return false }
            busy = false; authenticator = nil
            message = "Authentication was not completed. Try again using Face ID or your device passcode."
            return false
        }
    }
    func unlock() async {
        guard enabled, !isUnlocked else { return }
        let generation = lockGeneration
        if await authenticate(reason: "Unlock your Worklog trips and invoices."), !inBackground, generation == lockGeneration { isUnlocked = true }
    }
    /// Shows Face ID as soon as Worklog opens or returns while locked. It asks once per lock, so cancelling
    /// the prompt (which briefly makes the app inactive) doesn't bring it straight back; the Unlock button retries.
    func autoUnlockIfNeeded() async {
        guard enabled, !isUnlocked, !busy, !inBackground, autoPromptedGeneration != lockGeneration else { return }
        autoPromptedGeneration = lockGeneration
        await unlock()
    }
    func setEnabled(_ value: Bool) async {
        guard value != enabled else { return }
        let generation = lockGeneration
        guard await authenticate(reason: value ? "Enable Face ID or passcode protection for Worklog." : "Turn off Worklog app lock.") else { return }
        guard !inBackground, generation == lockGeneration else { return }
        do {
            try FileManager.default.createDirectory(at: preferenceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Preference(enabled: value)).write(to: preferenceFile,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            enabled = value; isUnlocked = value
        } catch { message = "The security setting was not saved. The previous setting is still in effect." }
    }
    func lockNow() {
        lockGeneration = UUID()
        attempt = UUID(); authenticator?.cancel(); authenticator = nil
        busy = false; isUnlocked = false
    }
    func enteredBackground() { inBackground = true; lockNow() }
    func becameActive() { inBackground = false }
}

// A separate opaque window covers presented sheets as well as the main screen
// before iOS takes its app-switcher snapshot. It never becomes the key window.
@MainActor final class WorklogPrivacyShield {
    private var window: UIWindow?
    func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let cover = UIWindow(windowScene: scene)
        cover.frame = scene.coordinateSpace.bounds
        cover.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(); label.text = "Worklog"
        label.textAlignment = .center; label.font = .preferredFont(forTextStyle: .title2)
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor), label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)])
        cover.overrideUserInterfaceStyle = .dark
        cover.rootViewController = controller; cover.isUserInteractionEnabled = false
        cover.isHidden = false; window = cover
    }
    func hide() { window?.isHidden = true; window = nil }
}

struct WorklogGate: View {
    @EnvironmentObject var store: WorkStore
    @EnvironmentObject var lock: AppLock
    @Environment(\.scenePhase) private var phase
    @State private var shield = WorklogPrivacyShield()
    var body: some View {
        Group {
            if lock.canShowRecords {
                MainView()
                    .alert("Worklog", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                        Button("OK") { store.error = nil }
                    } message: { Text(store.error ?? "") }
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "faceid").font(.system(size: 64)).foregroundStyle(Theme.accent)
                    Text("Worklog is locked").font(.title2.bold())
                    Text("Unlock to view your trips and invoices.").foregroundStyle(.secondary)
                    Button { Task { await lock.unlock() } } label: {
                        Label(lock.busy ? "Authenticating…" : "Unlock Worklog", systemImage: "lock.open")
                    }.buttonStyle(PrimaryButtonStyle()).disabled(lock.busy).padding(.horizontal, 20)
                    Text("Face ID opens Worklog automatically. If your face isn't recognised, use your iPhone passcode.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let message = lock.message { Text(message).font(.footnote).multilineTextAlignment(.center) }
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            }
        }
        .onChange(of: phase, initial: true) { _, current in
            switch current {
            case .active:
                lock.becameActive(); shield.hide()
                Task { await lock.autoUnlockIfNeeded() }
            // Always cover the screen for the app switcher, even without app lock.
            case .inactive: shield.show()
            case .background:
                shield.show()
                lock.enteredBackground()
            @unknown default: shield.show(); lock.enteredBackground()
            }
        }
    }
}

struct AppLockSettings: View {
    @EnvironmentObject var lock: AppLock
    var body: some View {
        Section {
            Toggle("Face ID / device passcode", isOn: Binding(get: { lock.enabled }, set: { value in
                Task { await lock.setEnabled(value) }
            })).disabled(lock.busy)
            if lock.enabled { Button("Lock Worklog now") { lock.lockNow() } }
            else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.warning)
                    Text("App lock is off. Anyone holding your unlocked iPhone can open your trips and receipts. Turn on Face ID above.")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
            }
            if lock.busy { ProgressView("Authenticating…") }
            if let message = lock.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("App security") } footer: {
            Text("Unlock with Apple's Face ID, Touch ID or your device passcode. Worklog locks when it enters the background; scheduled trip recording continues. Save edits before switching apps. Exported files and copies in Files or QNAP have their own protection.")
        }
    }
}
