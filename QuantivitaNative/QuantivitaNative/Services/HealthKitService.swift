import HealthKit
import WorkoutKit
import CoreLocation
import Foundation

enum HealthKitError: LocalizedError {
    case unavailable
    case alreadyExported
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is unavailable on this device."
        case .alreadyExported: return "This workout combination was already exported."
        }
    }
}

final class HealthKitService {
    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let reads = Set([
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKObjectType.quantityType(forIdentifier: .dietaryWater),
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .runningSpeed),
            HKObjectType.quantityType(forIdentifier: .runningPower),
            HKObjectType.quantityType(forIdentifier: .runningStrideLength),
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime),
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
            HKObjectType.quantityType(forIdentifier: .bodyTemperature),
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature),
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .height),
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ].compactMap { $0 })
        let shares: Set<HKSampleType> = Set([
            HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKObjectType.quantityType(forIdentifier: .distanceCycling),
            HKObjectType.quantityType(forIdentifier: .distanceSwimming),
            HKObjectType.quantityType(forIdentifier: .heartRate),
        ].compactMap { $0 })
        try await store.requestAuthorization(toShare: shares, read: reads)
    }

    func load(days: Int? = 30) async throws -> (HealthSummary, [Workout]) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        async let steps = cumulative(.stepCount, unit: .count(), start: start)
        async let active = cumulative(.activeEnergyBurned, unit: .kilocalorie(), start: start)
        async let basal = cumulative(.basalEnergyBurned, unit: .kilocalorie(), start: start)
        async let dietaryEnergy = cumulative(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start)
        async let water = cumulative(.dietaryWater, unit: .literUnit(with: .milli), start: start)
        async let carbs = cumulative(.dietaryCarbohydrates, unit: .gram(), start: start)
        async let protein = cumulative(.dietaryProtein, unit: .gram(), start: start)
        async let fat = cumulative(.dietaryFatTotal, unit: .gram(), start: start)
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let rhr = latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let respiratory = latest(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let oxygen = latest(.oxygenSaturation, unit: .percent())
        async let bodyTemperature = latest(.bodyTemperature, unit: .degreeCelsius())
        async let wristTemperature = latest(.appleSleepingWristTemperature, unit: .degreeCelsius())
        async let bodyMass = latest(.bodyMass, unit: .gramUnit(with: .kilo))
        async let height = latest(.height, unit: .meterUnit(with: .centi))
        async let bodyFat = latest(.bodyFatPercentage, unit: .percent())
        async let sleep = sleepSummary(since: calendar.date(byAdding: .day, value: -1, to: start)!)
        async let workouts = workoutHistory(since: days.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: .now)
        } ?? .distantPast)

        let profile = profileSummary()
        var summary = await HealthSummary(
            sleepMinutes: sleep.total,
            sleepREMMinutes: sleep.rem,
            sleepCoreMinutes: sleep.core,
            sleepDeepMinutes: sleep.deep,
            sleepAwakeMinutes: sleep.awake,
            sleepInBedMinutes: sleep.inBed,
            hrvMs: hrv, restingHeartBpm: rhr,
            respiratoryRate: respiratory, oxygenSaturation: oxygen * 100,
            activeEnergyKcal: active, basalEnergyKcal: basal,
            dietaryEnergyKcal: dietaryEnergy, dietaryWaterMl: water,
            dietaryCarbohydratesG: carbs, dietaryProteinG: protein, dietaryFatG: fat,
            steps: steps, bodyTemperatureC: bodyTemperature,
            wristTemperatureC: wristTemperature, bodyMassKg: bodyMass,
            heightCm: height, bodyFatPercent: bodyFat * 100,
            birthYear: profile.year, birthMonth: profile.month, birthDay: profile.day,
            biologicalSex: profile.sex
        )
        summary.oxygenSaturation = min(summary.oxygenSaturation, 100)
        summary.vo2MaxSamples = await vo2MaxHistory(since: days.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: .now)
        } ?? .distantPast)
        return await (summary, workouts)
    }

    private func profileSummary() -> (year: Int, month: Int, day: Int, sex: Int) {
        let birth = try? store.dateOfBirthComponents()
        let sex = (try? store.biologicalSex().biologicalSex.rawValue) ?? 0
        return (birth?.year ?? 0, birth?.month ?? 0, birth?.day ?? 0, sex)
    }

    func exportMergedWorkout(_ workouts: [Workout]) async throws {
        guard workouts.count >= 2,
              let start = workouts.map(\.startTime).min() else { return }
        let sourceIds = workouts.map(\.id).sorted().joined(separator: ",")
        if await mergedWorkoutExists(sourceIds: sourceIds) { throw HealthKitError.alreadyExported }
        let end = workouts.map { $0.startTime.addingTimeInterval($0.effectiveDurationMinutes * 60) }.max() ?? start
        let energy = workouts.reduce(0) { $0 + $1.effectiveEnergyKcal }
        let distance = workouts.reduce(0) { $0 + $1.distanceMeters }
        let activityType = mergedActivityType(workouts)
        let sourceWorkouts = try await healthKitWorkouts(ids: WorkoutFidelity.sourceUUIDs(for: workouts))
        let routeLocations = try await sourceRouteLocations(sourceWorkouts)
        let seriesSamples = await copiedSeriesSamples(from: sourceWorkouts)
        let sourceNames = Set(workouts.compactMap(\.sourceName)).sorted().joined(separator: ", ")
        let sourceBundles = Set(workouts.compactMap(\.sourceBundleIdentifier)).sorted().joined(separator: ",")
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            "com.bryandijkh.quantivita.mergedWorkoutIds": sourceIds,
            "com.bryandijkh.quantivita.sourceNames": sourceNames,
            "com.bryandijkh.quantivita.sourceBundles": sourceBundles,
        ]
        // Carry the ambient/weather temperature (and humidity) from the source workouts.
        metadata.merge(weatherMetadata(from: sourceWorkouts)) { current, _ in current }

        // Build with HKWorkoutBuilder (not the deprecated HKWorkout initializer) so the
        // GPS route attaches and shows a map, and pause the idle gaps between source
        // workouts so "Workout Time" is the active duration, not the multi-day span.
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: start)
        try await builder.addMetadata(metadata)
        let samples = mergedQuantitySamples(
            activityType: activityType, start: start, end: end,
            energyKcal: energy, distanceMeters: distance,
            averageHeartRate: WorkoutFidelity.weightedAverageHeartRate(for: workouts), series: seriesSamples
        )
        if !samples.isEmpty { try await builder.addSamples(samples) }
        let pauseEvents = WorkoutFidelity.pausedGaps(for: workouts).flatMap { gap in
            [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: gap.start, end: gap.start), metadata: nil),
             HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: gap.end, end: gap.end), metadata: nil)]
        }
        if !pauseEvents.isEmpty { try await builder.addWorkoutEvents(pauseEvents) }
        try await builder.endCollection(at: end)
        guard let merged = try await builder.finishWorkout() else { throw HealthKitError.unavailable }

        if !routeLocations.isEmpty {
            try await writeRoute(routeLocations, to: merged)
        }
    }

    /// Combined GPS route of the selected workouts, sorted and de-duplicated.
    func routeLocations(for workouts: [Workout]) async -> [CLLocation] {
        guard let sources = try? await healthKitWorkouts(ids: WorkoutFidelity.sourceUUIDs(for: workouts)),
              let locations = try? await sourceRouteLocations(sources) else { return [] }
        return locations
    }

    /// Combined GPS route of the selected workouts, for the Merge Lab map preview.
    func routeCoordinates(for workouts: [Workout]) async -> [CLLocationCoordinate2D] {
        await routeLocations(for: workouts).map(\.coordinate)
    }

    /// Copies the real heart-rate series from each source workout so the merged
    /// workout keeps the full data, not just an average.
    private func copiedSeriesSamples(from workouts: [HKWorkout]) async -> [HKQuantitySample] {
        guard let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        var result: [HKQuantitySample] = []
        for workout in workouts {
            result += await copiedSamples(of: heartRate, matching: HKQuery.predicateForObjects(from: workout))
        }
        return result
    }

    /// First available ambient weather temperature/humidity across the source workouts.
    private func weatherMetadata(from workouts: [HKWorkout]) -> [String: Any] {
        var result: [String: Any] = [:]
        for workout in workouts {
            if result[HKMetadataKeyWeatherTemperature] == nil,
               let temperature = workout.metadata?[HKMetadataKeyWeatherTemperature] {
                result[HKMetadataKeyWeatherTemperature] = temperature
            }
            if result[HKMetadataKeyWeatherHumidity] == nil,
               let humidity = workout.metadata?[HKMetadataKeyWeatherHumidity] {
                result[HKMetadataKeyWeatherHumidity] = humidity
            }
        }
        return result
    }

    private func copiedSamples(of type: HKQuantityType, matching predicate: NSPredicate) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let copies = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HKQuantitySample(
                        type: type, quantity: sample.quantity, start: sample.startDate, end: sample.endDate,
                        metadata: ["com.bryandijkh.quantivita.mergedSample": true]
                    )
                }
                continuation.resume(returning: copies)
            }
            store.execute(query)
        }
    }

    private func mergedActivityType(_ workouts: [Workout]) -> HKWorkoutActivityType {
        let grouped = Dictionary(grouping: workouts.filter { $0.typeCode > 0 }, by: \.typeCode)
        guard let raw = grouped.max(by: { $0.value.count < $1.value.count })?.key else { return .mixedCardio }
        return HKWorkoutActivityType.quantivitaActivity(for: raw)
    }

    private func mergedWorkoutExists(sourceIds: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: "com.bryandijkh.quantivita.mergedWorkoutIds", allowedValues: [sourceIds])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(query)
        }
    }

    private func cumulative(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: nil),
                options: .cumulativeSum
            ) { _, result, _ in continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0) }
            store.execute(query)
        }
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    func weightHistory(since: Date) async -> [WeightSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        return samples.map { WeightSample(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    private func sleepSummary(since: Date) async -> (total: Double, rem: Double, core: Double, deep: Double, awake: Double, inBed: Double) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return (0, 0, 0, 0, 0, 0) }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: Self.summarizeSleep((samples as? [HKCategorySample]) ?? []))
            }
            store.execute(query)
        }
    }

    /// Collapses the queried samples into the single most-recent sleep session.
    /// The query window spans roughly the last 34 hours, so it can contain the tail
    /// of the previous night plus last night. Summing both inflated the reported
    /// duration (e.g. ~16h); restricting to one session reports only last night.
    static func summarizeSleep(_ samples: [HKCategorySample]) -> (total: Double, rem: Double, core: Double, deep: Double, awake: Double, inBed: Double) {
        var rem: [(Date, Date)] = [], core: [(Date, Date)] = [], deep: [(Date, Date)] = []
        var unspecified: [(Date, Date)] = [], awake: [(Date, Date)] = [], inBed: [(Date, Date)] = []
        for sample in samples {
            let interval = (sample.startDate, sample.endDate)
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem.append(interval)
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: core.append(interval)
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep.append(interval)
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: unspecified.append(interval)
            case HKCategoryValueSleepAnalysis.awake.rawValue: awake.append(interval)
            case HKCategoryValueSleepAnalysis.inBed.rawValue: inBed.append(interval)
            default: break
            }
        }
        let asleep = rem + core + deep + unspecified
        guard let session = mostRecentSleepSession(asleep: asleep, inBed: inBed) else {
            return (0, 0, 0, 0, 0, 0)
        }
        func clip(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
            intervals.compactMap { interval in
                let start = max(interval.0, session.0)
                let end = min(interval.1, session.1)
                return start < end ? (start, end) : nil
            }
        }
        return (
            unionMinutes(clip(asleep)), unionMinutes(clip(rem)), unionMinutes(clip(core)),
            unionMinutes(clip(deep)), unionMinutes(clip(awake)), unionMinutes(clip(inBed))
        )
    }

    /// Groups in-bed/asleep intervals into sessions separated by a wake gap and
    /// returns the bounds of the latest one (last night's main sleep).
    static func mostRecentSleepSession(asleep: [(Date, Date)], inBed: [(Date, Date)]) -> (Date, Date)? {
        let intervals = (asleep + inBed).sorted { $0.0 < $1.0 }
        guard let first = intervals.first else { return nil }
        let gap: TimeInterval = 90 * 60 // a break longer than 90 minutes starts a new session
        var sessions: [(start: Date, end: Date)] = [(first.0, first.1)]
        for interval in intervals.dropFirst() {
            if interval.0.timeIntervalSince(sessions[sessions.count - 1].end) <= gap {
                sessions[sessions.count - 1].end = max(sessions[sessions.count - 1].end, interval.1)
            } else {
                sessions.append((interval.0, interval.1))
            }
        }
        // Sessions are chronological and non-overlapping, so the last is the most recent.
        return sessions.last.map { ($0.start, $0.end) }
    }

    static func unionMinutes(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        guard var current = sorted.first else { return 0 }
        var seconds = 0.0
        for interval in sorted.dropFirst() {
            if interval.0 <= current.1 { current.1 = max(current.1, interval.1) }
            else { seconds += current.1.timeIntervalSince(current.0); current = interval }
        }
        return (seconds + current.1.timeIntervalSince(current.0)) / 60
    }

    private func workoutHistory(since: Date) async -> [Workout] {
        let healthKitWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForSamples(withStart: since, end: nil), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        var result: [Workout] = []
        for workout in healthKitWorkouts {
            async let heartRate = heartRateMetrics(for: workout)
            async let locations = routeLocations(for: workout)
            let metrics = await heartRate
            let route = (try? await locations) ?? []
            let source = workout.sourceRevision.source
            result.append(Workout(
                id: workout.uuid.uuidString, title: workout.workoutActivityType.displayName,
                startTime: workout.startDate, durationMinutes: workout.duration / 60,
                energyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                totalEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                elevationGainMeters: WorkoutFidelity.elevationGain(route),
                averageHeartRate: metrics.average, maxHeartRate: metrics.maximum,
                typeCode: workout.workoutActivityType.quantivitaCode, hasRoute: !route.isEmpty,
                sourceName: source.name, sourceBundleIdentifier: source.bundleIdentifier
            ))
            if workout.workoutActivityType == .running {
                var telemetry = await trainingTelemetry(for: workout)
                telemetry.kilometerSplits = Self.routeSplits(route, events: workout.workoutEvents ?? [])
                if !telemetry.kilometerSplits.isEmpty { telemetry.splitMethod = "gps-distance-active-time" }
                result[result.count - 1].telemetry = telemetry
            }
        }
        return result
    }

    private func trainingTelemetry(for workout: HKWorkout) async -> WorkoutTelemetry {
        var result = WorkoutTelemetry()
        result.appleWorkoutActivities = Self.exportWorkoutActivities(workout.workoutActivities)
        result.workoutEndTime = workout.endDate.ISO8601Format()
        if #available(iOS 17.0, *) {
            do {
                if let plan = try await workout.workoutPlan {
                    result.appleWorkoutPlan = Self.exportWorkoutPlan(plan)
                    result.appleWorkoutPlanStatus = result.appleWorkoutPlan == nil ? "notCustom" : "available"
                } else { result.appleWorkoutPlanStatus = "noPlan" }
            } catch { result.appleWorkoutPlanStatus = "readFailed" }
        } else { result.appleWorkoutPlanStatus = "unsupportedOS" }
        let heart = await trainingSamples(.heartRate, for: workout)
        let speed = await trainingSamples(.runningSpeed, for: workout)
        // Keep evenly spaced real observations, including both endpoints. No GPS is exported.
        func bounded(_ samples: [HKQuantitySample]) -> [HKQuantitySample] {
            guard samples.count > 240 else { return samples }
            return (0..<240).map { samples[$0 * (samples.count - 1) / 239] }
        }
        result.heartRateSamples = bounded(heart).map {
            .init(time: $0.startDate.ISO8601Format(), bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }
        result.speedSamples = bounded(speed).map {
            .init(time: $0.startDate.ISO8601Format(), metersPerSecond: $0.quantity.doubleValue(for: .meter().unitDivided(by: .second())))
        }
        result.workoutEvents = (workout.workoutEvents ?? []).compactMap { event in
            let name: String
            switch event.type {
            case .pause: name = "pause"
            case .resume: name = "resume"
            case .lap: name = "lap"
            case .segment: name = "segment"
            case .marker: name = "marker"
            case .motionPaused: name = "motionPaused"
            case .motionResumed: name = "motionResumed"
            default: return nil
            }
            return .init(type: name, startTime: event.dateInterval.start.ISO8601Format(), endTime: event.dateInterval.end.ISO8601Format(), metadata: Self.intervalMetadata(event.metadata))
        }
        func average(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let value = workout.statistics(for: type)?.averageQuantity()?.doubleValue(for: unit),
                  value.isFinite, value > 0 else { return nil }
            return value
        }
        result.runningPowerWatts = average(.runningPower, unit: .watt())
        result.runningStrideLengthMeters = average(.runningStrideLength, unit: .meter())
        result.runningGroundContactTimeMilliseconds = average(.runningGroundContactTime, unit: .secondUnit(with: .milli))
        result.runningVerticalOscillationMeters = average(.runningVerticalOscillation, unit: .meter())
        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount), workout.duration > 0,
           let steps = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .count()), steps > 0 {
            result.cadenceStepsPerMinute = steps / (workout.duration / 60)
        }
        return result
    }

    static func intervalMetadata(_ metadata: [String: Any]?) -> [String: String]? {
        var values: [String: String] = [:]
        for (key, value) in metadata ?? [:] {
            guard ["interval", "segment", "lap", "step", "purpose", "marker", "activity"].contains(where: key.lowercased().contains) else { continue }
            if value is String || value is NSNumber || value is HKQuantity {
                values[key] = String(describing: value)
            }
        }
        return values.isEmpty ? nil : values
    }

    static func exportWorkoutActivities(_ activities: [HKWorkoutActivity]) -> [WorkoutTelemetry.Activity] {
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        return activities.compactMap { activity in
            guard let end = activity.endDate, end > activity.startDate,
                  activity.duration.isFinite, activity.duration > 0 else { return nil }
            let meters = distanceType.flatMap { activity.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
            return .init(id: activity.uuid.uuidString, startTime: activity.startDate.ISO8601Format(),
                         endTime: end.ISO8601Format(), durationSeconds: activity.duration,
                         activityTypeRaw: activity.workoutConfiguration.activityType.rawValue,
                         distanceMeters: meters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                         metadata: intervalMetadata(activity.metadata))
        }.sorted { $0.startTime < $1.startTime }
    }

    @available(iOS 17.0, *)
    static func exportWorkoutPlan(_ plan: WorkoutKit.WorkoutPlan) -> AppleWorkoutPlan? {
        guard case let .custom(custom) = plan.workout, custom.activity == .running else { return nil }
        func step(_ input: WorkoutKit.WorkoutStep, purpose: String) -> AppleWorkoutPlan.Step {
            var output = AppleWorkoutPlan.Step(purpose: purpose)
            switch input.goal {
            case let .time(value, unit):
                let seconds = Measurement(value: value, unit: unit).converted(to: .seconds).value
                if seconds.isFinite && seconds > 0 { output.targetSeconds = seconds }
            case let .distance(value, unit):
                let meters = Measurement(value: value, unit: unit).converted(to: .meters).value
                if meters.isFinite && meters > 0 { output.targetDistanceMeters = meters }
            case let .energy(value, unit):
                let kcal = Measurement(value: value, unit: unit).converted(to: .kilocalories).value
                if kcal.isFinite && kcal > 0 { output.targetEnergyKcal = kcal }
            default: break
            }
            return output
        }
        return AppleWorkoutPlan(
            id: plan.id.uuidString,
            blocks: custom.blocks.filter { $0.iterations > 0 && !$0.steps.isEmpty }.map { block in
                .init(iterations: block.iterations, steps: block.steps.map {
                    step($0.step, purpose: $0.purpose == .work ? "work" : "recovery")
                })
            },
            warmup: custom.warmup.map { step($0, purpose: "warmup") },
            cooldown: custom.cooldown.map { step($0, purpose: "cooldown") }
        )
    }

    private func vo2MaxHistory(since: Date) async -> [VO2MaxSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let unit = HKUnit(from: "ml/kg*min")
                let values = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> VO2MaxSample? in
                    let value = sample.quantity.doubleValue(for: unit)
                    guard value.isFinite, value > 0 else { return nil }
                    return .init(time: sample.startDate, millilitersPerKilogramPerMinute: value)
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// GPS-derived complete kilometers only. Sparse routes are omitted, never bridged.
    /// Boundary times are interpolated between actual neighboring GPS observations.
    static func routeSplits(_ route: [CLLocation], events: [HKWorkoutEvent]) -> [WorkoutTelemetry.Split] {
        let points = route.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 30 }
        guard points.count > 1 else { return [] }
        let pauses = events.filter { [.pause, .resume, .motionPaused, .motionResumed].contains($0.type) }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }
        var paused = false
        var eventIndex = 0
        var distance = 0.0
        var seconds = 0.0
        var splits: [WorkoutTelemetry.Split] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0, dt <= 30 else { return [] }
            while eventIndex < pauses.count, pauses[eventIndex].dateInterval.start <= a.timestamp {
                paused = pauses[eventIndex].type == .pause || pauses[eventIndex].type == .motionPaused
                eventIndex += 1
            }
            // A boundary crossing a pause cannot provide a reliable active split.
            if eventIndex < pauses.count, pauses[eventIndex].dateInterval.start < b.timestamp { return [] }
            if paused { continue }
            var meters = b.distance(from: a)
            guard meters.isFinite, meters / dt <= 15 else { return [] }
            var duration = dt
            while distance + meters >= 1000 {
                let fraction = (1000 - distance) / meters
                let elapsed = duration * fraction
                splits.append(.init(distanceMeters: 1000, durationSeconds: seconds + elapsed))
                meters -= 1000 - distance
                duration -= elapsed
                distance = 0
                seconds = 0
            }
            distance += meters
            seconds += duration
        }
        return splits
    }

    private func trainingSamples(_ identifier: HKQuantityTypeIdentifier, for workout: HKWorkout) async -> [HKQuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForObjects(from: workout), limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample] ?? []).filter {
                    ($0.metadata?["com.bryandijkh.quantivita.syntheticAverageHeartRate"] as? Bool) != true
                })
            }
            store.execute(query)
        }
    }

    private func heartRateMetrics(for workout: HKWorkout) async -> (average: Double, maximum: Double) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return (0, 0) }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: (
                    statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0,
                    statistics?.maximumQuantity()?.doubleValue(for: unit) ?? 0
                ))
            }
            store.execute(query)
        }
    }

    private func healthKitWorkouts(ids: [UUID]) async throws -> [HKWorkout] {
        var result: [HKWorkout] = []
        for id in ids {
            let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: id),
                    limit: 1, sortDescriptors: nil
                ) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples?.first as? HKWorkout) }
                }
                store.execute(query)
            }
            if let workout { result.append(workout) }
        }
        return result
    }

    private func sourceRouteLocations(_ workouts: [HKWorkout]) async throws -> [CLLocation] {
        var locations: [CLLocation] = []
        for workout in workouts {
            locations.append(contentsOf: try await routeLocations(for: workout))
        }
        return WorkoutFidelity.deduplicatedLocations(locations)
    }

    private func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? []) }
            }
            store.execute(query)
        }
        var collected: [CLLocation] = []
        for route in routes {
            collected.append(contentsOf: try await locations(for: route))
        }
        return WorkoutFidelity.deduplicatedLocations(collected)
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CLLocation], Error>) in
            var locations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, chunk, done, error in
                if let chunk { locations.append(contentsOf: chunk) }
                if let error { continuation.resume(throwing: error) }
                else if done { continuation.resume(returning: locations) }
            }
            store.execute(query)
        }
    }

    /// Quantity samples added to the merged workout: total energy and distance over the
    /// span, plus the real heart-rate series (with a synthesized average only as fallback).
    private func mergedQuantitySamples(
        activityType: HKWorkoutActivityType, start: Date, end: Date,
        energyKcal: Double, distanceMeters: Double, averageHeartRate: Double, series: [HKQuantitySample]
    ) -> [HKSample] {
        var samples: [HKSample] = []
        let metadata: [String: Any] = ["com.bryandijkh.quantivita.mergedSample": true]
        if energyKcal > 0, let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal), start: start, end: end, metadata: metadata))
        }
        if distanceMeters > 0, let type = distanceType(for: activityType) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters), start: start, end: end, metadata: metadata))
        }
        samples.append(contentsOf: series)
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let hasCopiedHeartRate = series.contains { $0.quantityType == heartRateType }
        if !hasCopiedHeartRate, averageHeartRate > 0, let type = heartRateType {
            var heartMetadata = metadata
            heartMetadata["com.bryandijkh.quantivita.syntheticAverageHeartRate"] = true
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: averageHeartRate), start: start, end: end, metadata: heartMetadata))
        }
        return samples
    }

    private func distanceType(for activityType: HKWorkoutActivityType) -> HKQuantityType? {
        switch activityType {
        case .cycling: return HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        case .swimming: return HKQuantityType.quantityType(forIdentifier: .distanceSwimming)
        default: return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        }
    }

    private func writeRoute(_ locations: [CLLocation], to workout: HKWorkout) async throws {
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        for start in stride(from: 0, to: locations.count, by: 1_000) {
            let end = min(start + 1_000, locations.count)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.insertRouteData(Array(locations[start..<end])) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: HealthKitError.unavailable) }
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishRoute(
                with: workout,
                metadata: ["com.bryandijkh.quantivita.mergedRoute": true, "com.bryandijkh.quantivita.routePointCount": locations.count]
            ) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

