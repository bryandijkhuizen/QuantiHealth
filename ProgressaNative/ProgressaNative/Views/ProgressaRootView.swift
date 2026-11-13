import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct ProgressaRootView: View {
    @EnvironmentObject private var model: ProgressaModel

    static var isWorkoutPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--workout-preview")
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if Self.isWorkoutPreview {
                NavigationStack { ProgressaWorkoutsView() }
            } else if model.isRecoveringPassword { ProgressaResetPasswordView() }
            else if model.session == nil { ProgressaLoginView() }
            else {
                switch model.profileState {
                case .loading:
                    ProgressView("Loading your profile…")
                case .required:
                    ProgressaOnboardingView()
                case .complete:
                    ProgressaTabs()
                case .failed:
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").font(.system(size: 54))
                        Text("Profile unavailable").font(.title2.bold())
                        Text("Progressa could not verify your profile. Your session is still safe on this device.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Try again") { Task { await model.loadProfile() } }
                        Button("Sign out", role: .destructive) { model.signOut() }
                    }.padding()
                }
            }
        }
        .sheet(item: $model.pendingConnect) { _ in QuantivitaConsentView() }
        .alert("Progressa", isPresented: Binding(
            get: { model.message != nil }, set: { if !$0 { model.message = nil } }
        )) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
}

private struct ProgressaLoginView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce = ""
    @State private var showingRegistration = false
    @State private var showingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SignInWithAppleButton(.continue) { request in
                        let nonce = randomNonce()
                        appleNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                    } onCompletion: { result in
                        switch result {
                        case let .success(authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let tokenData = credential.identityToken,
                                  let token = String(data: tokenData, encoding: .utf8),
                                  !appleNonce.isEmpty else {
                                model.appleSignInFailed(ProgressaClientError.invalidResponse)
                                return
                            }
                            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
                            Task { await model.signInWithApple(idToken: token, nonce: appleNonce, fullName: name) }
                        case let .failure(error):
                            model.appleSignInFailed(error)
                        }
                    }
                    .signInWithAppleButtonStyle(.black).frame(height: 50)
                }
                Section { TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never); SecureField("Password", text: $password).textContentType(.password) }
                Button("Sign in") { Task { await model.signIn(email: email, password: password) } }
                    .disabled(email.isEmpty || password.isEmpty || model.isLoading)
                Section {
                    Button("Forgot password?") { showingReset = true }
                    Button("Create account") { showingRegistration = true }
                }
            }.navigationTitle("Progressa")
                .sheet(isPresented: $showingRegistration) { ProgressaRegistrationView(email: email) }
                .sheet(isPresented: $showingReset) { ProgressaRequestResetView(email: email) }
        }
    }

    private func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }
}

private struct ProgressaRegistrationView: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never)
                SecureField("Password", text: $password).textContentType(.newPassword)
                SecureField("Repeat password", text: $confirmation).textContentType(.newPassword)
                Button("Create account") { Task { await model.signUp(email: email, password: password, confirmation: confirmation) } }
                    .disabled(model.isLoading)
            }
            .navigationTitle("Create account")
            .toolbar { Button("Close") { dismiss() } }
        }
    }
}

private struct ProgressaRequestResetView: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State var email: String

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never)
                Button("Send reset link") { Task { await model.requestPasswordReset(email: email) } }.disabled(model.isLoading)
            }
            .navigationTitle("Reset password")
            .toolbar { Button("Close") { dismiss() } }
        }
    }
}

private struct ProgressaResetPasswordView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a new password") {
                    SecureField("New password", text: $password).textContentType(.newPassword)
                    SecureField("Repeat new password", text: $confirmation).textContentType(.newPassword)
                }
                Button("Save password") { Task { _ = await model.updateRecoveredPassword(password, confirmation: confirmation) } }
                    .disabled(model.isLoading)
                Button("Back to sign in", role: .cancel) { model.isRecoveringPassword = false; model.signOut() }
            }.navigationTitle("Reset password")
        }
    }
}

