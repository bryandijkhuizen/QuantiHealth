import SwiftUI

enum ProgressaThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max.fill"; case .dark: "moon.stars.fill" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

struct ProgressaAccent: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color

    static let presets = [
        ProgressaAccent(id: "purple", title: "Purple", color: Color(red: 0.36, green: 0.18, blue: 1.00)),
        ProgressaAccent(id: "blue", title: "Blue", color: Color(red: 0.18, green: 0.42, blue: 1.00)),
        ProgressaAccent(id: "teal", title: "Teal", color: Color(red: 0.07, green: 0.70, blue: 0.66)),
        ProgressaAccent(id: "green", title: "Green", color: Color(red: 0.13, green: 0.77, blue: 0.37)),
        ProgressaAccent(id: "orange", title: "Orange", color: Color(red: 1.00, green: 0.48, blue: 0.10)),
        ProgressaAccent(id: "pink", title: "Pink", color: Color(red: 1.00, green: 0.24, blue: 0.55)),
        ProgressaAccent(id: "red", title: "Red", color: Color(red: 0.94, green: 0.27, blue: 0.27)),
    ]

    static func color(for id: String) -> Color { presets.first(where: { $0.id == id })?.color ?? presets[0].color }
}
