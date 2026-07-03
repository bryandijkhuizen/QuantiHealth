import SwiftUI

struct ProgressaRoutinesView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var showingCreate = false
    @State private var name = ""

    var body: some View {
        List {
            if model.routines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.largeTitle)
                    Text("No routines").font(.headline)
                    Text("Create a reusable workout template.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                ForEach(model.routines) { routine in
                    NavigationLink { ProgressaRoutineDetailView(routineId: routine.id) } label: {
                        VStack(alignment: .leading) {
                            Text(routine.name).font(.headline)
                            Text(routine.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteRoutine(id: routine.id) } } }
                }
            }
        }
        .navigationTitle("My routines")
        .refreshable { await model.loadRoutines() }
        .task { if model.routines.isEmpty { await model.loadRoutines() } }
        .toolbar { Button { showingCreate = true } label: { Label("Add routine", systemImage: "plus") } }
        .alert("New routine", isPresented: $showingCreate) {
            TextField("Push A / Upper / Full body", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") { Task { _ = await model.createRoutine(name: name); name = "" } }
        }
    }
}

private struct ProgressaRoutineDetailView: View {
    @EnvironmentObject private var model: ProgressaModel
    let routineId: String
    @State private var showingExercisePicker = false
    @State private var setTarget: RoutineSetTarget?
    @State private var showingRename = false
    @State private var name = ""

    private var detail: ProgressaRoutineDetail? { model.routineDetails[routineId] }

    var body: some View {
        List {
            if let detail {
                if detail.exercises.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "dumbbell").font(.largeTitle)
                        Text("No exercises").font(.headline)
                        Text("Add an exercise to build this routine.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 32)
                }
                ForEach(detail.exercises) { entry in
                    let sets = detail.sets.filter { $0.routineExerciseId == entry.id }.sorted { $0.sortOrder < $1.sortOrder }
                    Section {
                        ForEach(sets) { set in
                            Button { setTarget = .init(entry: entry, routineSet: set) } label: {
                                HStack {
                                    Text(set.reps.map { "\($0) reps" } ?? "Reps not set")
                                    Spacer()
                                    Text([
                                        set.weightKg.map(model.workoutWeightText), set.rir.map { "RIR \($0)" }, set.side
                                    ].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }.onDelete { offsets in
                            for index in offsets { Task { await model.deleteRoutineSet(routineId: routineId, setId: sets[index].id) } }
                        }
                        Button { setTarget = .init(entry: entry, routineSet: nil) } label: { Label("Add set", systemImage: "plus.circle") }
                    } header: {
                        HStack {
                            Text(entry.exercise.name)
                            Spacer()
                            Button(role: .destructive) { Task { await model.deleteRoutineExercise(routineId: routineId, entryId: entry.id) } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }.onMove { source, destination in Task { await model.moveRoutineExercises(routineId: routineId, from: source, to: destination) } }
            } else { ProgressView() }
        }
        .navigationTitle(detail?.routine.name ?? "Routine")
        .task { _ = await model.loadRoutine(id: routineId) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { name = detail?.routine.name ?? ""; showingRename = true } label: { Image(systemName: "pencil") }
                EditButton()
                Button { showingExercisePicker = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            RoutineExercisePicker { exercise in
                Task { if await model.addRoutineExercise(routineId: routineId, exercise: exercise) { showingExercisePicker = false } }
            }
        }
        .sheet(item: $setTarget) { target in RoutineSetEditor(routineId: routineId, target: target) }
        .alert("Rename routine", isPresented: $showingRename) {
            TextField("Routine name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { _ = await model.renameRoutine(id: routineId, name: name) } }
        }
    }
}

private struct RoutineSetTarget: Identifiable {
    let entry: ProgressaRoutineExercise
    let routineSet: ProgressaRoutineSet?
    var id: String { routineSet?.id ?? "new-\(entry.id)" }
}

private struct RoutineExercisePicker: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ProgressaExerciseLibraryItem] = []
    @State private var customName = ""
    let selection: (ProgressaExerciseLibraryItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { exercise in
                        Button { selection(exercise) } label: {
                            VStack(alignment: .leading) {
                                Text(exercise.name).foregroundStyle(.primary)
                                if let group = exercise.muscleGroup { Text(group).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("Custom exercise") {
                    TextField("Exercise name", text: $customName)
                    Button("Create and add") {
                        Task { if let exercise = await model.createCustomExercise(name: customName, weightType: .standard) { selection(exercise) } }
                    }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add exercise")
            .searchable(text: $query)
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                results = await model.searchExercises(query)
            }
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

private struct RoutineSetEditor: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let routineId: String
    let target: RoutineSetTarget
    @State private var reps: String
    @State private var weight: String
    @State private var rir: String
    @State private var side: String
    @State private var prepared = false

    init(routineId: String, target: RoutineSetTarget) {
        self.routineId = routineId; self.target = target
        _reps = State(initialValue: target.routineSet?.reps.map(String.init) ?? "")
        _weight = State(initialValue: target.routineSet?.weightKg.map { String($0) } ?? "")
        _rir = State(initialValue: target.routineSet?.rir.map(String.init) ?? "")
        _side = State(initialValue: target.routineSet?.side ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Reps", text: $reps).keyboardType(.numberPad)
                TextField("Weight (\(model.workoutWeightUnit))", text: $weight).keyboardType(.decimalPad)
                TextField("RIR", text: $rir).keyboardType(.numberPad)
                Picker("Side", selection: $side) { Text("Both").tag(""); Text("Left").tag("L"); Text("Right").tag("R") }
            }
            .navigationTitle(target.routineSet == nil ? "Add set" : "Edit set")
            .onAppear {
                guard !prepared else { return }; prepared = true
                if let kg = target.routineSet?.weightKg { weight = String(model.workoutWeightForDisplay(kg)) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let input = ProgressaSetInput(
                            weightKg: routineDouble(weight).map(model.workoutWeightForStorage), reps: Int(reps),
                            rir: routineDouble(rir), side: side.isEmpty ? nil : side, isWarmup: false
                        )
                        Task {
                            let saved = if let set = target.routineSet {
                                await model.updateRoutineSet(routineId: routineId, setId: set.id, input: input)
                            } else {
                                await model.addRoutineSet(routineId: routineId, entryId: target.entry.id, input: input)
                            }
                            if saved { dismiss() }
                        }
                    }.disabled((Int(reps) ?? 0) <= 0)
                }
            }
        }
    }
}

private func routineDouble(_ value: String) -> Double? {
    Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
}
