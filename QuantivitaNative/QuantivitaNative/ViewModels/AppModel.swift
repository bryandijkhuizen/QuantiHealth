import CoreLocation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Stage { case authentication, permissions, dashboard }

    @Published var stage: Stage = .authentication
    @Published var summary = HealthSummary()
    @Published var workouts: [Workout] = []
    @Published var weightHistory: [WeightSample] = []
    @Published var recovery = RecoveryScorer.calculate(summary: HealthSummary())
    @Published var dailyScores = DailyScoringEngine.calculate(summary: HealthSummary(), workouts: [])
    @Published var isLoading = false
    @Published var isSyncingProgressa = false
    @Published var isLoadingMoreWorkouts = false
    @Published var progressaConnected = false
    @Published var stravaConnected = false
    @Published var isUploadingStrava = false
    @Published var healthConnectionLabel = "Not connected"
    @Published var message: String?

    private let accounts = SecureAccountStore()
    private let cache = DashboardCacheStore()
    private let api = APIClient()
    private let health = HealthKitService()
    private let progressaAuth = ProgressaAuthService()
    private let stravaAuth = StravaAuthService()
    private var account: QuantivitaAccount?
    private var sessionGeneration = 0
    private var loadedWorkoutDays = 30

    func bootstrap() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingLinkedProgressa") {
            let start = ISO8601DateFormatter().date(from: "2026-06-18T18:00:00Z")!
            workouts = [Workout(
                id: "health-ui-test", title: "Strength Training", startTime: start,
                durationMinutes: 60, energyKcal: 320, typeCode: 3,
                progressaWorkoutTitle: "Push day", healthActivityLink: HealthActivityLink(
                    healthStart: "2026-06-18T18:00:00Z", healthEnd: "2026-06-18T19:00:00Z",
                    activityType: "Traditional Strength Training", durationSeconds: 3_600
                ),
                progressaDetails: ProgressaDetails(
                    exerciseCount: 1, totalSets: 1, totalVolumeKg: 800, hasVolumeData: true,
                    exercises: [ProgressaExercise(
                        id: "bench", name: "Bench Press", muscleGroup: "Chest",
                        sets: [ProgressaSet(weightKg: 80, reps: 10, rir: 2, side: nil, isWarmup: false, createdAt: nil)]
                    )]
                )
            )]
            stage = .dashboard
            return
        }
