import SwiftUI

struct ProgressaCustomExercisesView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var exercises: [ProgressaExerciseLibraryItem] = []
    @State private var showingCreate = false
    @State private var editing: ProgressaExerciseLibraryItem?
    @State private var isLoading = false

    var body: some View {
        List {
            if exercises.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No custom exercises").font(.headline)
                    Text("Create exercises that are missing from the Progressa catalogue.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            ForEach(exercises) { exercise in
                Button { editing = exercise } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.tint).frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading) {
                            Text(exercise.name).font(.headline).foregroundStyle(.primary)
                            Text(exercise.weightType.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 3)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { if await model.deleteCustomExercise(id: exercise.id) { exercises.removeAll { $0.id == exercise.id } } }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("My exercises")
        .toolbar { Button { showingCreate = true } label: { Label("New exercise", systemImage: "plus") } }
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingCreate) { CreateCustomExerciseSheet { created in exercises.insert(created, at: 0) } }
        .sheet(item: $editing) { exercise in
            EditCustomExerciseSheet(exercise: exercise) { updated in
                if let index = exercises.firstIndex(where: { $0.id == updated.id }) { exercises[index] = updated }
                exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        exercises = await model.searchExercises("")
        exercises = exercises.filter { !$0.isBuiltin }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct EditCustomExerciseSheet: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let exercise: ProgressaExerciseLibraryItem
    @State private var name: String
    @State private var weightType: ProgressaWeightType
    @State private var saving = false
    let onSaved: (ProgressaExerciseLibraryItem) -> Void

    init(exercise: ProgressaExerciseLibraryItem, onSaved: @escaping (ProgressaExerciseLibraryItem) -> Void) {
        self.exercise = exercise
        self.onSaved = onSaved
        _name = State(initialValue: exercise.name)
        _weightType = State(initialValue: exercise.weightType)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Weight type", selection: $weightType) {
                    ForEach([ProgressaWeightType.standard, .bodyweight, .assisted], id: \.rawValue) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }
            .navigationTitle("Edit exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var ok = true
        if clean != exercise.name { ok = await model.renameCustomExercise(id: exercise.id, name: clean) }
        if ok, weightType != exercise.weightType { ok = await model.updateCustomExerciseWeightType(id: exercise.id, weightType: weightType) }
        guard ok else { return }
        onSaved(ProgressaExerciseLibraryItem(
            id: exercise.id, name: clean, muscleGroup: exercise.muscleGroup, weightType: weightType, isBuiltin: false
        ))
        dismiss()
    }
}

private struct CreateCustomExerciseSheet: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var weightType: ProgressaWeightType = .standard
    @State private var isSaving = false
    let onCreated: (ProgressaExerciseLibraryItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Weight type", selection: $weightType) {
                    ForEach([ProgressaWeightType.standard, .bodyweight, .assisted], id: \.rawValue) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isSaving = true; defer { isSaving = false }
                            if let created = await model.createCustomExercise(name: name, weightType: weightType) {
                                onCreated(created); dismiss()
                            }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}
