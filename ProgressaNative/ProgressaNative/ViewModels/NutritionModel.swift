import Foundation

@MainActor
final class NutritionModel: ObservableObject {
    @Published var selectedDay = Date.now
    @Published var food = FoodSnapshot(entries: [], goal: .default)
    @Published var foodResults: [FoodItem] = []
    @Published var supplements: [Supplement] = []
    @Published var intakes: [String: [SupplementIntake]] = [:]
    @Published var preferences: [String: SupplementPreferences] = [:]
    @Published var supplementsAreCached = false
    @Published var isLoading = false
    @Published var message: String?

    private let service: NutritionServing
    private let store: NutritionStore
    private let reminders: SupplementReminderScheduling
    private var session: ProgressaSession?

    init(service: NutritionServing = NutritionClient(), store: NutritionStore = NutritionStore(), reminders: SupplementReminderScheduling = SupplementReminderScheduler()) {
        self.service = service; self.store = store; self.reminders = reminders
    }

    func configure(session: ProgressaSession) async {
        guard self.session?.userId != session.userId else { return }
        self.session = session
        food = store.loadFood(userId: session.userId)
        if let cached = store.loadSupplements(userId: session.userId) { apply(cached); supplementsAreCached = true }
        await refreshSupplements()
    }

    var dayEntries: [FoodEntry] {
        food.entries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDay) }.sorted { $0.loggedAt < $1.loggedAt }
    }
    var dayTotals: FoodMacros { dayEntries.reduce(.zero) { $0 + $1.totalMacros } }

    func searchFoods(_ query: String) async {
        guard let session else { return }
        do { foodResults = try await service.searchFoods(query, session: session) }
        catch { message = error.localizedDescription }
    }

    func addFood(_ item: FoodItem, grams: Double, slot: MealSlot) {
        guard let session, grams > 0, item.servingGrams > 0 else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDay)
        let loggedAt = Calendar.current.date(from: components) ?? selectedDay
        food.entries.append(FoodEntry(id: UUID().uuidString, loggedAt: loggedAt, mealSlot: slot, quantity: grams / item.servingGrams, food: item))
        try? store.saveFood(food, userId: session.userId)
    }
    func deleteFood(_ entry: FoodEntry) {
        guard let session else { return }; food.entries.removeAll { $0.id == entry.id }; try? store.saveFood(food, userId: session.userId)
    }
    func saveGoal(_ goal: FoodGoal) {
        guard let session else { return }; food.goal = goal; try? store.saveFood(food, userId: session.userId)
    }

    func refreshSupplements() async {
        guard let session else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let snapshot = try await service.fetchSupplements(session: session)
            apply(snapshot); supplementsAreCached = false
            try store.saveSupplements(snapshot, userId: session.userId)
            for supplement in supplements {
                if let value = preferences[supplement.id], value.reminderEnabled {
                    try? await reminders.apply(value, supplementName: supplement.name, requestPermission: false)
                }
            }
        } catch {
            supplementsAreCached = !supplements.isEmpty
            message = supplements.isEmpty ? "Supplements could not be loaded." : "Offline: cached supplements are still shown."
        }
    }

    func addSupplement(name: String) async -> Bool {
        guard let session else { return false }
        do {
            let item = try await service.createSupplement(name: name, session: session)
            supplements.insert(item, at: 0); preferences[item.id] = .defaults(for: item.id); saveSupplementCache(); return true
        } catch { message = error.localizedDescription; return false }
    }
    func deleteSupplement(_ supplement: Supplement) async {
        guard let session else { return }
        do {
            try await service.deleteSupplement(id: supplement.id, session: session); reminders.cancel(supplementId: supplement.id)
            supplements.removeAll { $0.id == supplement.id }; intakes[supplement.id] = nil; preferences[supplement.id] = nil; saveSupplementCache()
        } catch { message = error.localizedDescription }
    }
    func logIntake(_ supplement: Supplement, displayedAmount: Double) async -> Bool {
        guard let session, displayedAmount > 0 else { return false }
        let grams = supplement.unitKind == .count ? displayedAmount * (supplement.perCountGrams ?? 0) : grams(from: displayedAmount, unit: supplement.massInputUnit)
        guard grams > 0 else { message = "Set grams per \(supplement.countUnit) before logging count-based intake."; return false }
        do { try await service.addIntake(supplementId: supplement.id, amountGrams: grams, takenAt: .now, session: session); await refreshSupplements(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func deleteIntake(_ intake: SupplementIntake) async {
        guard let session else { return }
        do { try await service.deleteIntake(id: intake.id, session: session); intakes[intake.supplementId]?.removeAll { $0.id == intake.id }; saveSupplementCache() }
        catch { message = error.localizedDescription }
    }
    func savePreferences(_ value: SupplementPreferences, for supplement: Supplement) async -> Bool {
        guard let session else { return false }
        do {
            try await reminders.apply(value, supplementName: supplement.name, requestPermission: value.reminderEnabled)
            do { try await service.savePreferences(value, session: session) }
            catch { reminders.cancel(supplementId: supplement.id); throw error }
            preferences[supplement.id] = value; saveSupplementCache(); return true
        } catch { message = error.localizedDescription; return false }
    }

    private func apply(_ snapshot: SupplementSnapshot) {
        supplements = snapshot.supplements; intakes = snapshot.intakes; preferences = snapshot.preferences
    }
    private func saveSupplementCache() {
        guard let session else { return }
        try? store.saveSupplements(SupplementSnapshot(supplements: supplements, intakes: intakes, preferences: preferences, savedAt: .now), userId: session.userId)
    }
    private func grams(from amount: Double, unit: String) -> Double {
        switch unit { case "mg": amount / 1000; case "mcg": amount / 1_000_000; case "oz": amount * 28.349523125; default: amount }
    }
}
