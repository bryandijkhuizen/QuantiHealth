import XCTest
import CoreLocation
import HealthKit
import WorkoutKit
@testable import QuantivitaNative

final class WorkoutDecodingTests: XCTestCase {
    func testCyclingMissingAndZeroMetricsSurviveWireAndCache() throws {
        var ride = Workout(id: "ride", title: "Cycling", startTime: .now, durationMinutes: 20, energyKcal: 0)
        ride.avgPowerWatts = 0
        ride.energyAvailable = false
        let payload = APIClient().workoutPayload(ride)
        XCTAssertTrue(payload["averageHeartRate"] is NSNull)
        XCTAssertTrue(payload["maxHeartRate"] is NSNull)
        XCTAssertEqual(payload["avgPowerWatts"] as? Double, 0)
        XCTAssertTrue(payload["avgCadenceRpm"] is NSNull)
        let decoded = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(ride))
        XCTAssertEqual(decoded.avgPowerWatts, 0)
        XCTAssertNil(decoded.avgCadenceRpm)
        XCTAssertEqual(decoded.energyAvailable, false)
    }
    func testMergeProjectionHidesSourcesAndSurvivesCache() throws {
        let start = Date.now
        let a = Workout(id: "a", title: "Cycling", startTime: start, durationMinutes: 20, energyKcal: 200)
        let b = Workout(id: "b", title: "Cycling", startTime: start, durationMinutes: 20, energyKcal: 200)
        let merged = Workout(id: "merge:1", title: "Combined", startTime: start, durationMinutes: 40, energyKcal: 400)
        let state = WorkoutMergeState(workouts: [merged], hiddenWorkoutIds: ["a", "b"])
        let decoded = try JSONDecoder().decode(WorkoutMergeState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.applying(to: [a,b]).map(\.id), ["merge:1"])
        XCTAssertEqual(WorkoutMergeState().applying(to: [a,b]).count, 2)
    }
    func testNormalizedPowerRequiresCompleteOneSecondRecords() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [WorkoutTelemetry.CyclingSample] = (0..<60).map { i in
            .init(time: start.addingTimeInterval(Double(i)).ISO8601Format(), endTime: start.addingTimeInterval(Double(i+1)).ISO8601Format(), value: 200)
        }
        XCTAssertEqual(try XCTUnwrap(HealthKitService.normalizedCyclingPower(rows, start: start, end: start.addingTimeInterval(60))), 200, accuracy: 0.01)
        XCTAssertNil(HealthKitService.normalizedCyclingPower(Array(rows.dropFirst()), start: start, end: start.addingTimeInterval(60)))
    }

    func testRecordedActivityExportPreservesDurationWithoutInventingDistance() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = HKWorkoutActivity(workoutConfiguration: config, start: start, end: start.addingTimeInterval(360), metadata: ["IntervalPurpose": "work", "UnrelatedPrivateField": "omit"])
        let unfinished = HKWorkoutActivity(workoutConfiguration: config, start: start, end: nil, metadata: nil)
        let rows = HealthKitService.exportWorkoutActivities([unfinished, activity])
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.durationSeconds, 360)
        XCTAssertNil(row.distanceMeters)
        XCTAssertEqual(row.metadata?["IntervalPurpose"], "work")
        XCTAssertNil(row.metadata?["UnrelatedPrivateField"])
        var telemetry = WorkoutTelemetry()
        telemetry.appleWorkoutActivities = rows
        telemetry.workoutEvents = [.init(type: "marker", startTime: start.ISO8601Format(), endTime: start.ISO8601Format(), metadata: ["IntervalPurpose":"work"])]
        let data = try JSONEncoder().encode(telemetry)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutTelemetry.self, from: data), telemetry)
    }

    func testAppleIntervalPlanPreservesPurposesGoalsAndRepeats() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("WorkoutKit requires iOS 17") }
        let custom = CustomWorkout(activity: .running,
            warmup: WorkoutStep(goal: .distance(4, .kilometers)),
            blocks: [IntervalBlock(steps: [IntervalStep(.recovery, goal: .time(1, .minutes)), IntervalStep(.work, goal: .time(6, .minutes))], iterations: 2)],
            cooldown: WorkoutStep(goal: .open))
        let plan = WorkoutPlan(.custom(custom))
        let exported = try XCTUnwrap(HealthKitService.exportWorkoutPlan(plan))
        XCTAssertEqual(exported.id, plan.id.uuidString)
        XCTAssertEqual(exported.warmup?.purpose, "warmup")
        XCTAssertEqual(exported.warmup?.targetDistanceMeters, 4000)
        XCTAssertEqual(exported.blocks.first?.iterations, 2)
        XCTAssertEqual(exported.blocks.first?.steps.map(\.purpose), ["recovery", "work"])
        XCTAssertEqual(exported.blocks.first?.steps.last?.targetSeconds, 360)
        XCTAssertNil(exported.cooldown?.targetSeconds)
        var workout = Workout(id: "planned", title: "Run", startTime: .now, durationMinutes: 48, energyKcal: 500)
        var telemetry = WorkoutTelemetry()
        telemetry.appleWorkoutPlan = exported
        workout.telemetry = telemetry
        let payload = APIClient().workoutPayload(workout)
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try XCTUnwrap(wire["appleWorkoutPlan"] as? [String: Any])
        XCTAssertEqual(fields["source"] as? String, "healthkit-workout-plan")
        XCTAssertNil(fields["actualDurationSeconds"])
        XCTAssertEqual(try JSONDecoder().decode(AppleWorkoutPlan.self, from: JSONEncoder().encode(exported)), exported)
    }

    func testAppleWarmupCooldownOnlyIsNotAnIntervalBlock() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("WorkoutKit requires iOS 17") }
        let plan = WorkoutPlan(.custom(CustomWorkout(activity: .running, warmup: WorkoutStep(goal: .open))))
        XCTAssertTrue(try XCTUnwrap(HealthKitService.exportWorkoutPlan(plan)).blocks.isEmpty)
    }

    func testDashboardCacheRoundTripWithOptionalHealthMetrics() throws {
        var summary = HealthSummary()
        summary.steps = 111
        let cache = DashboardCache(summary: summary, workouts: [], savedAt: .now)
        let data = try JSONEncoder().encode(cache)
        XCTAssertEqual(try JSONDecoder().decode(DashboardCache.self, from: data).summary.steps, 111)
    }

    func testIngestBatchesPreserveEveryWorkoutUnderByteLimit() throws {
        let base: [String: Any] = ["workouts": [], "daily": [["date": "2026-10-29"]]]
        let rows: [[String: Any]] = (0..<20).map { ["id": "run-\($0)", "title": String(repeating: "é", count: 100)] }
        let batches = try APIClient.workoutBatches(rows, base: base, limit: 1000)
        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertEqual(batches.flatMap { $0 }.compactMap { $0["id"] as? String }, rows.compactMap { $0["id"] as? String })
        for batch in batches {
            var body = base
            body["workouts"] = batch
            XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: body).count, 1000)
        }
        XCTAssertThrowsError(try APIClient.workoutBatches(rows, base: base, limit: 100))
        XCTAssertEqual(try APIClient.workoutBatches([], base: base).count, 1)
    }

    func testRouteSplitsUseMeasuredDistanceAndRejectSparseRoutes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = (0...400).map { index in
            CLLocation(coordinate: .init(latitude: 52 + Double(index) * 0.00005, longitude: 5),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                       timestamp: start.addingTimeInterval(Double(index) * 2))
        }
        let splits = HealthKitService.routeSplits(route, events: [])
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].distanceMeters, 1000)
        XCTAssertGreaterThan(splits[0].durationSeconds, 350)
        XCTAssertLessThan(splits[0].durationSeconds, 370)
        XCTAssertTrue(HealthKitService.routeSplits([route[0], route[100]], events: []).isEmpty)
        let pause = HKWorkoutEvent(type: .pause, dateInterval: .init(start: start.addingTimeInterval(101), duration: 0), metadata: nil)
        XCTAssertTrue(HealthKitService.routeSplits(route, events: [pause]).isEmpty)
    }

    func testTelemetrySurvivesCacheRoundTripWithoutInventingMissingMetrics() throws {
        var workout = Workout(id: "run", title: "Run", startTime: .now, durationMinutes: 40, energyKcal: 300)
        var telemetry = WorkoutTelemetry()
        telemetry.heartRateSamples = [.init(time: "2026-10-29T08:00:00Z", bpm: 145)]
        telemetry.workoutEvents = [.init(type: "lap", startTime: "2026-10-29T08:00:00Z", endTime: "2026-10-29T08:05:00Z")]
        workout.telemetry = telemetry
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)
        XCTAssertEqual(decoded.telemetry, telemetry)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try XCTUnwrap(object["telemetry"] as? [String: Any])
        XCTAssertNil(fields["runningPowerWatts"])
        let payload = APIClient().workoutPayload(decoded)
        let wireData = try JSONSerialization.data(withJSONObject: payload)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: wireData) as? [String: Any])
        XCTAssertEqual((wire["heartRateSamples"] as? [[String: Any]])?.first?["bpm"] as? Double, 145)
        XCTAssertEqual(wire["id"] as? String, "run")
        XCTAssertNil(wire["telemetry"])
        XCTAssertNil(wire["runningPowerWatts"])
    }

    func testProgressaDetailDecodesWithoutLosingSetMetadata() throws {
        let json = #"""
        {
          "id":"progressa:p-123","source":"progressa","externalWorkoutId":"p-123",
          "title":"Strength","startTime":"2026-06-18T08:30:00Z","durationMinutes":0,"energyKcal":0,
          "progressaDetails":{"exerciseCount":1,"totalSets":2,"totalVolumeKg":540,"hasVolumeData":true,
            "exercises":[{"id":"bench","name":"Bench Press","muscleGroup":"Chest","sets":[
              {"weightKg":20,"reps":10,"rir":null,"side":null,"isWarmup":true,"createdAt":"a"},
              {"weightKg":60,"reps":8,"rir":2,"side":"left","isWarmup":false,"createdAt":"b"}
            ]}]}
        }
        """#.data(using: .utf8)!

        let workout = try JSONDecoder().decode(Workout.self, from: json)

        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.count, 2)
        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.last?.rir, 2)
        XCTAssertEqual(workout.progressaDetails?.exercises.first?.sets.last?.side, "left")
        XCTAssertEqual(workout.effectiveDurationMinutes, 9, accuracy: 0.01)
        XCTAssertGreaterThan(workout.effectiveEnergyKcal, 0)
    }

    func testEpochDateDecodes() throws {
        let json = #"{"id":"x","title":"Run","startTime":1750235400,"durationMinutes":30,"energyKcal":250}"#.data(using: .utf8)!
        let workout = try JSONDecoder().decode(Workout.self, from: json)
        XCTAssertEqual(workout.startTime.timeIntervalSince1970, 1_750_235_400, accuracy: 0.1)
        XCTAssertNil(workout.telemetry)
    }

    func testSwiftReferenceDateDecodesFromCache() throws {
        let start = ISO8601DateFormatter().date(from: "2026-07-04T16:32:00Z")!
        let cached = try JSONEncoder().encode(Workout(id: "x", title: "Swim", startTime: start, durationMinutes: 9, energyKcal: 62))
        let workout = try JSONDecoder().decode(Workout.self, from: cached)
        XCTAssertEqual(workout.startTime.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0.1)
    }
}
