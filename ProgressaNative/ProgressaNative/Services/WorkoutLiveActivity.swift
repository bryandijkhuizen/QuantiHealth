import ActivityKit
import UIKit

/// Serialize ActivityKit updates so a late update cannot resurrect an ended workout.
@MainActor
final class WorkoutLiveActivity {
    private var desired: ProgressaWorkout?
    private var revision = 0
    private var worker: Task<Void, Never>?

    func sync(_ workout: ProgressaWorkout?) {
        desired = workout
        revision += 1
        guard worker == nil else { return }
        worker = Task {
            var processed = -1
            while processed != revision {
                processed = revision
                if #available(iOS 16.2, *) { await apply(desired) }
            }
            worker = nil
        }
    }

    @available(iOS 16.2, *)
    private func apply(_ workout: ProgressaWorkout?) async {
        let active = workout?.isInProgress == true ? workout : nil
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.workoutID != active?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let active, let start = active.startedAt else { return }
        let state = WorkoutActivityAttributes.ContentState(
            title: String(active.title.prefix(80)), startedAt: start, loggedSets: active.totalSets,
            exerciseName: active.exercises.last(where: { !$0.sets.isEmpty }).map { String($0.name.prefix(80)) },
            endedAt: nil
        )
        let content = ActivityContent(state: state, staleDate: start.addingTimeInterval(8 * 3600))
        if let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.workoutID == active.id }) {
            await activity.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled,
                  UIApplication.shared.applicationState == .active,
                  start.addingTimeInterval(8 * 3600) > .now {
            // Live Activities are optional; a denied request must never prevent workout logging.
            _ = try? Activity.request(attributes: WorkoutActivityAttributes(workoutID: active.id), content: content, pushType: nil)
        }
    }
}
