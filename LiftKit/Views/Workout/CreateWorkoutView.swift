import SwiftUI
import SwiftData

struct CreateWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    @State private var workoutName = ""
    @State private var exercises: [CreateExerciseRow] = []

    struct CreateExerciseRow: Identifiable {
        let id = UUID()
        var name: String = ""
        var timerType: TimerType = .reps
        var sets: Int = 3
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Name") {
                    TextField("e.g., Push Day", text: $workoutName)
                        .font(.title3)
                }

                Section("Exercises") {
                    ForEach($exercises) { $ex in
                        VStack(alignment: .leading, spacing: LKSpacing.sm) {
                            TextField("Exercise name", text: $ex.name)
                                .font(.headline)

                            Picker("Type", selection: $ex.timerType) {
                                ForEach(TimerType.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)

                            Stepper("Sets: \(ex.sets)", value: $ex.sets, in: 1...20)
                        }
                        .padding(.vertical, LKSpacing.xs)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        exercises.append(CreateExerciseRow())
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .foregroundColor(LKColor.accent)
                }
            }
            .navigationTitle("New Workout")
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startWorkout()
                    }
                    .bold()
                    .disabled(exercises.isEmpty)
                }
            }
        }
    }

    private func startWorkout() {
        let name = workoutName.isEmpty
            ? "Workout \(Date().formatted(date: .abbreviated, time: .omitted))"
            : workoutName

        vm.workoutName = name
        vm.selectedTimerType = exercises.first?.timerType ?? .reps
        vm.exercises = exercises.map { row in
            var card = ExerciseCard()
            card.name = row.name
            card.sets = row.sets
            return card
        }
        vm.startTimedWorkout(context: context)
        dismiss()
    }
}
