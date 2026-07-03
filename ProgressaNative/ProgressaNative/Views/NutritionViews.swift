import PhotosUI
import SwiftUI
import UIKit

struct ProgressaMoreView: View {
    @EnvironmentObject private var app: ProgressaModel
    @StateObject private var model = NutritionModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var confirmingAvatarRemoval = false

    var body: some View {
        List {
            Section("Profile") {
                HStack(spacing: 14) {
                    ProgressaAvatarView(
                        path: app.profile?.avatarPath, fallback: app.profile?.fullName ?? "?",
                        session: app.session, size: 64
                    )
                    VStack(alignment: .leading) {
                        Text(app.profile?.fullName ?? "Profile").font(.headline)
                        if let handle = app.profile?.handle { Text("@\(handle)").foregroundStyle(.secondary) }
                    }
                    if app.isUploadingAvatar { Spacer(); ProgressView() }
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Change profile photo", systemImage: "photo")
                }
                if app.profile?.avatarPath != nil {
                    Button("Remove profile photo", role: .destructive) { confirmingAvatarRemoval = true }
                }
            }
            Section("Training") {
                NavigationLink { ProgressaRoutinesView() } label: { Label("My routines", systemImage: "list.bullet.rectangle") }
                NavigationLink { ProgressaCustomExercisesView() } label: { Label("My exercises", systemImage: "figure.strengthtraining.traditional") }
            }
            Section("Nutrition") {
                NavigationLink { FoodDiaryView(model: model) } label: { Label("Food diary", systemImage: "fork.knife") }
                NavigationLink { SupplementsView(model: model) } label: { Label("Supplements", systemImage: "pills") }
            }
            Section("Account") {
                if let name = app.profile?.fullName { LabeledContent("Name", value: name) }
                NavigationLink { ProgressaProfileSettingsView() } label: { Label("Profile & account", systemImage: "person.crop.circle") }
                NavigationLink { ProgressaAppearanceView() } label: { Label("Appearance", systemImage: "paintpalette") }
                Button("Sign out", role: .destructive) { app.signOut() }
            }
            Section("Notifications") {
                NavigationLink { ProgressaNotificationsView() } label: { Label("Inbox", systemImage: "bell") }
                NavigationLink { ProgressaNotificationSettingsView() } label: { Label("Notification settings", systemImage: "slider.horizontal.3") }
            }
        }
        .navigationTitle("Me")
        .task(id: app.session?.userId) { if let session = app.session { await model.configure(session: session) } }
        .onChange(of: selectedPhoto) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let jpeg = resizedAvatarJPEG(data) else { return }
                await app.uploadAvatar(jpegData: jpeg)
                selectedPhoto = nil
            }
        }
        .confirmationDialog("Remove profile photo?", isPresented: $confirmingAvatarRemoval) {
            Button("Remove", role: .destructive) { Task { await app.removeAvatar() } }
        }
        .alert("Progressa", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

private struct ProgressaProfileSettingsView: View {
    @EnvironmentObject private var app: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var handle = ""
    @State private var country = ""
    @State private var birthdate = Date.now
    @State private var height = ""
    @State private var units = "metric"
    @State private var sex = ""
    @State private var visibility = "public"
    @State private var confirmingDelete = false
    @State private var saving = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Full name", text: $fullName)
                TextField("Handle", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Country code", text: $country).textInputAutocapitalization(.characters)
                DatePicker("Birthdate", selection: $birthdate, in: ...Date.now, displayedComponents: .date)
                TextField("Height (cm)", text: $height).keyboardType(.decimalPad)
                Picker("Sex", selection: $sex) {
                    Text("Not specified").tag(""); Text("Female").tag("female"); Text("Male").tag("male"); Text("Other").tag("other")
                }
            }
            Section("Preferences") {
                Picker("Units", selection: $units) { Text("Metric").tag("metric"); Text("Imperial").tag("imperial") }
                Picker("Profile visibility", selection: $visibility) { Text("Public").tag("public"); Text("Private").tag("private") }
            }
            Section {
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Deleting your account permanently removes your Progressa data.")
            }
        }
        .navigationTitle("Profile & account")
        .toolbar {
            Button("Save") {
                Task {
                    guard let current = app.profile else { return }
                    saving = true
                    var value = current
                    value.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : handle
                    value.country = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    value.birthdate = birthdate
                    value.heightCm = routineProfileDouble(height)
                    value.unitSystem = units; value.sex = sex.isEmpty ? nil : sex; value.profileVisibility = visibility
                    let success = await app.saveProfileSettings(value)
                    saving = false
                    if success { dismiss() }
                }
            }.disabled(saving || country.trimmingCharacters(in: .whitespacesAndNewlines).count != 2)
        }
        .onAppear {
            guard let profile = app.profile else { return }
            fullName = profile.fullName ?? ""; handle = profile.handle ?? ""; country = profile.country ?? ""
            birthdate = profile.birthdate ?? .now; height = profile.heightCm.map { String($0) } ?? ""
            units = profile.unitSystem ?? "metric"; sex = profile.sex ?? ""; visibility = profile.profileVisibility ?? "public"
        }
        .confirmationDialog("Delete your account permanently?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { if await app.deleteAccount() { dismiss() } } }
        }
    }
}

