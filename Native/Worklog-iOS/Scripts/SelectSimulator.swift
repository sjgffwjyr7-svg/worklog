// Runs with the Swift compiler included in Xcode; no Python or Homebrew needed.
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}
func invoke(_ arguments: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.standardOutput = pipe
    try process.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("xcrun \(arguments.joined(separator: " ")) failed.") }
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
    guard CommandLine.arguments.count == 2 else { fail("Expected the simctl list JSON path.") }
    let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard let list = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          let runtimes = list["runtimes"] as? [[String: Any]],
          let devices = list["devices"] as? [String: [[String: Any]]],
          let types = list["devicetypes"] as? [[String: Any]] else { fail("Cannot read Simulator inventory.") }
    let installed = runtimes.filter {
        ($0["isAvailable"] as? Bool == true) &&
        ($0["identifier"] as? String ?? "").contains(".iOS-") &&
        (Int(($0["version"] as? String ?? "0").split(separator: ".").first ?? "0") ?? 0) >= 17
    }.sorted {
        ($0["version"] as? String ?? "").compare($1["version"] as? String ?? "", options: .numeric) == .orderedDescending
    }
    guard let runtime = installed.first, let runtimeID = runtime["identifier"] as? String else {
        fail("No available iOS 17+ Simulator runtime. Install iOS in Xcode Settings > Components (Platforms in older Xcode).", code: 3)
    }
    // Reuse only our dedicated simulator, leaving other simulator data untouched.
    if let existing = devices[runtimeID]?.first(where: {
        ($0["name"] as? String ?? "").hasPrefix("Worklog iPhone") && $0["isAvailable"] as? Bool == true
    }), let id = existing["udid"] as? String {
        print(id)
        exit(0)
    }
    let phoneTypes = types.filter { ($0["name"] as? String ?? "").hasPrefix("iPhone") }
    let deviceType = phoneTypes.first { $0["name"] as? String == "iPhone 14 Pro" } ?? phoneTypes.last
    guard let type = deviceType, let typeID = type["identifier"] as? String,
          let name = type["name"] as? String else { fail("No iPhone Simulator device type is installed.") }
    print(try invoke(["simctl", "create", "Worklog \(name)", typeID, runtimeID]))
} catch { fail(error.localizedDescription) }