private struct ProgressaTabs: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var selection = 0
    @AppStorage("progressa.accent") private var accent = ProgressaAccent.presets[0].id
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { ProgressaFeedView() }.tabItem { Label("Feed", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            NavigationStack { ProgressaWorkoutsView() }.tabItem { Label("Workouts", systemImage: "dumbbell") }.tag(1)
            NavigationStack { ProgressaStatsView() }.tabItem { Label("Stats", systemImage: "chart.bar") }.tag(2)
            NavigationStack { ProgressaMeasurementsView() }.tabItem { Label("Measure", systemImage: "ruler") }.tag(3)
            NavigationStack { ProgressaMoreView() }.tabItem { Label("Me", systemImage: "person") }.tag(4)
        }.tint(ProgressaAccent.color(for: accent))
            .onChange(of: model.workoutRoute) { route in if route != nil { selection = 1 } }
            .onAppear { if model.workoutRoute != nil { selection = 1 } }
    }
}

private struct ProgressaWorkoutsView: View {
    @EnvironmentObject private var model: ProgressaModel
    @State private var showingCreate = false
    @State private var createdWorkoutID: String?
    @State private var showingHealthImport = false
    @State private var showingRecorder = false
    @State private var importAround: Date = .now
    @State private var isStartingWorkout = false