#endif
        do {
            account = try accounts.load()
            if let account {
                let cached = cache.load(accountId: account.accountId)
                if let cached {
                    summary = cached.summary
                    workouts = cached.workouts.filter { !$0.isProgressa }
                    dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
                    recovery = dailyScores.recovery
                    healthConnectionLabel = cached.summary.hasAnyHealthData ? "Data available" : "Permission reviewed"
                }
                try await api.register(account)
                stage = cached == nil ? .permissions : .dashboard
                await refreshProgressaStatus()
                await refreshStravaStatus()
                if stage == .dashboard { await refreshAll(showErrors: false) }
            }
        } catch where !Self.isCancellation(error) {
            message = error.localizedDescription
        } catch {}
    }

    func continueOffline() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            account = try accounts.ensureLocalAccount()
            stage = cache.load(accountId: account!.accountId) == nil ? .permissions : .dashboard
            do { try await api.register(account!) }
            catch { message = "Offline mode is active. Server sync will retry when the homeserver is available." }
        } catch { message = error.localizedDescription }
    }

    func signInWithApple(userIdentifier: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            account = try accounts.linkAppleUser(userIdentifier)
            stage = .permissions
            do { try await api.register(account!) }
            catch { message = "Signed in. Server sync will retry when the homeserver is available." }
        } catch { message = error.localizedDescription }
    }

    /// Clears the active session and returns to authentication without destroying
    /// the cached account/dashboard, so the user can sign back in offline.
    func signOut() {
        sessionGeneration += 1
        account = nil
        resetSessionState()
        stage = .authentication
        message = "Signed out. Your cached data stays on this device."
    }

    /// Drops the on-device dashboard cache and re-reads from Apple Health.
    func resetLocalData() async {
        guard let account else { return }
        cache.clear(accountId: account.accountId)
        summary = HealthSummary()
        workouts = []
        dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
        recovery = dailyScores.recovery
        await refreshAll(showErrors: true)
        message = "Cached data was reset from Apple Health."
    }

    /// Permanently deletes the account server-side and wipes all local identity and cache.
    func deleteAccount() async {
        guard let account else { return }
        isLoading = true
        defer { isLoading = false }
        do { try await api.deleteAccount(account) }
        catch where !Self.isCancellation(error) {
            message = "Account deletion failed: \(error.localizedDescription)"
            return
        } catch {}
        cache.clear(accountId: account.accountId)
        try? accounts.clear()
        self.account = nil
        resetSessionState()
        stage = .authentication
        message = "Your account and local data were deleted."
    }

    private func resetSessionState() {
        summary = HealthSummary()
        workouts = []
        dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
        recovery = dailyScores.recovery
        progressaConnected = false
        stravaConnected = false
        healthConnectionLabel = "Not connected"
        isLoading = false
        isSyncingProgressa = false
        isLoadingMoreWorkouts = false
        loadedWorkoutDays = 30
    }

    func authorizeHealth() async {
        isLoading = true
        do {
            try await health.requestAuthorization()
            healthConnectionLabel = "Permission reviewed"
            stage = .dashboard
            isLoading = false
            await refreshAll(showErrors: true)
        } catch {
            isLoading = false
            message = error.localizedDescription
            stage = .dashboard
        }
    }

    func refreshHealth(showErrors: Bool = true) async {
        await refreshAll(showErrors: showErrors)
    }

    func refreshAll(showErrors: Bool = true) async {
        guard !isLoading else { return }
        let generation = sessionGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await health.load(days: 30)
            guard generation == sessionGeneration, account != nil else { return }
            summary = result.0
            healthConnectionLabel = result.0.hasAnyHealthData ? "Data available" : "Permission reviewed"
            workouts = ProgressaWorkoutLinker.preserveLinks(from: workouts, on: result.1)
            dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
            recovery = dailyScores.recovery
        } catch where showErrors && !Self.isCancellation(error) {
            message = error.localizedDescription
        } catch {}
        if progressaConnected { await loadProgressa(showErrors: showErrors) }
        if let account { cache.save(accountId: account.accountId, summary: summary, workouts: workouts) }
        await syncHomeserver()
    }

    func loadMoreWorkouts() async {
        guard !isLoadingMoreWorkouts, account != nil else { return }
        let generation = sessionGeneration
        isLoadingMoreWorkouts = true
        defer { isLoadingMoreWorkouts = false }
        let nextDays = loadedWorkoutDays + 30
        do {
            let fresh = try await health.load(days: nextDays).1
            guard generation == sessionGeneration, account != nil else { return }
            workouts = ProgressaWorkoutLinker.preserveLinks(from: workouts, on: fresh)
            loadedWorkoutDays = nextDays
            if progressaConnected { await loadProgressa(showErrors: false, days: nextDays) }
            if let account { cache.save(accountId: account.accountId, summary: summary, workouts: workouts) }
        } catch where !Self.isCancellation(error) { message = error.localizedDescription }
        catch {}
    }

    func forceSyncAllWorkouts() async {
        guard !isLoading, account != nil else { return }
        let generation = sessionGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            try await health.requestAuthorization()
            let result = try await health.load(days: nil)
            guard generation == sessionGeneration, account != nil else { return }
            summary = result.0
            workouts = ProgressaWorkoutLinker.preserveLinks(from: workouts, on: result.1)
            if progressaConnected { await loadProgressa(showErrors: true, days: nil) }
            dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
            recovery = dailyScores.recovery
            if let account { cache.save(accountId: account.accountId, summary: summary, workouts: workouts) }
            if await syncHomeserver() { message = "All workouts synced." }
        } catch where !Self.isCancellation(error) { message = error.localizedDescription }
        catch {}
    }

    func saveHealthProfile(
        birthdate: Date?, biologicalSex: Int, bodyMassKg: Double?,
        heightCm: Double?, bodyFatPercent: Double?
    ) async {
        if let birthdate {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: birthdate)
            summary.birthYear = parts.year ?? 0
            summary.birthMonth = parts.month ?? 0
            summary.birthDay = parts.day ?? 0
        } else {
            summary.birthYear = 0; summary.birthMonth = 0; summary.birthDay = 0
        }
        summary.biologicalSex = biologicalSex
        summary.bodyMassKg = bodyMassKg ?? 0
        summary.heightCm = heightCm ?? 0
        summary.bodyFatPercent = bodyFatPercent ?? 0
        dailyScores = DailyScoringEngine.calculate(summary: summary, workouts: workouts)
        recovery = dailyScores.recovery
        if let account { cache.save(accountId: account.accountId, summary: summary, workouts: workouts) }
        await syncHomeserver()
        message = "Health profile saved."
    }

    func loadWeightHistory() async {
        weightHistory = await health.weightHistory(since: .distantPast)
    }

    func connectProgressa() async {
        guard let account else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let code = try await progressaAuth.authorize()
            try await api.exchangeProgressaCode(code, account: account)
            progressaConnected = true
            await syncProgressa()
        } catch { message = error.localizedDescription }
    }

    func disconnectProgressa() async {
        guard let account else { return }
        do {
            try await api.disconnectProgressa(account: account)
            progressaConnected = false
            workouts = ProgressaWorkoutLinker.attach([], to: workouts)
            cache.save(accountId: account.accountId, summary: summary, workouts: workouts)
        } catch { message = error.localizedDescription }
    }

    func progressIndex(from: String?, to: String?) async throws -> StrengthIndex {
        guard let account else { throw APIError.invalidResponse }
        return try await api.progressIndex(account: account, from: from, to: to)
    }

    func syncProgressa() async {
        await loadProgressa(showErrors: true)
    }

    private func loadProgressa(showErrors: Bool, days: Int? = 30) async {
        guard let account, !isSyncingProgressa else { return }
        isSyncingProgressa = true
        defer { isSyncingProgressa = false }
        do {
            let incoming = try await api.fetchProgressaWorkouts(
                account: account,
                from: days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) },
                to: .now
            )
            workouts = ProgressaWorkoutLinker.attach(incoming, to: workouts)
            cache.save(accountId: account.accountId, summary: summary, workouts: workouts)
        } catch let error as APIError where error.statusCode == 401 {
            progressaConnected = false
            message = "Your Progressa connection expired and could not be refreshed. Connect Progressa again; cached linked workout details remain available."
        } catch where showErrors && !Self.isCancellation(error) {
            message = "Progressa sync failed. Cached workouts remain available. \(error.localizedDescription)"
        } catch {}
        if !isLoading {
            await syncHomeserver()
        }
    }

    func handle(url: URL) {
        if progressaAuth.handleCallback(url) { return }
        _ = stravaAuth.handle(url)
    }

    func connectStrava() async {
        guard let account else { return }
        do {
            let state = stravaAuth.newState()
            let url = try await api.stravaAuthorizeURL(account: account, state: state)
            let authorization = try await stravaAuth.authorize(url: url, state: state)
            guard authorization.scopes.contains("activity:write") else {
                throw StravaAuthError.denied("activity upload permission was not granted")
            }
            try await api.exchangeStravaCode(authorization.code, scopes: authorization.scopes, account: account)
            let status = try await api.stravaStatus(account: account)
            stravaConnected = status.connected && status.canUpload
            message = "Strava connected."
        } catch { message = error.localizedDescription }
    }

    func disconnectStrava() async {
        guard let account else { return }
        do { try await api.disconnectStrava(account: account); stravaConnected = false }
        catch { message = error.localizedDescription }
    }

    func uploadMergedWorkoutToStrava(ids: Set<String>) async -> Bool {
        guard let account else { return false }
        let selected = workouts.filter { ids.contains($0.id) }
        guard selected.count >= 2 else { return false }
        if !stravaConnected { await connectStrava() }
        guard stravaConnected else { return false }
        guard !isUploadingStrava else { return false }
        isUploadingStrava = true
        defer { isUploadingStrava = false }
        do {
            // Strava rejects activities that overlap an existing one. Source workouts may
            // already be on Strava, so place the merged activity entirely AFTER the source
            // window (span + random jitter) — guaranteeing no overlap and a unique start.
            let rawStart = selected.map(\.startTime).min()!
            let rawEnd = selected.map { $0.startTime.addingTimeInterval($0.effectiveDurationMinutes * 60) }.max() ?? rawStart
            let uniqueOffset = rawEnd.timeIntervalSince(rawStart) + TimeInterval(Int.random(in: 60...300))
            let routePoints = await mergedRoutePoints(ids: ids)
            guard let tcx = StravaTCXBuilder.build(workouts: selected, uniqueStartOffset: uniqueOffset, route: routePoints) else {
                message = "The selected workouts cannot be converted to a valid Strava file."
                return false
            }
            let shiftedStart = rawStart.addingTimeInterval(uniqueOffset)
            let uploadId = try await api.uploadToStrava(
                account: account, name: "Quantivita merged workout",
                externalId: "quantivita-\(Int(shiftedStart.timeIntervalSince1970)).tcx",
                tcx: tcx
            )
            guard let uploadId else {
                message = "Strava accepted the workout but returned no upload identifier."
                return false
            }
            for _ in 0..<12 {
                let status = try await api.stravaUploadStatus(uploadId, account: account)
                if status.state == "ready" {
                    message = "Merged workout uploaded to Strava."
                    return true
                }
                if status.state == "failed" {
                    message = Self.friendlyStravaError(status.error)
                    return false
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            message = "Strava is still processing the workout. It will appear after processing completes."
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func mergedRouteCoordinates(ids: Set<String>) async -> [CLLocationCoordinate2D] {
        await health.routeCoordinates(for: workouts.filter { ids.contains($0.id) })
    }

    /// Combined GPS track with cumulative distance, for the Strava TCX upload.
    func mergedRoutePoints(ids: Set<String>) async -> [WorkoutRoutePoint] {
        let locations = await health.routeLocations(for: workouts.filter { ids.contains($0.id) })
        var points: [WorkoutRoutePoint] = []
        var cumulative = 0.0
        var previous: CLLocation?
        for location in locations {
            if let previous { cumulative += location.distance(from: previous) }
            previous = location
            points.append(WorkoutRoutePoint(
                time: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                cumulativeDistanceMeters: cumulative
            ))
        }
        return points
    }

    func exportMergedWorkout(ids: Set<String>) async -> Bool {
        let selected = workouts.filter { ids.contains($0.id) }
        guard selected.count >= 2 else { return false }
        do {
            try await health.exportMergedWorkout(selected)
            message = "Merged workout exported to Apple Health."
            return true
        } catch {
            message = "Merge Lab export failed: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshProgressaStatus() async {
        guard let account else { return }
        progressaConnected = (try? await api.progressaStatus(account: account)) ?? false
    }

    private func refreshStravaStatus() async {
        guard let account else { return }
        guard let status = try? await api.stravaStatus(account: account) else {
            stravaConnected = false
            return
        }
        stravaConnected = status.connected && status.canUpload
    }

    @discardableResult
    private func syncHomeserver() async -> Bool {
        guard let account else { return false }
        let syncedThroughKey = "weightHistorySyncedThrough.\(account.accountId)"
        let since = UserDefaults.standard.object(forKey: syncedThroughKey) as? Date ?? .distantPast
        let newWeightSamples = await health.weightHistory(since: since)
        do {
            try await api.ingest(
                account: account, summary: summary, recovery: recovery, workouts: workouts,
                weightHistory: newWeightSamples
            )
            if let latest = newWeightSamples.last?.date {
                UserDefaults.standard.set(latest, forKey: syncedThroughKey)
            }
            return true
        } catch where !Self.isCancellation(error) {
            message = "Health data is saved locally; server sync is unavailable."
            return false
        } catch { return false }
    }

    /// Strava failure strings arrive as HTML (e.g. `duplicate of <a ...>Lunch Run</a>`).
    /// Strip the markup and turn the common "duplicate" case into a plain explanation,
    /// since a merged workout shares its source's start time and Strava already has it.
    static func friendlyStravaError(_ raw: String?) -> String {
        let stripped = (raw ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "Strava could not process the workout." }
        if let range = stripped.range(of: "duplicate of ", options: .caseInsensitive) {
            let name = String(stripped[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty
                ? "This workout is already on Strava."
                : "This workout is already on Strava as “\(name)”."
        }
        if stripped.range(of: "duplicate", options: .caseInsensitive) != nil {
            return "This workout is already on Strava."
        }
        return "Strava rejected the workout: \(stripped)"
    }

    /// A cancelled URLSession request (or a cancelled Swift task, e.g. when SwiftUI
    /// tears down a `.task`/`.refreshable`) is benign and must not surface as a failure.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func merge(_ first: [Workout], with second: [Workout]) -> [Workout] {
        var indexed = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0) })
        for workout in second { indexed[workout.id] = workout }
        return indexed.values.sorted { $0.startTime > $1.startTime }
    }
}
