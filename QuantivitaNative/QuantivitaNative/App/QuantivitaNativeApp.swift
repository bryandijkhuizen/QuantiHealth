import SwiftUI

@main
struct QuantivitaNativeApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentColor") private var accentColor = "violet"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(QuantivitaAppearance.color(accentColor))
                .preferredColorScheme(QuantivitaAppearance.scheme(appearanceMode))
                .task { await model.bootstrap() }
                .onOpenURL { model.handle(url: $0) }
        }
    }
}