    var body: some View {
        List {
            if let active = model.activeWorkout {
                Section {
                    NavigationLink(value: active.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Continue Workout", systemImage: "dumbbell.fill").font(.headline)
                            Text(active.title)
                            if let start = active.startedAt { Text(start, style: .timer).monospacedDigit().foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                }
            } else {
                Section {
                    Button { Task { await startWorkout() } } label: {
                        Label("Start Workout", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(isStartingWorkout || model.isChangingWorkout)
                }
            }
            if case let .cached(savedAt) = model.workoutSyncState {
                Section {
                    Label(
                        savedAt.map { "Offline copy from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Offline copy",
                        systemImage: "icloud.slash"
                    ).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(model.workouts.filter { !$0.isInProgress }) { workout in
                    NavigationLink(value: workout.id) {
                        VStack(alignment: .leading) {
                            Text(workout.title).font(.headline)
                            Text(workout.exercises.isEmpty
                                 ? workout.createdAt.formatted(date: .abbreviated, time: .shortened)
                                 : "\(workout.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(workout.totalSets) sets")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .navigationDestination(for: String.self) { ProgressaWorkoutDetail(workoutId: $0) }
        .navigationDestination(isPresented: Binding(
            get: { createdWorkoutID != nil }, set: { if !$0 { createdWorkoutID = nil } }
        )) {
            if let id = createdWorkoutID { ProgressaWorkoutDetail(workoutId: id) }
        }
        .onChange(of: model.workoutRoute) { id in
            if let id { createdWorkoutID = id; model.workoutRoute = nil }
        }
        .onAppear { if let id = model.workoutRoute { createdWorkoutID = id; model.workoutRoute = nil } }
        .refreshable { await model.refreshWorkouts() }
        .toolbar {
            if isStartingWorkout {
                ProgressView()
            } else {
                Menu {
                    // Primary path: the workout exists immediately, no creation form to fill in first.
                    Button { Task { await startWorkout() } } label: { Label(model.activeWorkout == nil ? "Start Workout" : "Continue Workout", systemImage: "play.fill") }
                    Button { showingCreate = true } label: { Label("New workout from routine…", systemImage: "list.bullet.rectangle") }.disabled(model.activeWorkout != nil)
                    Button { showingRecorder = true } label: { Label("Record outdoor workout", systemImage: "location.fill") }
                    Button { importAround = .now; showingHealthImport = true } label: { Label("Import from Apple Health", systemImage: "heart") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingCreate) {
            ProgressaWorkoutEditor { id in
                showingCreate = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    createdWorkoutID = id
                }
            }
        }
        .sheet(isPresented: $showingRecorder) {
            WorkoutRecordingView { recordedStart in
                // Offer to import the just-recorded Apple Health workout (with its route) as a Progressa workout.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    importAround = recordedStart
                    showingHealthImport = true
                }
            }
        }
        .sheet(isPresented: $showingHealthImport) {
            ProgressaHealthSessionPicker(around: importAround, title: "Import from Health") { session in
                if let id = await model.importHealthSession(session) { createdWorkoutID = id; return true }
                return false
            }
        }
    }

    /// Creates a blank workout immediately and opens it — no separate "save workout" step
    /// before the user can start adding exercises.
    private func startWorkout() async {
        isStartingWorkout = true
        defer { isStartingWorkout = false }
        if let id = await model.createWorkout(title: "Workout", createdAt: .now, exercises: []) {
            createdWorkoutID = id
        }
    }
}

private struct ProgressaWorkoutDetail: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let workoutId: String
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var showingAddExercise = false
    @State private var setTarget: SetEditTarget?
    @State private var showingHealthPicker = false
    @State private var showingSequence = false
    @State private var showingTimes = false
    @State private var editMode: EditMode = .inactive

    private var workout: ProgressaWorkout? { model.workouts.first { $0.id == workoutId } }

    var body: some View {
        List {
            if let workout {
                Section {
                    if let start = workout.startedAt {
                        LabeledContent("Started", value: start.formatted(date: .abbreviated, time: .shortened))
                        if let end = workout.endedAt {
                            LabeledContent("Finished", value: end.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Duration", value: Duration.seconds(end.timeIntervalSince(start)).formatted(.time(pattern: .hourMinute)))
                        } else {
                            HStack { Label("In Progress", systemImage: "timer"); Spacer(); Text(start, style: .timer).monospacedDigit() }
                        }
                    } else {
                        LabeledContent("Date", value: workout.createdAt.formatted(date: .long, time: .shortened))
                    }
                    Button("Edit Workout Times") { showingTimes = true }
                    if let location = workout.location { LabeledContent("Location", value: location) }
                }
                if workout.exercises.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "dumbbell").font(.largeTitle).foregroundStyle(.secondary)
                            Text("No exercises added yet").font(.headline)
                            Text("Add exercises to start tracking sets.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(workout.exercises) { exercise in
                    Section {
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            InlineSetRow(
                                workoutId: workoutId, blockId: exercise.id, set: set, index: index,
                                onDelete: { Task { await model.deleteSet(workoutId: workoutId, blockId: exercise.id, setId: set.id) } }
                            )
                        }
                        .onDelete { offsets in
                            for index in offsets { Task { await model.deleteSet(workoutId: workoutId, blockId: exercise.id, setId: exercise.sets[index].id) } }
                        }
                        Button { setTarget = SetEditTarget(workoutId: workoutId, block: exercise, workoutSet: nil) } label: {
                            Label("Add set", systemImage: "plus.circle")
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                if let sequence = exercise.sequenceID, let round = exercise.sequenceRound {
                                    let ids = workout.exercises.compactMap(\.sequenceID).reduce(into: [String]()) { ids, id in
                                        if !ids.contains(id) { ids.append(id) }
                                    }
                                    Text("Sequence \((ids.firstIndex(of: sequence) ?? 0) + 1) · Round \(round)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("· \(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) { Task { await model.deleteExercise(workoutId: workoutId, blockId: exercise.id) } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless).accessibilityLabel("Delete \(exercise.name)").frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                .onMove { source, destination in Task { await model.moveExercises(workoutId: workoutId, from: source, to: destination) } }
                if let metadata = model.healthMetadata[workoutId] {
                    ProgressaHealthMetadataSection(value: metadata)
                    Section {
                        Button("Unlink Apple Health", role: .destructive) { Task { await model.unlinkHealthSession(workoutId: workoutId) } }
                    }
                } else {
                    Section("Apple Health") {
                        Button { showingHealthPicker = true } label: { Label("Link Apple Health workout", systemImage: "heart") }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let workout, workout.isInProgress, let start = workout.startedAt {
                Button {
                    Task { _ = await model.saveWorkoutTiming(id: workoutId, startedAt: start, endedAt: .now) }
                } label: {
                    HStack { if model.isChangingWorkout { ProgressView() }; Label("Finish Workout", systemImage: "checkmark.circle.fill") }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).disabled(model.isChangingWorkout)
                .padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
        }
        .navigationTitle(workout?.title ?? "Workout")
        .task { await model.refreshWorkout(id: workoutId); await model.loadHealthMetadata(workoutId: workoutId) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Add Exercise", systemImage: "plus") { showingAddExercise = true }
                    Button("Add Sequence", systemImage: "repeat") { showingSequence = true }
                } label: { Image(systemName: "plus").accessibilityLabel("Add exercises") }.disabled(workout == nil)
                Menu {
                    Button("Edit Workout", systemImage: "pencil") { showingEdit = true }
                    Button("Edit Times", systemImage: "clock") { showingTimes = true }
                    Button(editMode.isEditing ? "Done Reordering" : "Reorder Exercises", systemImage: "arrow.up.arrow.down") {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    Button("Delete Workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis").accessibilityLabel("Workout options") }.disabled(workout == nil)
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingTimes) { if let workout { WorkoutTimesEditor(workout: workout) } }
        .sheet(isPresented: $showingSequence) { WorkoutSequenceEditor(workoutID: workoutId) }
        .sheet(isPresented: $showingEdit) { if let workout { ProgressaWorkoutEditor(workout: workout) } }
        .sheet(isPresented: $showingAddExercise) {
            ProgressaExercisePicker { input in
                Task { if await model.addExercise(input, workoutId: workoutId) { showingAddExercise = false } }
            }
        }
        .sheet(item: $setTarget) { target in ProgressaSetEditor(target: target) }
        .sheet(isPresented: $showingHealthPicker) {
            ProgressaHealthSessionPicker(around: workout?.createdAt ?? .now, title: "Link Apple Health") { session in
                await model.linkHealthSession(session, workoutId: workoutId)
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                Task { if await model.deleteWorkout(id: workoutId) { dismiss() } }
            }
        }
    }
}

private struct WorkoutTimesEditor: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let workout: ProgressaWorkout
    @State private var start: Date
    @State private var end: Date
    @State private var finished: Bool

    init(workout: ProgressaWorkout) {
        self.workout = workout
        _start = State(initialValue: workout.startedAt ?? workout.createdAt)
        _end = State(initialValue: workout.endedAt ?? max(workout.createdAt, .now))
        _finished = State(initialValue: !workout.isInProgress)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Started", selection: $start, in: ...Date.now)
                Toggle("Finished", isOn: $finished)
                if finished { DatePicker("Finished", selection: $end, in: start...max(start, .now)) }
                if !finished { Text("Without an end time, this workout stays in progress.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Workout Times")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.saveWorkoutTiming(id: workout.id, startedAt: start, endedAt: finished ? end : nil) { dismiss() } }
                    }.disabled(model.isChangingWorkout || (finished && end < start))
                }
            }
        }
    }
}

private struct WorkoutSequenceEditor: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var exercises: [ProgressaExerciseInput] = []
    @State private var rounds = 3
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(rounds) rounds", value: $rounds, in: 1...20)
                } footer: { Text("Complete these exercises in order, then repeat. Log your sets as you go.") }
                Section("Exercises in Each Round") {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, input in
                        HStack { Text("\(index + 1)").foregroundStyle(.secondary); Text(input.exercise.name) }
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button("Choose Exercise", systemImage: "plus") { picking = true }.disabled(exercises.count >= 12)
                }
                if exercises.count >= 2 {
                    Section("Preview") {
                        Text("\(exercises.map { $0.exercise.name }.joined(separator: " → "))")
                        Text("Repeat \(rounds) times · \(rounds * exercises.count) exercise blocks").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Sequence")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isChangingWorkout) }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await model.addSequence(workoutId: workoutID, exercises: exercises.map(\.exercise), rounds: rounds) { dismiss() }
                        }
                    }.disabled(exercises.count < 2 || model.isChangingWorkout)
                }
            }
            .sheet(isPresented: $picking) {
                ProgressaExercisePicker(configureSets: false) { input in exercises.append(input); picking = false }
            }
            .interactiveDismissDisabled(model.isChangingWorkout)
        }
    }
}

private struct ProgressaWorkoutEditor: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let workout: ProgressaWorkout?
    @State private var title: String
    @State private var createdAt: Date
    @State private var isSaving = false
    @State private var exercises: [ProgressaExerciseInput] = []
    @State private var showingExercisePicker = false
    @State private var selectedRoutineID: String?
    @State private var copyRoutineWeights = true
    let onCreated: ((String) -> Void)?

    init(workout: ProgressaWorkout? = nil, onCreated: ((String) -> Void)? = nil) {
        self.workout = workout
        self.onCreated = onCreated
        _title = State(initialValue: workout?.title ?? "Workout")
        _createdAt = State(initialValue: workout?.createdAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Workout title", text: $title)
                DatePicker("Date", selection: $createdAt)
                if workout == nil {
                    Section("Template") {
                        Picker("From routine", selection: $selectedRoutineID) {
                            Text("No routine").tag(nil as String?)
                            ForEach(model.routines) { routine in Text(routine.name).tag(Optional(routine.id)) }
                        }
                        if selectedRoutineID != nil {
                            Toggle("Copy weights", isOn: $copyRoutineWeights)
                            Text(copyRoutineWeights ? "Copies reps and weights" : "Copies reps only")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Exercises") {
                        ForEach(exercises) { item in
                            VStack(alignment: .leading) {
                                Text(item.exercise.name).font(.headline)
                                Text("\(item.sets.count) set\(item.sets.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                            }
                        }.onDelete { exercises.remove(atOffsets: $0) }.onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                        Button { showingExercisePicker = true } label: { Label("Add exercise", systemImage: "plus.circle") }
                    }
                }
            }
            .navigationTitle(workout == nil ? "New workout" : "Edit workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let workout {
                                let success = await model.updateWorkout(id: workout.id, title: cleanTitle, createdAt: createdAt)
                                isSaving = false
                                if success { dismiss() }
                            } else {
                                let id = await model.createWorkout(title: cleanTitle, createdAt: createdAt, exercises: exercises)
                                isSaving = false
                                if let id { onCreated?(id); dismiss() }
                            }
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ProgressaExercisePicker { input in exercises.append(input); showingExercisePicker = false }
            }
            .task { if workout == nil && model.routines.isEmpty { await model.loadRoutines() } }
            .onChange(of: selectedRoutineID) { id in Task { await applyRoutine(id) } }
            .onChange(of: copyRoutineWeights) { _ in Task { await applyRoutine(selectedRoutineID) } }
        }
    }

    @MainActor
    private func applyRoutine(_ id: String?) async {
        guard let id else { return }
        let detail: ProgressaRoutineDetail?
        if let cached = model.routineDetails[id] { detail = cached }
        else { detail = await model.loadRoutine(id: id) }
        guard let detail else { return }
        exercises = detail.workoutExercises(copyWeights: copyRoutineWeights)
        title = detail.routine.name
    }
}

private struct SetEditTarget: Identifiable {
    let workoutId: String
    let block: ProgressaExercise
    let workoutSet: ProgressaWorkoutSet?
    var id: String { workoutSet?.id ?? "new-\(block.id)" }
}

/// One set within the workout overview: weight and reps are editable directly in the row and
/// autosave (debounced) instead of requiring a modal, per the workout-flow requirement that
/// weight/reps live and are edited at the set level, not just the exercise level.
private struct InlineSetRow: View {
    @EnvironmentObject private var model: ProgressaModel
    let workoutId: String
    let blockId: String
    let set: ProgressaWorkoutSet
    let index: Int
    let onDelete: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var isSaving = false

    /// Whether the fields differ from the saved set — drives the manual save button, offered
    /// alongside autosave so the user can confirm a change was captured instead of just
    /// trusting the debounce timer.
    private var displayedAddedWeight: String {
        set.addedWeightKg.map { formattedNumber(model.workoutWeightForDisplay($0)) } ?? ""
    }

    private var isDirty: Bool {
        weightText != displayedAddedWeight || parsedInt(repsText) != set.reps
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Set \(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            if set.isWarmup { Text("W").font(.caption2.bold()).foregroundStyle(.orange) }
            TextField(model.workoutWeightUnit, text: $weightText)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text(model.workoutWeightUnit).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            TextField("Reps", text: $repsText)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(width: 40)
            Text("reps").font(.caption2).foregroundStyle(.secondary)
            if isSaving {
                ProgressView().controlSize(.mini).frame(width: 20)
            } else if isDirty {
                Button { Task { await commitIfChanged() } } label: { Image(systemName: "checkmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.green)
            }
            Button(action: onDelete) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.red.opacity(0.8))
        }
        .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
            if let base = set.baseWeightKg, base > 0, let total = set.weightKg {
                Text("Base \(model.workoutWeightText(base)) + added \(model.workoutWeightText(set.addedWeightKg ?? 0)) = \(model.workoutWeightText(total))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            weightText = displayedAddedWeight
            repsText = set.reps.map(String.init) ?? ""
        }
        .task(id: "\(weightText)|\(repsText)") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await commitIfChanged()
        }
    }

    private func commitIfChanged() async {
        guard isDirty else { return }
        guard weightText.isEmpty || (parsedDouble(weightText).map { $0.isFinite && $0 >= 0 } ?? false) else { return }
        let newWeightKg = weightText == displayedAddedWeight ? set.addedWeightKg : parsedDouble(weightText).map(model.workoutWeightForStorage)
        let newReps = parsedInt(repsText)
        guard let newReps, newReps > 0 else { return }
        let input = ProgressaSetInput(weightKg: (set.baseWeightKg ?? 0) > 0 ? (newWeightKg ?? 0) + (set.baseWeightKg ?? 0) : newWeightKg, reps: newReps, rir: set.rir, side: set.side, isWarmup: set.isWarmup)
        guard input.isValidForEntry else { return }
        isSaving = true
        _ = await model.updateSet(input, workoutId: workoutId, blockId: blockId, setId: set.id)
        isSaving = false
    }
}

private func formattedNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
}

/// Step 1 of the add-exercise wizard: search-first selection. Per design, the user is never
/// shown the full unfiltered catalogue — results only appear once they type a query.
private struct ProgressaExercisePicker: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ProgressaExerciseLibraryItem] = []
    @State private var isSearching = false
    @State private var path: [ProgressaExerciseLibraryItem] = []
    @State private var customName = ""
    @State private var customWeightType: ProgressaWeightType = .standard
    @State private var isCreatingCustom = false
    var configureSets = true
    let onSave: (ProgressaExerciseInput) -> Void

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search exercises", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("exerciseSearch")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Clear search").buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                Section("Exercise") {
                    if trimmedQuery.isEmpty {
                        Label("Search for an exercise by name.", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    } else if isSearching {
                        ProgressView()
                    } else if results.isEmpty {
                        Text("No exercises match “\(trimmedQuery)”.").foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { exercise in
                            Button {
                                if configureSets { path.append(exercise) }
                                else { onSave(ProgressaExerciseInput(exercise: exercise, sets: [])) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    if let group = exercise.muscleGroup { Text(group).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                DisclosureGroup("Create Custom Exercise") {
                    TextField("Exercise name", text: $customName)
                    Picker("Weight type", selection: $customWeightType) {
                        Text("Standard").tag(ProgressaWeightType.standard)
                        Text("Bodyweight").tag(ProgressaWeightType.bodyweight)
                        Text("Assisted").tag(ProgressaWeightType.assisted)
                    }
                    Button("Create and continue") {
                        Task {
                            isCreatingCustom = true
                            if let created = await model.createCustomExercise(name: customName, weightType: customWeightType) {
                                customName = ""
                                if configureSets { path.append(created) }
                                else { onSave(ProgressaExerciseInput(exercise: created, sets: [])) }
                            }
                            isCreatingCustom = false
                        }
                    }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingCustom)
                }
            }
            .navigationTitle("Add exercise")
            .task(id: query) {
                guard !trimmedQuery.isEmpty else { results = []; isSearching = false; return }
                isSearching = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let found = await model.searchExercises(trimmedQuery)
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
            }
            .navigationDestination(for: ProgressaExerciseLibraryItem.self) { exercise in
                ExerciseSetupStep(exercise: exercise) { input in onSave(input) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Step 2 of the add-exercise wizard: configure the initial weight/reps and how many sets to
/// create, with the most recently logged weight shown as reference and default.
private struct DraftSetRow: Identifiable {
    let id = UUID()
    var weightText: String
    var repsText: String
    var suggestedWeightText: String = ""
    var suggestedRepsText: String = ""
}

/// Step 2 of the add-exercise wizard: an editable per-set table (weight + reps), with previous
/// workout values shown as suggestions so new entries are still deliberate user input.
private struct ExerciseBaseSection: View {
    @EnvironmentObject private var model: ProgressaModel
    let exerciseID: String
    @State private var value = ""
    @State private var saved: Double?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Section {
            HStack {
                Text("Equipment base")
                Spacer()
                TextField("0", text: $value).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing).accessibilityLabel("Equipment base weight")
                Text(model.workoutWeightUnit)
            }
            Button("Save base for new sets") {
                guard let number = parsedDouble(value), number.isFinite, number >= 0 else { return }
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        try await model.setExerciseBase(model.workoutWeightForStorage(number), id: exerciseID)
                        saved = number
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }.disabled(busy || parsedDouble(value) == nil || (parsedDouble(value) ?? -1) < 0 || parsedDouble(value) == saved)
            if let error { Text(error).foregroundStyle(.red) }
        } footer: { Text("Enter the added weight for each set. The total includes this base.") }
        .task(id: exerciseID) {
            do {
                let kg = try await model.exerciseBase(exerciseID)
                value = String(model.workoutWeightForDisplay(kg))
                saved = parsedDouble(value)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ExerciseSetupStep: View {
    @EnvironmentObject private var model: ProgressaModel
    let exercise: ProgressaExerciseLibraryItem
    let onSave: (ProgressaExerciseInput) -> Void

    @State private var rows: [DraftSetRow] = []
    @State private var rir = ""
    @State private var side = ""
    @State private var isWarmup = false
    @State private var lastUsedWeightKg: Double?
    @State private var loadedPreviousStructure = false
    @State private var isLoadingHistory = true

    var body: some View {
        Form {
            Section {
                Text(exercise.name).font(.headline)
                if let group = exercise.muscleGroup { Text(group).font(.caption).foregroundStyle(.secondary) }
            }
            ExerciseBaseSection(exerciseID: exercise.id)
            Section("Previous data") {
                if isLoadingHistory {
                    ProgressView()
                } else if let lastUsedWeightKg {
                    Label(
                        loadedPreviousStructure
                            ? "Previous set values are suggested below. Last used: \(model.workoutWeightText(lastUsedWeightKg))"
                            : "Last used: \(model.workoutWeightText(lastUsedWeightKg))",
                        systemImage: "clock.arrow.circlepath"
                    ).font(.footnote)
                } else {
                    Text("No previous data available yet.").foregroundStyle(.secondary)
                }
            }
            Section("Sets · added weight") {
                ForEach($rows) { $row in
                    HStack {
                        Text("Set \(rowNumber(row))").frame(width: 44, alignment: .leading).foregroundStyle(.secondary)
                        TextField(row.suggestedWeightText.isEmpty ? "Weight" : row.suggestedWeightText, text: $row.weightText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text(model.workoutWeightUnit).font(.caption2).foregroundStyle(.secondary)
                        TextField(row.suggestedRepsText.isEmpty ? "Reps" : row.suggestedRepsText, text: $row.repsText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 44)
                        Text("reps").font(.caption2).foregroundStyle(.secondary)
                    }
                }.onDelete { rows.remove(atOffsets: $0) }
                Button {
                    rows.append(DraftSetRow(
                        weightText: "",
                        repsText: "",
                        suggestedWeightText: rows.last?.suggestedWeightText ?? "",
                        suggestedRepsText: rows.last?.suggestedRepsText ?? ""
                    ))
                } label: { Label("Add set", systemImage: "plus.circle") }
            }
            Section("Advanced (applies to all sets above)") {
                TextField("RIR (optional)", text: $rir).keyboardType(.decimalPad)
                Picker("Side", selection: $side) {
                    Text("Both").tag(""); Text("Left").tag("L"); Text("Right").tag("R")
                }
                Toggle("Warm-up sets", isOn: $isWarmup)
            }
        }
        .navigationTitle("Set details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let previous = model.previousSetStructure(exerciseId: exercise.id)
            async let lastWeight = model.lastUsedWeight(exerciseId: exercise.id)
            let (previousSets, weight) = await (previous, lastWeight)
            lastUsedWeightKg = weight
            if !previousSets.isEmpty {
                loadedPreviousStructure = true
                rows = previousSets.map {
                    DraftSetRow(
                        weightText: "",
                        repsText: "",
                        suggestedWeightText: $0.weightKg.map { formattedNumber(model.workoutWeightForDisplay($0)) } ?? "",
                        suggestedRepsText: $0.reps.map(String.init) ?? ""
                    )
                }
            } else {
                let defaultWeightText = weight.map { formattedNumber(model.workoutWeightForDisplay($0)) } ?? ""
                rows = (0..<3).map { _ in DraftSetRow(weightText: "", repsText: "", suggestedWeightText: defaultWeightText) }
            }
            isLoadingHistory = false
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add to workout") {
                    onSave(ProgressaExerciseInput(exercise: exercise, sets: setInputs))
                }.disabled(!isValid)
            }
        }
    }

    private func rowNumber(_ row: DraftSetRow) -> Int { (rows.firstIndex { $0.id == row.id } ?? 0) + 1 }

    private var setInputs: [ProgressaSetInput] {
        rows.map { row in
            ProgressaSetInput(
                weightKg: parsedDouble(row.weightText).map(model.workoutWeightForStorage), reps: parsedInt(row.repsText),
                rir: parsedDouble(rir), side: side.isEmpty ? nil : side, isWarmup: isWarmup
            )
        }
    }

    private var isValid: Bool { !rows.isEmpty && setInputs.allSatisfy(\.isValidForEntry) }
}

private struct ProgressaSetEditor: View {
    @EnvironmentObject private var model: ProgressaModel
    @Environment(\.dismiss) private var dismiss
    let target: SetEditTarget
    @State private var weight: String
    @State private var reps: String
    @State private var rir: String
    @State private var side: String
    @State private var isWarmup: Bool
    @State private var isSaving = false
    @State private var didPrepareWeight = false

    init(target: SetEditTarget) {
        self.target = target
        _weight = State(initialValue: target.workoutSet?.addedWeightKg.map { String($0) } ?? "")
        _reps = State(initialValue: target.workoutSet?.reps.map(String.init) ?? "")
        _rir = State(initialValue: target.workoutSet?.rir.map { String($0) } ?? "")
        _side = State(initialValue: target.workoutSet?.side ?? "")
        _isWarmup = State(initialValue: target.workoutSet?.isWarmup ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if target.workoutSet == nil { ExerciseBaseSection(exerciseID: target.block.exerciseId) }
                Section(target.block.name) {
                    TextField("Added weight (\(model.workoutWeightUnit))", text: $weight).keyboardType(.decimalPad)
                    TextField("Reps", text: $reps).keyboardType(.numberPad)
                    TextField("RIR (optional)", text: $rir).keyboardType(.decimalPad)
                    Picker("Side", selection: $side) {
                        Text("Both").tag(""); Text("Left").tag("L"); Text("Right").tag("R")
                    }
                    Toggle("Warm-up set", isOn: $isWarmup)
                }
            }
            .navigationTitle(target.workoutSet == nil ? "Add set" : "Edit set")
            .onAppear {
                guard !didPrepareWeight else { return }
                didPrepareWeight = true
                if let kilograms = target.workoutSet?.addedWeightKg {
                    weight = String(model.workoutWeightForDisplay(kilograms))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let input = ProgressaSetInput(
                                weightKg: (target.workoutSet?.baseWeightKg ?? 0) > 0 ? model.workoutWeightForStorage(parsedDouble(weight) ?? 0) + (target.workoutSet?.baseWeightKg ?? 0) : parsedDouble(weight).map(model.workoutWeightForStorage), reps: parsedInt(reps), rir: parsedDouble(rir),
                                side: side.isEmpty ? nil : side, isWarmup: isWarmup
                            )
                            let success = if let set = target.workoutSet {
                                await model.updateSet(input, workoutId: target.workoutId, blockId: target.block.id, setId: set.id)
                            } else {
                                await model.addSet(input, workoutId: target.workoutId, blockId: target.block.id)
                            }
                            isSaving = false
                            if success { dismiss() }
                        }
                    }.disabled(isSaving || parsedInt(reps) == nil || (parsedInt(reps) ?? 0) <= 0)
                }
            }
        }
    }
}

private func parsedDouble(_ value: String) -> Double? {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    return cleaned.isEmpty ? nil : Double(cleaned)
}

private func parsedInt(_ value: String) -> Int? {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : Int(cleaned)
}

private struct QuantivitaConsentView: View {
    @EnvironmentObject private var model: ProgressaModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.circle.fill").font(.system(size: 62)).foregroundStyle(.purple)
                Text("Connect Quantivita?").font(.title.bold())
                Text("Quantivita may read your Progressa workouts, exercises, sets, reps, weight and volume.").multilineTextAlignment(.center)
                Button("Allow") { Task { await model.finishQuantivitaConnect(approved: true) } }.buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { Task { await model.finishQuantivitaConnect(approved: false) } }
            }.padding().navigationTitle("App connection")
        }.interactiveDismissDisabled()
    }
}
