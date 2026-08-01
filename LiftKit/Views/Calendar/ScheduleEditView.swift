import SwiftUI
import SwiftData

struct ScheduleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    let schedule: WorkoutSchedule
    let isNew: Bool

    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var allTemplates: [WorkoutTemplate]
    /// User plans only — program-generated session templates are hidden from the
    /// single-day scheduler's template picker.
    private var templates: [WorkoutTemplate] { allTemplates.filter { !$0.isProgramGenerated } }

    @State private var date: Date
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var customName: String
    @State private var notes: String
    @State private var showDeleteConfirm = false

    init(schedule: WorkoutSchedule, vm: WorkoutViewModel, isNew: Bool = false) {
        self.schedule = schedule
        self.vm = vm
        self.isNew = isNew
        _date          = State(initialValue: schedule.date)
        _selectedTemplate = State(initialValue: schedule.template)
        _customName    = State(initialValue: schedule.customName ?? "")
        _notes         = State(initialValue: schedule.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Workout Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(LKColor.accent)
                }

                Section("Workout") {
                    if templates.isEmpty {
                        TextField("Workout name", text: $customName)
                    } else {
                        Picker("Template", selection: $selectedTemplate) {
                            Text("Custom").tag(WorkoutTemplate?.none)
                            ForEach(templates) { t in
                                Text(t.name).tag(WorkoutTemplate?.some(t))
                            }
                        }
                        if selectedTemplate == nil {
                            TextField("Custom workout name", text: $customName)
                        }
                    }
                    // Schedule a prebuilt workout without building it first — picking
                    // one materialises it into a plan and selects it here.
                    NavigationLink {
                        PrebuiltWorkoutPicker { rec in
                            selectedTemplate = rec.materializedTemplate(in: context)
                            customName = ""
                        }
                    } label: {
                        Label("Choose Prebuilt Workout", systemImage: "square.grid.2x2")
                            .foregroundColor(LKColor.accent)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Jump into the full workout setup (weights, times, sets, rounds…)
                // for the chosen plan. Edits/starts there behave like any workout;
                // this screen stays about *when* it's scheduled.
                if let template = selectedTemplate {
                    Section {
                        Button {
                            // Dismiss this sheet first, then present the setup on the
                            // next runloop — presenting a sheet in the same tick another
                            // is dismissing makes SwiftUI silently drop it.
                            dismiss()
                            let t = template
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                vm.loadFromTemplate(t, type: t.sortedExercises.first?.timerType ?? .reps)
                                vm.showWorkoutSetup = true
                            }
                        } label: {
                            Label("Edit Workout", systemImage: "slider.horizontal.3")
                        }
                    } footer: {
                        Text("Open the full workout to adjust weights, reps, times and rounds.")
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Scheduled Workout", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
            }
            .confirmationDialog("Delete this scheduled workout?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        if isNew {
            context.insert(schedule)
        }
        schedule.date = date
        schedule.template = selectedTemplate
        schedule.customName = customName.isEmpty ? nil : customName
        schedule.notes = notes.isEmpty ? nil : notes
        Persist.save(context)
        // Keep the local reminder in sync with the (possibly changed) date.
        WorkoutReminders.cancel(schedule)
        WorkoutReminders.schedule(schedule)
        dismiss()
    }

    private func delete() {
        WorkoutReminders.cancel(schedule)
        context.delete(schedule)
        Persist.save(context)
        dismiss()
    }
}

// MARK: - Prebuilt workout picker
//
// A searchable list of the recommended-workout catalog, shared by the single-day
// scheduler and the series scheduler. On pick, the caller materialises the chosen
// prebuilt into a reusable `WorkoutTemplate` (see `RecommendedWorkout
// .materializedTemplate`) and this view pops.
struct PrebuiltWorkoutPicker: View {
    let onPick: (RecommendedWorkout) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [RecommendedWorkout] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return RecommendedWorkouts.all }
        return RecommendedWorkouts.all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.blurb.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            ForEach(results) { workout in
                Button {
                    onPick(workout)
                    HapticManager.shared.buttonTap()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .font(LKFont.body).foregroundColor(LKColor.textPrimary)
                        Text(workout.type.rawValue)
                            .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LKColor.background.ignoresSafeArea())
        .searchable(text: $search, prompt: "Search prebuilt workouts")
        .navigationTitle("Prebuilt Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