private extension HKWorkoutActivityType {
    var quantivitaCode: Int {
        switch self {
        case .running: return 1
        case .walking: return 2
        case .cycling: return 3
        case .swimming: return 4
        case .functionalStrengthTraining, .traditionalStrengthTraining: return 5
        case .highIntensityIntervalTraining: return 6
        case .yoga: return 7
        case .hiking: return 8
        case .elliptical: return 9
        case .rowing: return 10
        case .climbing: return 11
        case .pilates: return 12
        case .dance: return 13
        case .stairClimbing: return 14
        case .tennis: return 15
        case .soccer: return 16
        case .basketball: return 17
        case .coreTraining: return 18
        case .paddleSports: return 19
        default: return 0
        }
    }

    static func quantivitaActivity(for code: Int) -> HKWorkoutActivityType {
        switch code {
        case 1: return .running
        case 2: return .walking
        case 3: return .cycling
        case 4: return .swimming
        case 5: return .functionalStrengthTraining
        case 6: return .highIntensityIntervalTraining
        case 7: return .yoga
        case 8: return .hiking
        case 9: return .elliptical
        case 10: return .rowing
        case 11: return .climbing
        case 12: return .pilates
        case 13: return .dance
        case 14: return .stairClimbing
        case 15: return .tennis
        case 16: return .soccer
        case 17: return .basketball
        case 18: return .coreTraining
        case 19: return .paddleSports
        default: return .mixedCardio
        }
    }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .climbing: return "Rock Climbing"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .stairClimbing: return "Stair Climbing"
        case .tennis: return "Tennis"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .coreTraining: return "Core Training"
        case .paddleSports: return "Paddling"
        default: return "Workout"
        }
    }
}