private func routineProfileDouble(_ value: String) -> Double? {
    Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
}

private func resizedAvatarJPEG(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let largest = max(image.size.width, image.size.height)
    let scale = min(900 / max(largest, 1), 1)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.85)
}

private struct FoodDiaryView: View {
    @ObservedObject var model: NutritionModel
    @State private var showingSearch = false
    @State private var showingGoal = false

    var body: some View {
        List {
            DatePicker("Day", selection: $model.selectedDay, displayedComponents: .date)
            Section("Daily totals") {
                MacroLine(name: "Calories", value: model.dayTotals.calories, target: model.food.goal.calories, unit: "kcal")
                MacroLine(name: "Protein", value: model.dayTotals.protein, target: model.food.goal.protein, unit: "g")
                MacroLine(name: "Carbs", value: model.dayTotals.carbs, target: model.food.goal.carbs, unit: "g")
                MacroLine(name: "Fat", value: model.dayTotals.fat, target: model.food.goal.fat, unit: "g")
            }
            ForEach(MealSlot.allCases) { slot in
                let entries = model.dayEntries.filter { $0.mealSlot == slot }
                if !entries.isEmpty {
                    Section(slot.label) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.food.title)
                                Text("\((entry.quantity * entry.food.servingGrams).formatted(.number.precision(.fractionLength(0...1)))) g · \(entry.totalMacros.calories.formatted(.number.precision(.fractionLength(0)))) kcal")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.swipeActions { Button("Delete", role: .destructive) { model.deleteFood(entry) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Food diary")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingGoal = true } label: { Label("Targets", systemImage: "target") }
                Button { showingSearch = true } label: { Label("Add food", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingSearch) { FoodSearchView(model: model) }
        .sheet(isPresented: $showingGoal) { FoodGoalEditor(model: model) }
    }
}

private struct MacroLine: View {
    let name: String; let value: Double; let target: Double; let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(name); Spacer(); Text("\(value.formatted(.number.precision(.fractionLength(0)))) / \(target.formatted(.number.precision(.fractionLength(0)))) \(unit)").foregroundStyle(.secondary) }
            ProgressView(value: target > 0 ? min(value / target, 1) : 0)
        }
    }
}

private struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: NutritionModel
    @State private var query = ""
    @State private var selected: FoodItem?

    var body: some View {
        NavigationStack {
            List(model.foodResults) { item in
                Button { selected = item } label: {
                    VStack(alignment: .leading) {
                        Text(item.title).foregroundStyle(.primary)
                        Text("\(item.brand) · \(item.macrosPerServing.calories.formatted(.number.precision(.fractionLength(0)))) kcal per \(item.servingGrams.formatted()) g")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add food")
            .searchable(text: $query, prompt: "Search Progressa foods")
            .onSubmit(of: .search) { Task { await model.searchFoods(query) } }
            .toolbar { Button("Done") { dismiss() } }
            .sheet(item: $selected) { FoodServingView(model: model, item: $0) { selected = nil; dismiss() } }
        }
    }
}

private struct FoodServingView: View {
    @ObservedObject var model: NutritionModel
    let item: FoodItem
    let completion: () -> Void
    @State private var grams: Double
    @State private var slot: MealSlot = .breakfast
    init(model: NutritionModel, item: FoodItem, completion: @escaping () -> Void) {
        self.model = model; self.item = item; self.completion = completion; _grams = State(initialValue: item.servingGrams)
    }
    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g", value: $grams, in: 1...2000, step: 5)
                Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.label).tag($0) } }
                let macros = item.macrosPerServing.scaled(by: grams / max(item.servingGrams, 1))
                LabeledContent("Calories", value: "\(macros.calories.formatted(.number.precision(.fractionLength(0)))) kcal")
                LabeledContent("Protein", value: "\(macros.protein.formatted(.number.precision(.fractionLength(1)))) g")
            }.navigationTitle(item.title).toolbar { Button("Add") { model.addFood(item, grams: grams, slot: slot); completion() } }
        }
    }
}

