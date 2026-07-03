import Foundation

/// A single GPS sample carried into the merged Strava upload.
struct WorkoutRoutePoint: Equatable {
    let time: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let cumulativeDistanceMeters: Double
}

enum StravaTCXBuilder {
    private static let maxTrackpoints = 2_500

    /// Builds a TCX for the merged workout. `uniqueStartOffset` shifts the whole timeline
    /// forward so Strava never rejects the upload as a duplicate of one of its source
    /// activities. `route` carries the combined GPS track so Strava can draw a map.
    static func build(workouts: [Workout], uniqueStartOffset: TimeInterval = 0, route: [WorkoutRoutePoint] = []) -> String? {
        guard workouts.count >= 2,
              let rawStart = workouts.map(\.startTime).min() else { return nil }
        let rawEnd = workouts.map { $0.startTime.addingTimeInterval($0.effectiveDurationMinutes * 60) }.max() ?? rawStart
        guard rawEnd > rawStart else { return nil }
        let start = rawStart.addingTimeInterval(uniqueStartOffset)
        let end = rawEnd.addingTimeInterval(uniqueStartOffset)
        let energy = Int(workouts.reduce(0) { $0 + $1.effectiveEnergyKcal }.rounded())
        let distance = max(0, workouts.reduce(0) { $0 + $1.distanceMeters })
        let averageHeartRate = Int(WorkoutFidelity.weightedAverageHeartRate(for: workouts).rounded())
        let maxHeartRate = Int(workouts.map(\.maxHeartRate).max()?.rounded() ?? 0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)
        let sport = workouts.contains(where: { $0.typeCode == 1 || $0.typeCode == 2 || $0.typeCode == 8 }) ? "Running"
            : workouts.contains(where: { $0.typeCode == 3 }) ? "Biking" : "Other"
        let averageXML = averageHeartRate > 0 ? "<AverageHeartRateBpm><Value>\(averageHeartRate)</Value></AverageHeartRateBpm>" : ""
        let maximumXML = maxHeartRate > 0 ? "<MaximumHeartRateBpm><Value>\(maxHeartRate)</Value></MaximumHeartRateBpm>" : ""
        let track = trackXML(
            route: route, offset: uniqueStartOffset, formatter: formatter,
            startText: startText, endText: endText, totalDistance: distance
        )
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <Activities><Activity Sport="\(sport)"><Id>\(startText)</Id><Lap StartTime="\(startText)">
            <TotalTimeSeconds>\(Int(end.timeIntervalSince(start).rounded()))</TotalTimeSeconds><DistanceMeters>\(distance)</DistanceMeters><Calories>\(energy)</Calories>
            \(averageXML)\(maximumXML)<Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
            <Track>\(track)</Track>
          </Lap></Activity></Activities><Author xsi:type="Application_t"><Name>Quantivita</Name></Author>
        </TrainingCenterDatabase>
        """
    }

    private static func trackXML(
        route: [WorkoutRoutePoint], offset: TimeInterval, formatter: ISO8601DateFormatter,
        startText: String, endText: String, totalDistance: Double
    ) -> String {
        let points = downsample(route)
        guard !points.isEmpty else {
            // No GPS: keep the distance-only two-point track so the upload still has a duration/distance.
            return "<Trackpoint><Time>\(startText)</Time><DistanceMeters>0</DistanceMeters></Trackpoint>"
                + "<Trackpoint><Time>\(endText)</Time><DistanceMeters>\(totalDistance)</DistanceMeters></Trackpoint>"
        }
        return points.map { point in
            let time = formatter.string(from: point.time.addingTimeInterval(offset))
            let latitude = String(format: "%.7f", point.latitude)
            let longitude = String(format: "%.7f", point.longitude)
            let altitude = point.altitudeMeters.map { "<AltitudeMeters>\(String(format: "%.1f", $0))</AltitudeMeters>" } ?? ""
            let distance = String(format: "%.1f", point.cumulativeDistanceMeters)
            return "<Trackpoint><Time>\(time)</Time><Position><LatitudeDegrees>\(latitude)</LatitudeDegrees><LongitudeDegrees>\(longitude)</LongitudeDegrees></Position>\(altitude)<DistanceMeters>\(distance)</DistanceMeters></Trackpoint>"
        }.joined()
    }

    /// Strava handles large tracks, but keep the payload sane by thinning very dense routes.
    private static func downsample(_ points: [WorkoutRoutePoint]) -> [WorkoutRoutePoint] {
        guard points.count > maxTrackpoints else { return points }
        let step = Double(points.count) / Double(maxTrackpoints)
        var result: [WorkoutRoutePoint] = []
        var cursor = 0.0
        while Int(cursor) < points.count {
            result.append(points[Int(cursor)])
            cursor += step
        }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}
