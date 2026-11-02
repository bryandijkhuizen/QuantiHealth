import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ProgressaLiveActivityBundle: WidgetBundle {
    var body: some Widget { ProgressaWorkoutActivity() }
}

struct ProgressaWorkoutActivity: Widget {
    // Lighter Progressa violet keeps small controls legible against the black Island.
    private let islandPurple = Color(red: 0.68, green: 0.52, blue: 1)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Workout in progress", systemImage: "dumbbell.fill").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.36, green: 0.18, blue: 1))
                    Spacer(minLength: 8)
                    elapsed(context.state).font(.title2.weight(.semibold)).frame(maxWidth: 110)
                }
                Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
                HStack {
                    Text("\(context.state.loggedSets) sets logged")
                    Spacer()
                    Label("Continue", systemImage: "arrow.up.forward")
                }.font(.subheadline.weight(.medium))
            }
            .padding(14)
            .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "dumbbell.fill").font(.title3).foregroundStyle(islandPurple).accessibilityLabel("Progressa workout")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context.state).font(.headline).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.headline).lineLimit(1).privacySensitive()
                        HStack {
                            Text("\(context.state.loggedSets) sets logged")
                            Spacer()
                            Label("Open", systemImage: "arrow.up.forward").foregroundStyle(islandPurple)
                        }.font(.subheadline.weight(.medium))
                    }.padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(islandPurple).accessibilityLabel("Workout in progress")
            } compactTrailing: {
                elapsed(context.state).font(.caption.weight(.semibold)).frame(width: 52)
            } minimal: {
                Text("\(context.state.loggedSets)").font(.caption.weight(.semibold))
                    .foregroundStyle(islandPurple).accessibilityLabel("\(context.state.loggedSets) sets logged")
            }
            .widgetURL(context.attributes.url)
            .keylineTint(islandPurple)
        }
    }

    private func elapsed(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...max(state.startedAt, state.startedAt.addingTimeInterval(8 * 3600)), countsDown: false)
            .monospacedDigit().multilineTextAlignment(.trailing)
            .accessibilityLabel("Workout duration")
    }
}

@available(iOS 17.0, *)
#Preview("Workout", as: .content, using: WorkoutActivityAttributes(workoutID: "preview")) {
    ProgressaWorkoutActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(title: "Push Day", startedAt: .now.addingTimeInterval(-1260), loggedSets: 8, exerciseName: "Bench Press", endedAt: nil)
}

@available(iOS 17.0, *)
#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes(workoutID: "preview")) {
    ProgressaWorkoutActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(title: "Push Day", startedAt: .now.addingTimeInterval(-1260), loggedSets: 8, exerciseName: "Bench Press", endedAt: nil)
}