private struct FoodGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: NutritionModel
    @State private var goal: FoodGoal
    init(model: NutritionModel) { self.model = model; _goal = State(initialValue: model.food.goal) }
    var body: some View {
        NavigationStack {
            Form {
                target("Calories", value: $goal.calories, range: 800...6000, step: 50, unit: "kcal")
                target("Protein", value: $goal.protein, range: 0...500, step: 5, unit: "g")
                target("Carbs", value: $goal.carbs, range: 0...800, step: 5, unit: "g")
                target("Fat", value: $goal.fat, range: 0...300, step: 5, unit: "g")
            }.navigationTitle("Nutrition targets").toolbar { Button("Save") { model.saveGoal(goal); dismiss() } }
        }
    }
    private func target(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper("\(name): \(value.wrappedValue.formatted(.number.precision(.fractionLength(0)))) \(unit)", value: value, in: range, step: step)
    }
}

private struct SupplementsView: View {
    @ObservedObject var model: NutritionModel
    @State private var showingAdd = false
    @State private var name = ""
    var body: some View {
        List {
            if model.supplementsAreCached { Label("Offline copy", systemImage: "icloud.slash").font(.footnote).foregroundStyle(.secondary) }
            ForEach(model.supplements) { item in
                NavigationLink { SupplementDetailView(model: model, supplement: item) } label: {
                    VStack(alignment: .leading) { Text(item.name); Text("\(model.intakes[item.id]?.count ?? 0) logged intakes").font(.caption).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteSupplement(item) } } }
            }
        }
        .navigationTitle("Supplements").refreshable { await model.refreshSupplements() }
        .toolbar { Button { showingAdd = true } label: { Label("Add", systemImage: "plus") } }
        .alert("Add supplement", isPresented: $showingAdd) {
            TextField("Name", text: $name)
            Button("Add") { let value = name; name = ""; Task { _ = await model.addSupplement(name: value) } }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

private struct SupplementDetailView: View {
    @ObservedObject var model: NutritionModel
    let supplement: Supplement
    @State private var amount = 1.0
    @State private var showingPreferences = false
    var body: some View {
        List {
            Section("Log intake") {
                Stepper("\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unitLabel)", value: $amount, in: 0.001...10000, step: supplement.unitKind == .count ? 1 : 0.5)
                Button("Log now") { Task { _ = await model.logIntake(supplement, displayedAmount: amount) } }
            }
            Section("History") {
                ForEach(model.intakes[supplement.id] ?? []) { intake in
                    HStack { Text("\(intake.amountGrams.formatted(.number.precision(.fractionLength(0...3)))) g"); Spacer(); Text(intake.takenAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                        .swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteIntake(intake) } } }
                }
            }
        }.navigationTitle(supplement.name)
        .toolbar { Button("Preferences") { showingPreferences = true } }
        .sheet(isPresented: $showingPreferences) { SupplementPreferencesView(model: model, supplement: supplement) }
    }
    private var unitLabel: String { supplement.unitKind == .count ? supplement.countUnit : supplement.massInputUnit }
}

private struct SupplementPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: NutritionModel
    let supplement: Supplement
    @State private var value: SupplementPreferences
    @State private var time: Date
    init(model: NutritionModel, supplement: Supplement) {
        self.model = model; self.supplement = supplement
        let prefs = model.preferences[supplement.id] ?? .defaults(for: supplement.id); _value = State(initialValue: prefs)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: prefs.hour, minute: prefs.minute)) ?? .now)
    }
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Keep streak", isOn: $value.keepStreak)
                Toggle("Reminder", isOn: $value.reminderEnabled)
                if value.reminderEnabled {
                    Picker("Frequency", selection: $value.frequency) { ForEach(SupplementReminderFrequency.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    if value.frequency == .weekly { Picker("Day", selection: $value.weekday) { ForEach(1...7, id: \.self) { Text(dayName($0)).tag($0) } } }
                    if value.frequency == .custom {
                        ForEach(1...7, id: \.self) { day in Toggle(dayName(day), isOn: dayBinding(day)) }
                    }
                }
            }.navigationTitle("Preferences").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { let parts = Calendar.current.dateComponents([.hour, .minute], from: time); value.hour = parts.hour ?? 9; value.minute = parts.minute ?? 0; if await model.savePreferences(value, for: supplement) { dismiss() } } } }
            }
        }
    }
    private func dayBinding(_ day: Int) -> Binding<Bool> { Binding(get: { value.weekdaysMask & (1 << (day - 1)) != 0 }, set: { on in if on { value.weekdaysMask |= 1 << (day - 1) } else { value.weekdaysMask &= ~(1 << (day - 1)) } }) }
    private func dayName(_ day: Int) -> String { Calendar.current.weekdaySymbols[day % 7] }
}
