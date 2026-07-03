import Foundation

struct ProgressaRoutine: Identifiable, Hashable {
    let id: String
    let userId: String
    var name: String
    let createdAt: Date
}

struct ProgressaRoutineExercise: Identifiable, Hashable {
    let id: String
    let routineId: String
    let exercise: ProgressaExerciseLibraryItem
    var sortOrder: Int
}

struct ProgressaRoutineSet: Identifiable, Hashable {
    let id: String
    let routineExerciseId: String
    let routineId: String
    let exerciseId: String
    var reps: Int?
    var weightKg: Double?
    var rir: Int?
    var side: String?
    var sortOrder: Int

    var workoutInput: ProgressaSetInput {
        ProgressaSetInput(
            weightKg: weightKg, reps: reps, rir: rir.map(Double.init), side: side, isWarmup: false
        )
    }
}

struct ProgressaRoutineDetail: Equatable {
    var routine: ProgressaRoutine
    var exercises: [ProgressaRoutineExercise]
    var sets: [ProgressaRoutineSet]

    func workoutExercises(copyWeights: Bool) -> [ProgressaExerciseInput] {
        exercises.sorted { $0.sortOrder < $1.sortOrder }.map { entry in
            let templates = sets
                .filter { $0.routineExerciseId == entry.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            return ProgressaExerciseInput(
                exercise: entry.exercise,
                sets: templates.map { template in
                    var input = template.workoutInput
                    if !copyWeights { input.weightKg = nil }
                    return input
                }
            )
        }
    }
}
