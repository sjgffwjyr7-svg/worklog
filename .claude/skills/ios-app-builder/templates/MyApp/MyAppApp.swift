import SwiftUI

@main struct MyAppApp: App {
    var body: some Scene {
        WindowGroup { ContentView().tint(Theme.accent).preferredColorScheme(.dark) }
    }
}

struct ContentView: View {
    @State private var tab = DemoMode.initialTab
    @State private var choice = ""
    @State private var name = ""
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DropdownField("Job type", selection: $choice, options: ["", "Site visit", "Supply pickup"], placeholder: "Choose a job")
                        ThemedTextField(label: "Customer", prompt: "e.g. Smith Farms", text: $name)
                        StatChip(icon: "checkmark", text: "Template works", color: Theme.mint)
                        Button("Primary action") {}.buttonStyle(PrimaryButtonStyle())
                    }.padding(20)
                }.background(Theme.background).navigationTitle("Template")
            }.tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            Form { Section("Second") { Text("Second tab") } }.themedForm()
                .tabItem { Label("Second", systemImage: "gearshape.fill") }.tag(1)
        }
    }
}
