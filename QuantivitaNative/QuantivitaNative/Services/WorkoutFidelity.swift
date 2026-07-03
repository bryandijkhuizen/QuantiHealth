import CoreLocation
import Foundation

enum WorkoutFidelity {
    static func sourceUUIDs(for workouts: [Workout]) -> [UUID] {
        workouts.compactMap { workout in
            guard workout.source == "healthkit" else { return nil }
            return UUID(uuidString: workout.id)
        }
    }

    /// Disjoint active time intervals from the (possibly overlapping) source workouts.
    static func activeSegments(for workouts: [Workout]) -> [DateInterval] {
        let raw = workouts.compactMap { workout -> (Date, Date)? in
            let seconds = max(0, workout.effectiveDurationMinutes) * 60
            guard seconds > 0 else { return nil }
            return (workout.startTime, workout.startTime.addingTimeInterval(seconds))
        }.sorted { $0.0 < $1.0 }
        guard var currentStart = raw.first?.0, var currentEnd = raw.first?.1 else { return [] }
        var merged: [DateInterval] = []
        for (start, end) in raw.dropFirst() {
            if start <= currentEnd {
                currentEnd = max(currentEnd, end)
            } else {
                merged.append(DateInterval(start: currentStart, end: currentEnd))
                currentStart = start; currentEnd = end
            }
        }
        merged.append(DateInterval(start: currentStart, end: currentEnd))
        return merged
    }

    /// Total active time across the source workouts (overlaps counted once).
    static func movingDuration(for workouts: [Workout]) -> TimeInterval {
        activeSegments(for: workouts).reduce(0) { $0 + $1.duration }
    }

    /// Idle gaps between the active segments, marked as paused in the merged workout
    /// so its reported duration is the active time rather than the wall-clock span.
    static func pausedGaps(for workouts: [Workout]) -> [DateInterval] {
        let segments = activeSegments(for: workouts)
        guard segments.count > 1 else { return [] }
        return zip(segments, segments.dropFirst()).compactMap { earlier, later in
            later.start > earlier.end ? DateInterval(start: earlier.end, end: later.start) : nil
        }
    }

    static func weightedAverageHeartRate(for workouts: [Workout]) -> Double {
        let measured = workouts.filter { $0.averageHeartRate > 0 && $0.effectiveDurationMinutes > 0 }
        let duration = measured.reduce(0) { $0 + $1.effectiveDurationMinutes }
        guard duration > 0 else { return 0 }
        return measured.reduce(0) { $0 + $1.averageHeartRate * $1.effectiveDurationMinutes } / duration
    }

    static func deduplicatedLocations(_ locations: [CLLocation]) -> [CLLocation] {
        var seen = Set<LocationKey>()
        return locations.sorted { $0.timestamp < $1.timestamp }.filter { location in
            seen.insert(LocationKey(location)).inserted
        }
    }

    static func elevationGain(_ locations: [CLLocation]) -> Double {
        zip(locations, locations.dropFirst()).reduce(0) { total, pair in
            let gain = pair.1.altitude - pair.0.altitude
            return total + (gain > 0 ? gain : 0)
        }
    }
}

private struct LocationKey: Hashable {
    let milliseconds: Int64
    let latitude: Double
    let longitude: Double

    init(_ location: CLLocation) {
        milliseconds = Int64((location.timestamp.timeIntervalSince1970 * 1000).rounded())
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }
}
