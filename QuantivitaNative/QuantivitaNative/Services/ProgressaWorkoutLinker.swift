import Foundation

enum ProgressaWorkoutLinker {
    static func attach(_ linked: [Workout], to healthActivities: [Workout]) -> [Workout] {
        var result = healthActivities.filter { !$0.isProgressa }.map(clearingLink)
        var claimedHealthIds = Set<String>()

        for progressa in linked
            .filter({ $0.isProgressa && $0.healthActivityLink != nil })
            .sorted(by: { ($0.externalWorkoutId ?? $0.id) < ($1.externalWorkoutId ?? $1.id) }) {
            guard let link = progressa.healthActivityLink,
                  let linkStart = date(link.healthStart),
                  let linkEnd = date(link.healthEnd) else { continue }
            let candidates = result.enumerated().compactMap { index, health -> (Int, TimeInterval)? in
                guard !claimedHealthIds.contains(health.id) else { return nil }
                let startDelta = abs(health.startTime.timeIntervalSince(linkStart))
                let healthEnd = health.startTime.addingTimeInterval(health.effectiveDurationMinutes * 60)
                let endDelta = abs(healthEnd.timeIntervalSince(linkEnd))
                guard startDelta <= 5, endDelta <= 90 else { return nil }
                return (index, startDelta + endDelta)
            }.sorted { $0.1 < $1.1 }
            guard let index = candidates.first?.0 else { continue }
            claimedHealthIds.insert(result[index].id)
            result[index].externalWorkoutId = progressa.externalWorkoutId
            result[index].progressaWorkoutTitle = progressa.title
            result[index].healthActivityLink = link
            result[index].progressaDetails = progressa.progressaDetails
        }
        return result.sorted { $0.startTime > $1.startTime }
    }

    static func preserveLinks(from cached: [Workout], on fresh: [Workout]) -> [Workout] {
        let byId = Dictionary(uniqueKeysWithValues: cached.filter {
            !$0.isProgressa && $0.progressaDetails != nil
        }.map { ($0.id, $0) })
        return fresh.map { activity in
            guard let old = byId[activity.id] else { return activity }
            var value = activity
            value.externalWorkoutId = old.externalWorkoutId
            value.progressaWorkoutTitle = old.progressaWorkoutTitle
            value.healthActivityLink = old.healthActivityLink
            value.progressaDetails = old.progressaDetails
            return value
        }
    }

    private static func clearingLink(_ activity: Workout) -> Workout {
        var value = activity
        value.externalWorkoutId = nil
        value.progressaWorkoutTitle = nil
        value.healthActivityLink = nil
        value.progressaDetails = nil
        return value
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
