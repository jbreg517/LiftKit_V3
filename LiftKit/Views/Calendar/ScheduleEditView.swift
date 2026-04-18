import SwiftUI
import SwiftData

struct ScheduleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    let schedule: WorkoutSchedule
    let isNew: Bool

    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]

    @State private var date: Date
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var customName: String
    @State private var notes: String
    @State private var showDeleteConfirm = false

    init(schedule: WorkoutSchedule, vm: WorkoutViewModel) {
        self.schedule = schedule
        self.vm = vm
        self.isNew = schedule.id == UUID() // heuristic for new
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
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
        schedule.date = date
        schedule.template = selectedTemplate
        schedule.customName = customName.isEmpty ? nil : customName
        schedule.notes = notes.isEmpty ? nil : notes

        if isNew {
            context.insert(schedule)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        context.delete(schedule)
        try? context.save()
        dismiss()
    }
}
