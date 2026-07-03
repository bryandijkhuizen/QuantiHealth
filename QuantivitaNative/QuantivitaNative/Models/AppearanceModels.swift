import SwiftUI

enum QuantivitaAppearance {
    struct Accent: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    static let accents = [
        Accent(id: "violet", name: "Violet", color: Color(red: 0.40, green: 0.29, blue: 0.92)),
        Accent(id: "indigo", name: "Indigo", color: Color(red: 0.25, green: 0.37, blue: 0.90)),
        Accent(id: "cyan", name: "Cyan", color: Color(red: 0.04, green: 0.67, blue: 0.78)),
        Accent(id: "lime", name: "Lime", color: Color(red: 0.45, green: 0.72, blue: 0.15)),
        Accent(id: "orange", name: "Orange", color: Color(red: 0.95, green: 0.43, blue: 0.10)),
        Accent(id: "rose", name: "Rose", color: Color(red: 0.91, green: 0.25, blue: 0.43)),
    ]

    static func color(_ id: String) -> Color { accents.first(where: { $0.id == id })?.color ?? accents[0].color }
    static func scheme(_ mode: String) -> ColorScheme? {
        switch mode { case "light": .light; case "dark": .dark; default: nil }
    }
}
