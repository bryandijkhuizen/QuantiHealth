import HealthKit
import CoreLocation

final class ProgressaHealthKitService {
    private let store: HKHealthStore
    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ProgressaClientError.invalidResponse }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(heartRate) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(energy) }
        if let route = HKSeriesType.workoutRoute() as HKObjectType? { read.insert(route) }
        try await store.requestAuthorization(toShare: [], read: read)
    }

    func sessions(around: Date, days: Int = 2) async throws -> [ProgressaHealthSession] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: around) ?? around.addingTimeInterval(-172_800)
        let end = Calendar.current.date(byAdding: .day, value: days, to: around) ?? around.addingTimeInterval(172_800)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            store.execute(query)
        }
        return workouts.map {
            ProgressaHealthSession(
                workoutUUID: $0.uuid, start: $0.startDate, end: $0.endDate,
                activityType: Self.activityName($0.workoutActivityType),
                calories: $0.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                distanceMeters: $0.totalDistance?.doubleValue(for: .meter())
            )
        }
    }

    func heartRate(start: Date, end: Date) async throws -> (average: Double?, maximum: Double?) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return (nil, nil) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let values: [Double] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: (samples as? [HKQuantitySample] ?? []).map { $0.quantity.doubleValue(for: unit) })
            }
            store.execute(query)
        }
        guard !values.isEmpty else { return (nil, nil) }
        return (values.reduce(0, +) / Double(values.count), values.max())
    }

    /// Authorization to write a recorded workout (and its route) back to Apple Health.
    func requestRecordingAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ProgressaClientError.invalidResponse }
        var share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for identifier in [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { share.insert(type) }
        }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let route = HKSeriesType.workoutRoute() as HKObjectType? { read.insert(route) }
        try await store.requestAuthorization(toShare: share, read: read)
    }

    /// Saves a recorded outdoor workout with its GPS route to Apple Health.
    func saveRecordedWorkout(activity: RecordingActivity, start: Date, end: Date, distanceMeters: Double, locations: [CLLocation]) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.hkType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: start)
        if distanceMeters > 0, let type = Self.distanceType(for: activity.hkType) {
            try await builder.addSamples([HKQuantitySample(
                type: type, quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters), start: start, end: end
            )])
        }
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw ProgressaClientError.invalidResponse }
        guard locations.count > 1 else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        try await routeBuilder.insertRouteData(locations)
        try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    private static func distanceType(for activity: HKWorkoutActivityType) -> HKQuantityType? {
        switch activity {
        case .cycling: return HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        default: return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        }
    }

    /// GPS route of the workout that best matches the given time window, if recorded locally.
    func routeCoordinates(matching start: Date, end: Date) async -> [CLLocationCoordinate2D] {
        let padding: TimeInterval = 120
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-padding), end: end.addingTimeInterval(padding))
        let workouts: [HKWorkout] = (try? await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            store.execute(query)
        }) ?? []
        guard let workout = workouts.min(by: { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }) else { return [] }
        return await routeCoordinates(for: workout)
    }

    private func routeCoordinates(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        let routes: [HKWorkoutRoute] = (try? await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKWorkoutRoute] ?? []) }
            }
            store.execute(query)
        }) ?? []
        var coordinates: [CLLocationCoordinate2D] = []
        for route in routes {
            let locations = (try? await self.locations(for: route)) ?? []
            coordinates.append(contentsOf: locations.map(\.coordinate))
        }
        return coordinates
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CLLocation], Error>) in
            var collected: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, chunk, done, error in
                if let chunk { collected.append(contentsOf: chunk) }
                if let error { continuation.resume(throwing: error) }
                else if done { continuation.resume(returning: collected) }
            }
            store.execute(query)
        }
    }

    static func activityName(_ value: HKWorkoutActivityType) -> String {
        switch value {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength Training"
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }
}
