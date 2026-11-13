import AuthenticationServices
import CoreLocation
import Foundation
import UIKit

@MainActor
final class ProgressaModel: ObservableObject {
    enum ProfileState: Equatable { case loading, required, complete, failed }

    @Published var session: ProgressaSession?
    @Published var profile: ProgressaProfile?
    @Published var profileState: ProfileState = .loading
    @Published var workouts: [ProgressaWorkout] = [] { didSet { liveActivity.sync(activeWorkout) } }
    @Published var workoutRoute: String?
    @Published private(set) var isChangingWorkout = false
    private let liveActivity = WorkoutLiveActivity()
    var activeWorkout: ProgressaWorkout? { workouts.first(where: \.isInProgress) }
    func syncLiveActivity() { liveActivity.sync(activeWorkout) }
    @Published var routines: [ProgressaRoutine] = []
    @Published var routineDetails: [String: ProgressaRoutineDetail] = [:]
    @Published var healthSessions: [ProgressaHealthSession] = []
    @Published var healthMetadata: [String: ProgressaHealthMetadata] = [:]
    @Published var isLoadingHealth = false
    @Published var pendingConnect: QuantivitaConnectRequest?
    @Published var isLoading = false
    @Published var workoutSyncState: WorkoutSyncState = .idle
    @Published var statsSets: [ProgressaSetStat] = []
    @Published var cardioSessions: [ProgressaCardioSession] = []
    @Published var measurements: [ProgressaMeasurement] = []
    @Published var isLoadingStats = false
    @Published var isLoadingMeasurements = false
    @Published var message: String?
    @Published var isUploadingAvatar = false
    @Published var isRecoveringPassword = false

    private let client: ProgressaClient
    private let workoutService: ProgressaWorkoutServing
    private let workoutCache: WorkoutCache
    private let sessions: any ProgressaSessionStoring
    private let statsMeasurementsService: any ProgressaStatsMeasurementsServing
    private let routineService: any ProgressaRoutineServing
    private let healthKitService: ProgressaHealthKitService
    private let healthMetadataService: ProgressaHealthMetadataService
    private var sessionRefreshTask: Task<ProgressaSession, Error>?

    init(
        client: ProgressaClient = ProgressaClient(),
        workoutService: ProgressaWorkoutServing? = nil,
        workoutCache: WorkoutCache = WorkoutCache(),
        sessions: any ProgressaSessionStoring = ProgressaSessionStore(),
        statsMeasurementsService: any ProgressaStatsMeasurementsServing = StatsMeasurementsService(),
        routineService: any ProgressaRoutineServing = ProgressaRoutineService(),
        healthKitService: ProgressaHealthKitService = ProgressaHealthKitService(),
        healthMetadataService: ProgressaHealthMetadataService = ProgressaHealthMetadataService()
    ) {
        self.client = client
        self.workoutService = workoutService ?? client
        self.workoutCache = workoutCache
        self.sessions = sessions
        self.statsMeasurementsService = statsMeasurementsService
        self.routineService = routineService
        self.healthKitService = healthKitService
        self.healthMetadataService = healthMetadataService
    }

    func bootstrap() async {
        session = sessions.load()
        if let current = session {
            do {
                let valid = current.expiresAt.timeIntervalSinceNow < 300 ? try await client.refresh(current) : current
                try sessions.save(valid)
                session = valid
                loadCachedWorkouts(userId: valid.userId)
                await loadProfile()
            } catch {
                sessions.clear()
                session = nil
                profile = nil
                profileState = .loading
                message = "Your session expired. Sign in again."
            }
        }
    }

