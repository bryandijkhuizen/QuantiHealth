import SwiftUI

@main
struct ProgressaNativeApp: App {
    @StateObject private var model = ProgressaModel()
    @AppStorage("progressa.theme") private var theme = ProgressaThemeMode.system.rawValue
    @AppStorage("progressa.accent") private var accent = ProgressaAccent.presets[0].id

    var body: some Scene {
        WindowGroup {
            ProgressaRootView()
                .environmentObject(model)
                .tint(ProgressaAccent.color(for: accent))
                .preferredColorScheme(ProgressaThemeMode(rawValue: theme)?.colorScheme)
                .task { await model.bootstrap() }
                .onOpenURL { model.handle(url: $0) }
        }
    }
}
