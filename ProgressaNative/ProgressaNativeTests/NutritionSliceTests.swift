import XCTest
@testable import ProgressaNative

@MainActor
final class NutritionSliceTests: XCTestCase {
    private let session = ProgressaSession(accessToken: "a", refreshToken: "r", userId: "user-a", expiresAt: .distantFuture)

    func testServingCalculationAndAccountIsolation() throws {
        let directory = temporaryDirectory()
        let store = NutritionStore(directory: directory)
        let item = FoodItem(id: "food", title: "Oats", brand: "", servingGrams: 100, macrosPerServing: FoodMacros(calories: 380, protein: 13, carbs: 68, fat: 7))
        let entry = FoodEntry(id: "entry", loggedAt: .now, mealSlot: .breakfast, quantity: 0.5, food: item)
        XCTAssertEqual(entry.totalMacros.calories, 190, accuracy: 0.001)
        XCTAssertEqual(entry.totalMacros.protein, 6.5, accuracy: 0.001)

        try store.saveFood(FoodSnapshot(entries: [entry], goal: .default), userId: "user-a")
        XCTAssertEqual(store.loadFood(userId: "user-a").entries.count, 1)
        XCTAssertTrue(store.loadFood(userId: "user-b").entries.isEmpty)
    }

    func testCountIntakeConvertsToGramsAndRefreshes() async {
        let service = FakeNutritionService()
        let model = NutritionModel(service: service, store: NutritionStore(directory: temporaryDirectory()), reminders: FakeReminderScheduler())
        await model.configure(session: session)
        let supplement = Supplement(
            id: "supp", userId: session.userId, name: "Creatine caps", unitKind: .count,
            countUnit: "capsule", perCountGrams: 0.75, massInputUnit: "g", createdAt: .now
        )
        let success = await model.logIntake(supplement, displayedAmount: 2)
        XCTAssertTrue(success)
        XCTAssertEqual(service.loggedAmount, 1.5, accuracy: 0.001)
    }

    func testSavingEnabledReminderSchedulesAndPersistsPreferences() async {
        let service = FakeNutritionService()
        let scheduler = FakeReminderScheduler()
        let model = NutritionModel(service: service, store: NutritionStore(directory: temporaryDirectory()), reminders: scheduler)
        await model.configure(session: session)
        let supplement = Supplement(id: "supp", userId: session.userId, name: "Vitamin D", unitKind: .mass, countUnit: "tablet", massInputUnit: "mg", createdAt: .now)
        var preferences = SupplementPreferences.defaults(for: supplement.id)
        preferences.reminderEnabled = true; preferences.frequency = .weekly; preferences.weekday = 3

        let success = await model.savePreferences(preferences, for: supplement)

        XCTAssertTrue(success)
        XCTAssertEqual(scheduler.applied?.0, preferences)
        XCTAssertTrue(scheduler.applied?.2 == true)
        XCTAssertEqual(service.savedPreferences, preferences)
    }

    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true) }
}

private final class FakeNutritionService: NutritionServing {
    var snapshot = SupplementSnapshot(supplements: [], intakes: [:], preferences: [:], savedAt: .now)
    var loggedAmount = 0.0
    var savedPreferences: SupplementPreferences?
    func searchFoods(_ query: String, session: ProgressaSession) async throws -> [FoodItem] { [] }
    func fetchSupplements(session: ProgressaSession) async throws -> SupplementSnapshot { snapshot }
    func createSupplement(name: String, session: ProgressaSession) async throws -> Supplement { Supplement(id: "new", userId: session.userId, name: name, unitKind: .mass, countUnit: "tablet", massInputUnit: "g", createdAt: .now) }
    func deleteSupplement(id: String, session: ProgressaSession) async throws {}
    func addIntake(supplementId: String, amountGrams: Double, takenAt: Date, session: ProgressaSession) async throws { loggedAmount = amountGrams }
    func deleteIntake(id: String, session: ProgressaSession) async throws {}
    func savePreferences(_ preferences: SupplementPreferences, session: ProgressaSession) async throws { savedPreferences = preferences }
}

private final class FakeReminderScheduler: SupplementReminderScheduling {
    var applied: (SupplementPreferences, String, Bool)?
    func apply(_ preferences: SupplementPreferences, supplementName: String, requestPermission: Bool) async throws { applied = (preferences, supplementName, requestPermission) }
    func cancel(supplementId: String) {}
}
