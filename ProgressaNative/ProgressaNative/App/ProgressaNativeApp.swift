import SwiftUI

@main
struct ProgressaNativeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ProgressaModel()
    @AppStorage("progressa.theme") private var theme = ProgressaThemeMode.system.rawValue
    @AppStorage("progressa.accent") private var accent = ProgressaAccent.presets[0].id

    var body: some Scene {
        WindowGroup {
            ProgressaRootView()
                .environmentObject(model)
                .tint(ProgressaAccent.color(for: accent))
                .preferredColorScheme(ProgressaThemeMode(rawValue: theme)?.colorScheme)
                .task {
                    if ProgressaRootView.isWorkoutPreview {
                        #if DEBUG
                        let workout = ProgressaWorkout(
                            id: "preview", title: "Push Day", createdAt: .now.addingTimeInterval(-1260),
                            exercises: [ProgressaExercise(id: "bench", name: "Bench Press", sets: [
                                ProgressaWorkoutSet(id: "one", weightKg: 60, reps: 10, isWarmup: false),
                                ProgressaWorkoutSet(id: "two", weightKg: 65, reps: 8, isWarmup: false)
                            ])], startedAt: .now.addingTimeInterval(-1260)
                        )
                        model.workouts = [workout]
                        model.workoutRoute = workout.id
                        #endif
                    } else { await model.bootstrap() }
                }
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.syncLiveActivity(); Task { await model.refreshWorkouts() } }
                }
        }
    }
}