    func signIn(email: String, password: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@"), !password.isEmpty else {
            message = "Enter a valid email address and password."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.signIn(email: cleanEmail, password: password)
            try sessions.save(value)
            session = value
            loadCachedWorkouts(userId: value.userId)
            await loadProfile()
        } catch {
            if session != nil { profileState = .failed }
            message = friendly(error)
        }
    }

    func signUp(email: String, password: String, confirmation: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else { message = "Enter a valid email address."; return }
        guard password.count >= 8 else { message = "Use a password of at least 8 characters."; return }
        guard password == confirmation else { message = "The passwords do not match."; return }
        isLoading = true; defer { isLoading = false }
        do {
            if let value = try await client.signUp(email: cleanEmail, password: password) {
                try sessions.save(value); session = value; await loadProfile()
            } else {
                message = "Account created. Confirm your email address, then sign in."
            }
        } catch { message = friendly(error) }
    }

    func requestPasswordReset(email: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else { message = "Enter your email address first."; return }
        isLoading = true; defer { isLoading = false }
        do {
            try await client.requestPasswordReset(email: cleanEmail)
            message = "Check your email and open the Progressa password reset link."
        } catch { message = friendly(error) }
    }

    func updateRecoveredPassword(_ password: String, confirmation: String) async -> Bool {
        guard password.count >= 8 else { message = "Use a password of at least 8 characters."; return false }
        guard password == confirmation else { message = "The passwords do not match."; return false }
        guard let session else { message = "The password reset link is no longer valid."; return false }
        isLoading = true; defer { isLoading = false }
        do {
            try await client.updatePassword(password, session: session)
            isRecoveringPassword = false
            signOut()
            message = "Password updated. Sign in with your new password."
            return true
        } catch { message = friendly(error); return false }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.signInWithApple(idToken: idToken, nonce: nonce)
            try sessions.save(value)
            session = value
            loadCachedWorkouts(userId: value.userId)
            let existing = try await client.fetchProfile(session: value)
            if existing?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
               let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                profile = try await client.upsertProfile(
                    ProgressaProfile(
                        userId: value.userId, fullName: name,
                        country: existing?.country, birthdate: existing?.birthdate
                    ),
                    session: value
                )
            } else {
                profile = existing
            }
            updateProfileState()
            if profileState == .complete { await refreshWorkouts() }
        } catch {
            if session != nil { profileState = .failed }
            message = friendly(error)
        }
    }

    func appleSignInFailed(_ error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            message = "Apple sign-in was cancelled."
        } else {
            message = "Apple sign-in failed. Please try again."
        }
    }

    func loadProfile() async {
        guard let session else { return }
        profileState = .loading
        do {
            profile = try await client.fetchProfile(session: session)
            updateProfileState()
            if profileState == .complete { await refreshWorkouts() }
        } catch {
            profileState = .failed
            message = "Your profile could not be loaded. \(friendly(error))"
        }
    }

    func saveProfile(fullName: String, country: String, birthdate: Date) async {
        guard let session else { return }
        let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (session.isAppleUser || !cleanName.isEmpty), cleanCountry.count == 2 else {
            message = session.isAppleUser
                ? "Select your country and birthdate."
                : "Enter your name, country and birthdate."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await client.upsertProfile(
                ProgressaProfile(
                    userId: session.userId, fullName: cleanName.isEmpty ? nil : cleanName,
                    country: cleanCountry, birthdate: birthdate, heightCm: profile?.heightCm,
                    unitSystem: profile?.unitSystem, sex: profile?.sex, profileVisibility: profile?.profileVisibility
                ),
                session: session
            )
            updateProfileState()
            if profileState == .complete { await refreshWorkouts() }
        } catch { message = friendly(error) }
    }

    func saveProfileSettings(_ value: ProgressaProfile) async -> Bool {
        guard let session, value.userId == session.userId else { return false }
        do { profile = try await client.upsertProfile(value, session: session); updateProfileState(); return true }
        catch { message = friendly(error); return false }
    }

    func uploadAvatar(jpegData: Data) async {
        guard let session = await validWorkoutSession() else { return }
        isUploadingAvatar = true; defer { isUploadingAvatar = false }
        do {
            profile?.avatarPath = try await ProgressaAvatarService.shared.uploadJPEG(
                jpegData, oldPath: profile?.avatarPath, session: session
            )
        } catch { message = "Profile photo upload failed. \(friendly(error))" }
    }

    func removeAvatar() async {
        guard let session = await validWorkoutSession() else { return }
        isUploadingAvatar = true; defer { isUploadingAvatar = false }
        do {
            try await ProgressaAvatarService.shared.remove(path: profile?.avatarPath, session: session)
            profile?.avatarPath = nil
        } catch { message = "Profile photo could not be removed. \(friendly(error))" }
    }

    func deleteAccount() async -> Bool {
        guard let session else { return false }
        isLoading = true; defer { isLoading = false }
        do { try await client.deleteAccount(session: session); signOut(); return true }
        catch { message = "Account deletion failed. \(friendly(error))"; return false }
    }

    func signOut() {
        if let userId = session?.userId { workoutCache.clear(userId: userId) }
        sessions.clear()
        session = nil
        profile = nil
        profileState = .loading
        workoutRoute = nil
        workouts = []
        routines = []
        routineDetails = [:]
        healthSessions = []
        healthMetadata = [:]
        statsSets = []
        cardioSessions = []
        measurements = []
        Task { await ProgressaAvatarService.shared.clearCache() }
    }

    var statsSummary: ProgressaStatsSummary { .calculate(statsSets) }

    var measurementUnitSystem: MeasurementUnitSystem {
        MeasurementUnitSystem(rawValue: profile?.unitSystem ?? "metric") ?? .metric
    }

    var workoutWeightUnit: String { measurementUnitSystem == .imperial ? "lb" : "kg" }

    func workoutWeightForDisplay(_ kilograms: Double) -> Double {
        measurementUnitSystem == .imperial ? kilograms * 2.204_622_621_8 : kilograms
    }

    func workoutWeightForStorage(_ displayed: Double) -> Double {
        measurementUnitSystem == .imperial ? displayed / 2.204_622_621_8 : displayed
    }

    func workoutWeightText(_ kilograms: Double) -> String {
        "\(workoutWeightForDisplay(kilograms).formatted()) \(workoutWeightUnit)"
    }

    func refreshStats() async {
        guard let session, !isLoadingStats else { return }
        isLoadingStats = true
        defer { isLoadingStats = false }
        do {
            statsSets = try await statsMeasurementsService.fetchAllSets(session: session)
        } catch {
            message = "Strength statistics could not be loaded. \(friendly(error))"
        }
        do {
            cardioSessions = try await statsMeasurementsService.fetchCardio(session: session)
        } catch {
            if statsSets.isEmpty { message = "Cardio statistics could not be loaded. \(friendly(error))" }
        }
    }

    func refreshMeasurements() async {
        guard let session, !isLoadingMeasurements else { return }
        isLoadingMeasurements = true
        defer { isLoadingMeasurements = false }
        do {
            measurements = try await statsMeasurementsService.fetchMeasurements(session: session)
        } catch { message = "Measurements could not be loaded. \(friendly(error))" }
    }

    @discardableResult
    func addMeasurement(type: ProgressaMeasurementType, displayedValue: Double, measuredAt: Date, note: String?) async -> Bool {
        guard let session, displayedValue.isFinite, type.displayRange.contains(displayedValue) else {
            let unit = measurementUnitSystem.unit(for: type)
            message = "Enter a value between \(type.displayRange.lowerBound.formatted()) and \(type.displayRange.upperBound.formatted()) \(unit)."
            return false
        }
        isLoadingMeasurements = true
        defer { isLoadingMeasurements = false }
        do {
            let stored = measurementUnitSystem.storageValue(displayedValue, type: type)
            let value = try await statsMeasurementsService.addMeasurement(
                type: type, value: stored, measuredAt: measuredAt, note: note, session: session
            )
            replaceMeasurement(value)
            return true
        } catch { message = "Measurement could not be saved. \(friendly(error))"; return false }
    }

    @discardableResult
    func updateMeasurementNote(id: String, note: String?) async -> Bool {
        guard let session else { return false }
        do {
            replaceMeasurement(try await statsMeasurementsService.updateMeasurementNote(id: id, note: note, session: session))
            return true
        } catch { message = "The note could not be saved. \(friendly(error))"; return false }
    }

    func deleteMeasurement(id: String) async {
        guard let session else { return }
        do {
            try await statsMeasurementsService.deleteMeasurement(id: id, session: session)
            measurements.removeAll { $0.id == id }
        } catch { message = "The measurement could not be deleted. \(friendly(error))" }
    }

    func refreshWorkouts() async {
        guard let session = await validWorkoutSession() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let existingDetails = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.exercises) })
            workouts = try await workoutService.fetchWorkouts(session: session).map { header in
                var workout = header
                if let exercises = existingDetails[header.id], !exercises.isEmpty { workout.exercises = exercises }
                return workout
            }
            workouts.sort { $0.createdAt > $1.createdAt }
            let syncedAt = Date.now
            try workoutCache.save(workouts, userId: session.userId, at: syncedAt)
            workoutSyncState = .fresh(syncedAt)
        } catch {
            if workouts.isEmpty { loadCachedWorkouts(userId: session.userId) }
            workoutSyncState = .cached(workoutCache.load(userId: session.userId)?.savedAt)
            message = workouts.isEmpty
                ? "Workouts could not be loaded. Check your connection and try again."
                : "Offline: cached workouts are still shown."
        }
    }

    func loadRoutines() async {
        guard let session = await validWorkoutSession() else { return }
        do { routines = try await routineService.list(session: session) }
        catch { message = "Routines could not be loaded. \(friendly(error))" }
    }

    func loadHealthMetadata(workoutId: String) async {
        guard let session = await validWorkoutSession() else { return }
        do {
            if let value = try await healthMetadataService.metadata(workoutId: workoutId, session: session) {
                healthMetadata[workoutId] = value
            } else { healthMetadata[workoutId] = nil }
        } catch { message = "Apple Health details could not be loaded." }
    }

    /// Local Apple Health GPS route for a linked/imported workout, matched on its time window.
    func healthRoute(for metadata: ProgressaHealthMetadata) async -> [CLLocationCoordinate2D] {
        await healthKitService.routeCoordinates(matching: metadata.start, end: metadata.end)
    }

    func prepareRecordingAuthorization() async {
        try? await healthKitService.requestRecordingAuthorization()
    }

    func saveRecordedWorkout(activity: RecordingActivity, start: Date, end: Date, distanceMeters: Double, locations: [CLLocation]) async -> Bool {
        do {
            try await healthKitService.saveRecordedWorkout(activity: activity, start: start, end: end, distanceMeters: distanceMeters, locations: locations)
            return true
        } catch {
            message = "The recorded workout could not be saved to Apple Health."
            return false
        }
    }

    func browseHealthSessions(around: Date) async {
        isLoadingHealth = true; defer { isLoadingHealth = false }
        do {
            try await healthKitService.requestAuthorization()
            healthSessions = try await healthKitService.sessions(around: around, days: 2)
        } catch { healthSessions = []; message = "Apple Health access is required to browse workouts." }
    }

    func linkHealthSession(_ health: ProgressaHealthSession, workoutId: String) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        isLoadingHealth = true; defer { isLoadingHealth = false }
        do {
            let heartRate = try await healthKitService.heartRate(start: health.start, end: health.end)
            healthMetadata[workoutId] = try await healthMetadataService.link(
                workoutId: workoutId, health: health, heartRate: heartRate, session: session
            )
            return true
        } catch { message = "The Apple Health workout could not be linked. \(friendly(error))"; return false }
    }

    func unlinkHealthSession(workoutId: String) async {
        guard let session = await validWorkoutSession() else { return }
        do { try await healthMetadataService.unlink(workoutId: workoutId, session: session); healthMetadata[workoutId] = nil }
        catch { message = "The Apple Health link could not be removed." }
    }

    func importHealthSession(_ health: ProgressaHealthSession) async -> String? {
        guard let session = await validWorkoutSession() else { return nil }
        isLoadingHealth = true; defer { isLoadingHealth = false }
        do {
            let heartRate = try await healthKitService.heartRate(start: health.start, end: health.end)
            let workout = try await healthMetadataService.importWorkout(health: health, heartRate: heartRate, session: session)
            replace(workout)
            try workoutCache.save(workouts, userId: session.userId)
            await loadHealthMetadata(workoutId: workout.id)
            return workout.id
        } catch { message = "The Apple Health workout could not be imported. \(friendly(error))"; return nil }
    }

    func loadRoutine(id: String) async -> ProgressaRoutineDetail? {
        guard let session = await validWorkoutSession(),
              let routine = routines.first(where: { $0.id == id }) else { return nil }
        do {
            let detail = try await routineService.detail(routine, session: session)
            routineDetails[id] = detail
            return detail
        } catch { message = "The routine could not be loaded. \(friendly(error))"; return nil }
    }

    func createRoutine(name: String) async -> ProgressaRoutine? {
        guard let session = await validWorkoutSession() else { return nil }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        do {
            let routine = try await routineService.create(name: clean, session: session)
            routines.insert(routine, at: 0)
            routineDetails[routine.id] = ProgressaRoutineDetail(routine: routine, exercises: [], sets: [])
            return routine
        } catch { message = "The routine could not be created. \(friendly(error))"; return nil }
    }

    func renameRoutine(id: String, name: String) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        do {
            try await routineService.rename(id: id, name: clean, session: session)
            if let index = routines.firstIndex(where: { $0.id == id }) { routines[index].name = clean }
            if var detail = routineDetails[id] { detail.routine.name = clean; routineDetails[id] = detail }
            return true
        } catch { message = "The routine could not be renamed. \(friendly(error))"; return false }
    }

    func deleteRoutine(id: String) async {
        guard let session = await validWorkoutSession() else { return }
        do {
            try await routineService.delete(id: id, session: session)
            routines.removeAll { $0.id == id }; routineDetails[id] = nil
        } catch { message = "The routine could not be deleted. \(friendly(error))" }
    }

    func addRoutineExercise(routineId: String, exercise: ProgressaExerciseLibraryItem) async -> Bool {
        guard let session = await validWorkoutSession(), var detail = routineDetails[routineId] else { return false }
        do {
            detail.exercises.append(try await routineService.addExercise(
                routineId: routineId, exercise: exercise, sortOrder: detail.exercises.count, session: session
            ))
            routineDetails[routineId] = detail
            return true
        } catch { message = "The exercise could not be added to the routine. \(friendly(error))"; return false }
    }

    func deleteRoutineExercise(routineId: String, entryId: String) async {
        guard let session = await validWorkoutSession(), var detail = routineDetails[routineId] else { return }
        do {
            try await routineService.deleteExercise(id: entryId, session: session)
            detail.exercises.removeAll { $0.id == entryId }
            detail.sets.removeAll { $0.routineExerciseId == entryId }
            routineDetails[routineId] = detail
        } catch { message = "The exercise could not be removed. \(friendly(error))" }
    }

    func moveRoutineExercises(routineId: String, from source: IndexSet, to destination: Int) async {
        guard let session = await validWorkoutSession(), var detail = routineDetails[routineId] else { return }
        let previous = detail.exercises
        detail.exercises.move(fromOffsets: source, toOffset: destination)
        for index in detail.exercises.indices { detail.exercises[index].sortOrder = index }
        routineDetails[routineId] = detail
        do { try await routineService.reorderExercises(detail.exercises, session: session) }
        catch { detail.exercises = previous; routineDetails[routineId] = detail; message = "The routine order could not be saved." }
    }

    func addRoutineSet(routineId: String, entryId: String, input: ProgressaSetInput) async -> Bool {
        guard input.isValidForEntry, let session = await validWorkoutSession(),
              var detail = routineDetails[routineId], let entry = detail.exercises.first(where: { $0.id == entryId }) else { return false }
        do {
            let order = detail.sets.filter { $0.routineExerciseId == entryId }.count
            detail.sets.append(try await routineService.addSet(
                routineId: routineId, entry: entry, input: input, sortOrder: order, session: session
            ))
            routineDetails[routineId] = detail
            return true
        } catch { message = "The routine set could not be added. \(friendly(error))"; return false }
    }

    func updateRoutineSet(routineId: String, setId: String, input: ProgressaSetInput) async -> Bool {
        guard input.isValidForEntry, let session = await validWorkoutSession(), var detail = routineDetails[routineId],
              let index = detail.sets.firstIndex(where: { $0.id == setId }) else { return false }
        do {
            try await routineService.updateSet(id: setId, input: input, session: session)
            detail.sets[index].reps = input.reps; detail.sets[index].weightKg = input.weightKg
            detail.sets[index].rir = input.rir.map(Int.init); detail.sets[index].side = input.side
            routineDetails[routineId] = detail
            return true
        } catch { message = "The routine set could not be updated. \(friendly(error))"; return false }
    }

    func deleteRoutineSet(routineId: String, setId: String) async {
        guard let session = await validWorkoutSession(), var detail = routineDetails[routineId] else { return }
        do {
            try await routineService.deleteSet(id: setId, session: session)
            detail.sets.removeAll { $0.id == setId }; routineDetails[routineId] = detail
        } catch { message = "The routine set could not be deleted. \(friendly(error))" }
    }

    func refreshWorkout(id: String) async {
        guard let session = await validWorkoutSession() else { return }
        do {
            guard let workout = try await workoutService.fetchWorkout(id: id, session: session) else { return }
            replace(workout)
            let syncedAt = Date.now
            try workoutCache.save(workouts, userId: session.userId, at: syncedAt)
            workoutSyncState = .fresh(syncedAt)
        } catch {
            workoutSyncState = .cached(workoutCache.load(userId: session.userId)?.savedAt)
        }
    }

    func createWorkout(title: String, createdAt: Date, exercises: [ProgressaExerciseInput]) async -> String? {
        if let activeWorkout {
            guard exercises.isEmpty else { message = "Finish your current workout before starting a routine."; return nil }
            return activeWorkout.id
        }
        guard !isChangingWorkout else { return nil }
        isChangingWorkout = true
        defer { isChangingWorkout = false }
        guard let session = await validWorkoutSession() else { return nil }
        guard exercises.allSatisfy({ $0.sets.allSatisfy(\.isValidForEntry) }) else {
            message = "Every set needs positive reps, non-negative weight and RIR between 0 and 10."
            return nil
        }
        var createdID: String?
        do {
            var workout = try await workoutService.createWorkout(title: title, createdAt: createdAt, session: session)
            createdID = workout.id
            for (index, input) in exercises.enumerated() {
                workout.exercises.append(try await workoutService.addExercise(
                    input, workoutId: workout.id, sortOrder: index, session: session
                ))
            }
            replace(workout)
            try? workoutCache.save(workouts, userId: session.userId)
            return workout.id
        } catch {
            if let createdID { try? await workoutService.deleteWorkout(id: createdID, session: session) }
            message = "The workout could not be saved. No partial workout was kept. \(friendly(error))"
            return nil
        }
    }

    @discardableResult
    func saveWorkoutTiming(id: String, startedAt: Date, endedAt: Date?) async -> Bool {
        guard !isChangingWorkout else { return false }
        isChangingWorkout = true
        defer { isChangingWorkout = false }
        guard let session = await validWorkoutSession() else { return false }
        guard startedAt <= .now, endedAt == nil || (endedAt! >= startedAt && endedAt! <= .now) else {
            message = "The end must be after the start, and workout times cannot be in the future."
            return false
        }
        do {
            var updated = try await workoutService.updateWorkoutTiming(id: id, startedAt: startedAt, endedAt: endedAt, session: session)
            updated.exercises = workouts.first(where: { $0.id == id })?.exercises ?? []
            replace(updated)
            try? workoutCache.save(workouts, userId: session.userId)
            return true
        } catch {
            message = "Workout times could not be saved. Keep the workout open and try again. \(friendly(error))"
            return false
        }
    }

    func addSequence(workoutId: String, exercises: [ProgressaExerciseLibraryItem], rounds: Int) async -> Bool {
        guard !isChangingWorkout else { return false }
        isChangingWorkout = true
        defer { isChangingWorkout = false }
        guard let session = await validWorkoutSession() else { return false }
        guard (2...12).contains(exercises.count), (1...20).contains(rounds) else { return false }
        do {
            try await workoutService.addSequence(workoutId: workoutId, exerciseIDs: exercises.map(\.id), rounds: rounds, session: session)
            await refreshWorkout(id: workoutId)
            return true
        } catch { message = "The sequence could not be added. \(friendly(error))"; return false }
    }

    func searchExercises(_ query: String) async -> [ProgressaExerciseLibraryItem] {
        guard let session = await validWorkoutSession() else { return [] }
        do { return try await workoutService.fetchExercises(query: query, session: session) }
        catch { message = "Exercises could not be loaded. \(friendly(error))"; return [] }
    }

    /// Weight from the most recent set logged for this exercise, shown as a reference/default
    /// when adding the exercise to a workout. `nil` when there is no prior history.
    func lastUsedWeight(exerciseId: String) async -> Double? {
        guard let session = await validWorkoutSession() else { return nil }
        return try? await workoutService.lastWeightForExercise(exerciseId, session: session)
    }

    /// Full set structure (weight + reps per set) from the exercise's most recent previous
    /// workout, offered as a starting-point suggestion in the add-exercise wizard.
    func previousSetStructure(exerciseId: String) async -> [ProgressaSetInput] {
        guard let session = await validWorkoutSession() else { return [] }
        return (try? await workoutService.previousSetStructure(exerciseId, session: session)) ?? []
    }

    func createCustomExercise(name: String, weightType: ProgressaWeightType) async -> ProgressaExerciseLibraryItem? {
        guard let session = await validWorkoutSession() else { return nil }
        do { return try await workoutService.createCustomExercise(name: name, weightType: weightType, session: session) }
        catch { message = "The custom exercise could not be created. \(friendly(error))"; return nil }
    }

    func renameCustomExercise(id: String, name: String) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        do { try await workoutService.renameCustomExercise(id: id, name: name, session: session); return true }
        catch { message = "The exercise could not be renamed. \(friendly(error))"; return false }
    }

    func updateCustomExerciseWeightType(id: String, weightType: ProgressaWeightType) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        do { try await workoutService.updateCustomExerciseWeightType(id: id, weightType: weightType, session: session); return true }
        catch { message = "The exercise could not be updated. \(friendly(error))"; return false }
    }

    func deleteCustomExercise(id: String) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        do { try await workoutService.deleteCustomExercise(id: id, session: session); return true }
        catch { message = "The exercise could not be deleted. \(friendly(error))"; return false }
    }

    @discardableResult
    func addExercise(_ input: ProgressaExerciseInput, workoutId: String) async -> Bool {
        guard let session = await validWorkoutSession(),
              let index = workouts.firstIndex(where: { $0.id == workoutId }) else { return false }
        guard input.sets.allSatisfy(\.isValidForEntry) else { message = "Enter valid set values."; return false }
        do {
            let exercise = try await workoutService.addExercise(
                input, workoutId: workoutId, sortOrder: workouts[index].exercises.count, session: session
            )
            workouts[index].exercises.append(exercise)
            try workoutCache.save(workouts, userId: session.userId)
            return true
        } catch { message = "The exercise could not be added. \(friendly(error))"; return false }
    }

    @discardableResult
    func addSet(_ input: ProgressaSetInput, workoutId: String, blockId: String) async -> Bool {
        guard let session = await validWorkoutSession(),
              let workoutIndex = workouts.firstIndex(where: { $0.id == workoutId }),
              let blockIndex = workouts[workoutIndex].exercises.firstIndex(where: { $0.id == blockId }) else { return false }
        guard input.isValidForEntry else { message = "Enter valid set values."; return false }
        do {
            let block = workouts[workoutIndex].exercises[blockIndex]
            let set = try await workoutService.addSet(input, workoutId: workoutId, block: block, session: session)
            workouts[workoutIndex].exercises[blockIndex].sets.append(set)
            try workoutCache.save(workouts, userId: session.userId)
            return true
        } catch { message = "The set could not be added. \(friendly(error))"; return false }
    }

    @discardableResult
    func updateSet(_ input: ProgressaSetInput, workoutId: String, blockId: String, setId: String) async -> Bool {
        guard let session = await validWorkoutSession(),
              let workoutIndex = workouts.firstIndex(where: { $0.id == workoutId }),
              let blockIndex = workouts[workoutIndex].exercises.firstIndex(where: { $0.id == blockId }),
              let setIndex = workouts[workoutIndex].exercises[blockIndex].sets.firstIndex(where: { $0.id == setId }) else { return false }
        guard input.isValidForEntry else { message = "Enter valid set values."; return false }
        do {
            workouts[workoutIndex].exercises[blockIndex].sets[setIndex] = try await workoutService.updateSet(input, setId: setId, session: session)
            try workoutCache.save(workouts, userId: session.userId)
            return true
        } catch { message = "The set could not be updated. \(friendly(error))"; return false }
    }

    func deleteSet(workoutId: String, blockId: String, setId: String) async {
        guard let session = await validWorkoutSession(),
              let workoutIndex = workouts.firstIndex(where: { $0.id == workoutId }),
              let blockIndex = workouts[workoutIndex].exercises.firstIndex(where: { $0.id == blockId }) else { return }
        do {
            try await workoutService.deleteSet(id: setId, session: session)
            workouts[workoutIndex].exercises[blockIndex].sets.removeAll { $0.id == setId }
            try workoutCache.save(workouts, userId: session.userId)
        } catch { message = "The set could not be deleted. \(friendly(error))" }
    }

    func deleteExercise(workoutId: String, blockId: String) async {
        guard let session = await validWorkoutSession(),
              let workoutIndex = workouts.firstIndex(where: { $0.id == workoutId }) else { return }
        do {
            try await workoutService.deleteExerciseBlock(id: blockId, workoutId: workoutId, session: session)
            workouts[workoutIndex].exercises.removeAll { $0.id == blockId }
            try workoutCache.save(workouts, userId: session.userId)
        } catch { message = "The exercise could not be deleted. \(friendly(error))" }
    }

    func moveExercises(workoutId: String, from source: IndexSet, to destination: Int) async {
        guard let session = await validWorkoutSession(),
              let workoutIndex = workouts.firstIndex(where: { $0.id == workoutId }) else { return }
        let original = workouts[workoutIndex].exercises
        workouts[workoutIndex].exercises.move(fromOffsets: source, toOffset: destination)
        for index in workouts[workoutIndex].exercises.indices { workouts[workoutIndex].exercises[index].sortOrder = index }
        do {
            try await workoutService.reorderExerciseBlocks(
                workoutId: workoutId, orderedBlockIds: workouts[workoutIndex].exercises.map(\.id), session: session
            )
            try workoutCache.save(workouts, userId: session.userId)
        } catch {
            workouts[workoutIndex].exercises = original
            message = "The exercise order could not be saved. \(friendly(error))"
        }
    }

    @discardableResult
    func updateWorkout(id: String, title: String, createdAt: Date) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        do {
            var updated = try await workoutService.updateWorkout(id: id, title: title, createdAt: createdAt, session: session)
            updated.exercises = workouts.first(where: { $0.id == id })?.exercises ?? []
            replace(updated)
            try workoutCache.save(workouts, userId: session.userId)
            return true
        } catch { message = "Editing a workout requires a connection. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func deleteWorkout(id: String) async -> Bool {
        guard let session = await validWorkoutSession() else { return false }
        do {
            try await workoutService.deleteWorkout(id: id, session: session)
            workouts.removeAll { $0.id == id }
            try workoutCache.save(workouts, userId: session.userId)
            return true
        } catch { message = "Deleting a workout requires a connection. \(error.localizedDescription)"; return false }
    }

    func handle(url: URL) {
        if url.scheme == "progressa", url.host == "workout", let id = url.pathComponents.dropFirst().first {
            workoutRoute = id
            return
        }
        if url.scheme == "progressa", url.host == "reset-callback" {
            Task { await beginPasswordRecovery(url) }
            return
        }
        guard let request = QuantivitaConnectRequest(url: url) else { return }
        pendingConnect = request
        if session == nil { message = "Sign in first; Quantivita connection will continue afterwards." }
    }

    private func beginPasswordRecovery(_ url: URL) async {
        let fragment = URLComponents(string: "progressa://reset?\(url.fragment ?? "")")
        let values = Dictionary(uniqueKeysWithValues: (fragment?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard values["type"] == "recovery", let access = values["access_token"], let refresh = values["refresh_token"] else {
            message = "This password reset link is invalid or expired."; return
        }
        do {
            let value = try await client.recoverySession(accessToken: access, refreshToken: refresh)
            try sessions.save(value); session = value; isRecoveringPassword = true
        } catch { message = friendly(error) }
    }

    func finishQuantivitaConnect(approved: Bool) async {
        guard let connect = pendingConnect else { return }
        guard approved else {
            returnToQuantivita(connect, query: ["error": "access_denied", "state": connect.state])
            pendingConnect = nil
            return
        }
        guard let session else { message = "Sign in to Progressa first."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let code = try await client.createQuantivitaCode(connect, session: session)
            returnToQuantivita(connect, query: ["code": code, "state": connect.state])
            pendingConnect = nil
        } catch { message = "Connection failed: \(error.localizedDescription)" }
    }

    private func returnToQuantivita(_ request: QuantivitaConnectRequest, query: [String: String]) {
        var components = URLComponents(url: request.redirectURI, resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let url = components.url { UIApplication.shared.open(url) }
    }

    private func loadCachedWorkouts(userId: String) {
        guard let cached = workoutCache.load(userId: userId) else { return }
        workouts = cached.workouts.sorted { $0.createdAt > $1.createdAt }
        workoutSyncState = .cached(cached.savedAt)
    }

    private func replace(_ workout: ProgressaWorkout) {
        workouts.removeAll { $0.id == workout.id }
        workouts.append(workout)
        workouts.sort { $0.createdAt > $1.createdAt }
    }

    func exerciseBase(_ id: String) async throws -> Double {
        guard let session = await validWorkoutSession() else { throw ProgressaClientError.invalidResponse }
        return try await client.exerciseBase(id, session: session)
    }

    func setExerciseBase(_ kg: Double, id: String) async throws {
        guard kg.isFinite, kg >= 0, let session = await validWorkoutSession() else { throw ProgressaClientError.invalidResponse }
        try await client.setExerciseBase(kg, id: id, session: session)
    }

    private func validWorkoutSession() async -> ProgressaSession? {
        guard let current = session else { return nil }
        guard current.expiresAt.timeIntervalSinceNow < 300 else { return current }
        let task: Task<ProgressaSession, Error>
        if let active = sessionRefreshTask {
            task = active
        } else {
            let created = Task { try await client.refresh(current) }
            sessionRefreshTask = created
            task = created
        }
        do {
            let refreshed = try await task.value
            sessionRefreshTask = nil
            try sessions.save(refreshed)
            session = refreshed
            return refreshed
        } catch {
            sessionRefreshTask = nil
            message = "Your session expired. Sign in again."
            signOut()
            return nil
        }
    }

    private func replaceMeasurement(_ measurement: ProgressaMeasurement) {
        measurements.removeAll { $0.id == measurement.id }
        measurements.append(measurement)
        measurements.sort { $0.measuredAt > $1.measuredAt }
    }

    private func updateProfileState() {
        profileState = profile?.isComplete(appleUser: session?.isAppleUser == true) == true ? .complete : .required
    }

    private func friendly(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
                ? "The request timed out. Check your connection and try again."
                : "Progressa could not reach the server. Check your connection."
        }
        return error.localizedDescription
    }
}
