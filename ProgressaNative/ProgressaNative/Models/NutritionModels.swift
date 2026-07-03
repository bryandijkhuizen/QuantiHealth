import Foundation

struct FoodMacros: Codable, Equatable, Hashable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    static let zero = FoodMacros(calories: 0, protein: 0, carbs: 0, fat: 0)
    func scaled(by factor: Double) -> FoodMacros {
        FoodMacros(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
    static func + (lhs: FoodMacros, rhs: FoodMacros) -> FoodMacros {
        FoodMacros(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}

struct FoodItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var brand: String
    var servingGrams: Double
    var macrosPerServing: FoodMacros
}

enum MealSlot: String, CaseIterable, Codable, Identifiable {
    case breakfast, afterBreakfast = "after_breakfast", lunch, afterLunch = "after_lunch", dinner, afterDinner = "after_dinner"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .afterBreakfast: "After breakfast"
        case .lunch: "Lunch"
        case .afterLunch: "After lunch"
        case .dinner: "Dinner"
        case .afterDinner: "After dinner"
        }
    }
}

struct FoodEntry: Identifiable, Codable, Equatable {
    let id: String
    var loggedAt: Date
    var mealSlot: MealSlot
    var quantity: Double
    var food: FoodItem
    var totalMacros: FoodMacros { food.macrosPerServing.scaled(by: quantity) }
}

struct FoodGoal: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    static let `default` = FoodGoal(calories: 2400, protein: 180, carbs: 240, fat: 80)
    var macros: FoodMacros { FoodMacros(calories: calories, protein: protein, carbs: carbs, fat: fat) }
}

struct FoodSnapshot: Codable, Equatable {
    var entries: [FoodEntry]
    var goal: FoodGoal
}

enum SupplementUnitKind: String, Codable { case mass, count }

struct Supplement: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    var name: String
    var unitKind: SupplementUnitKind
    var countUnit: String
    var perCountGrams: Double?
    var massInputUnit: String
    var createdAt: Date
}

struct SupplementIntake: Identifiable, Codable, Equatable {
    let id: String
    let supplementId: String
    var amountGrams: Double
    var takenAt: Date
}

enum SupplementReminderFrequency: String, CaseIterable, Codable, Identifiable {
    case daily, weekly, custom
    var id: String { rawValue }
}

struct SupplementPreferences: Codable, Equatable {
    let supplementId: String
    var keepStreak: Bool
    var reminderEnabled: Bool
    var frequency: SupplementReminderFrequency
    var hour: Int
    var minute: Int
    var weekday: Int
    var weekdaysMask: Int
    static func defaults(for id: String) -> SupplementPreferences {
        SupplementPreferences(supplementId: id, keepStreak: false, reminderEnabled: false, frequency: .daily, hour: 9, minute: 0, weekday: 1, weekdaysMask: 0)
    }
}

struct SupplementSnapshot: Codable, Equatable {
    var supplements: [Supplement]
    var intakes: [String: [SupplementIntake]]
    var preferences: [String: SupplementPreferences]
    var savedAt: Date
}
