import Foundation

// Screenshot support for CI. Debug builds launched with -DemoData use a throwaway store
// filled with sample records; -DemoTab N opens a tab; other -Demo... flags open sheets.
// Release builds ignore all of these. List the launches in screenshots.txt.
enum DemoMode {
    static func flag(_ name: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(name)
        #else
        return false
        #endif
    }
    static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-DemoTab"), i + 1 < args.count, let tab = Int(args[i + 1]) { return tab }
        #endif
        return 0
    }
    // Add: static func makeStore() -> Store { guard flag("-DemoData") else { return Store() } ... seed sample data ... }
}
