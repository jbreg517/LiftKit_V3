import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Bindable var vm: WorkoutViewModel

    private var completed: [WorkoutSession] { sessions.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            Group {
                if completed.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Complete a workout and it will appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: LKSpacing.sm) {
                            ForEach(completed) { session in
                                SwipeToDeleteRow(enabled: true, onDelete: {
                                    context.delete(session)
                                    try? context.save()
                                }) {
                                    NavigationLink {
                                        WorkoutDetailView(session: session, vm: vm)
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            vm.loadFromSession(session)
                                        } label: {
                                            Label("Do Again", systemImage: "arrow.counterclockwise")
                                        }
                                        Button(role: .destructive) {
                                            context.delete(session)
                                            try? context.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .padding(.horizontal, LKSpacing.md)
                            }
                        }
                        .padding(.vertical, LKSpacing.md)
                    }
                }
            }
            .navigationTitle("History")
            .background(LKColor.background.ignoresSafeArea())
        }
        .sheet(isPresented: $vm.showWorkoutSetup) {
            NavigationStack {
                WorkoutSetupView(vm: vm, type: vm.selectedTimerType)
            }
        }
        .fullScreenCover(isPresented: $vm.showActiveWorkout) {
            ActiveWorkoutView(vm: vm)
        }
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            HStack {
                Text(session.name)
                    .font(.headline)
                    .foregroundColor(LKColor.textPrimary)
                Spacer()
                if let type = session.timerType {
                    Text(type.displayName)
                        .font(.caption2)
                        .foregroundColor(LKColor.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LKColor.surfaceElevated)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: LKSpacing.sm) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text(session.formattedDuration)
                Text("·")
                Text("\(session.entries.count) exercises")
            }
            .font(LKFont.caption)
            .foregroundColor(LKColor.textSecondary)

            let names = session.sortedEntries.compactMap { $0.exercise?.name }
            if !names.isEmpty {
                Text(names.joined(separator: " · "))
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(LKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LKColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: LKRadius.large)
                .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
        )
        .cornerRadius(LKRadius.large)
        .contentShape(Rectangle())
    }
}

// MARK: - Workout Detail
/// Staged edits to a single set (applied to the SetRecord only on Save).
struct SetDraft {
    var weight: Double?
    var reps: Int?
    var duration: TimeInterval?
    var rpe: Double?
    var setType: SetType
}

/// Identifiable wrapper so we don't use the SwiftData model directly as a sheet item.
struct EditingSetTarget: Identifiable {
    let id: UUID
    let set: SetRecord
}

struct WorkoutDetailView: View {
    @Bindable var session: WorkoutSession
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editingTarget: EditingSetTarget?

    // Staged edits (applied only on Save; dropped on Discard).
    @State private var drafts: [UUID: SetDraft] = [:]
    @State private var deletedSetIDs: Set<UUID> = []
    @State private var draftNotes: String = ""
    @State private var notesEdited = false
    @State private var showDiscardConfirm = false

    private var isDirty: Bool {
        !drafts.isEmpty || !deletedSetIDs.isEmpty || notesEdited
    }

    /// Current (draft-aware) values for a set.
    private func effective(_ set: SetRecord) -> SetDraft {
        drafts[set.id] ?? SetDraft(weight: set.weight, reps: set.reps,
                                   duration: set.duration, rpe: set.rpe, setType: set.setType)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.md) {
                // Summary
                summarySection
                // Splits (AMRAP rounds / For Time checkpoints)
                if !session.splits.isEmpty {
                    VStack(alignment: .leading, spacing: LKSpacing.xs) {
                        LKSectionLabel(text: "SPLITS")
                        ForEach(Array(session.splits.enumerated()), id: \.offset) { i, s in
                            HStack {
                                Text("\(i + 1)")
                                    .font(LKFont.caption)
                                    .foregroundColor(LKColor.textMuted)
                                Spacer()
                                Text(TimerEngine.format(s))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundColor(LKColor.textPrimary)
                            }
                        }
                    }
                    .lkCard()
                    .padding(.horizontal, LKSpacing.md)
                }
                // Exercises
                ForEach(session.sortedEntries) { entry in
                    exerciseSection(entry: entry)
                }
                // Notes
                if isEditing {
                    VStack(alignment: .leading, spacing: LKSpacing.xs) {
                        LKSectionLabel(text: "NOTES")
                        TextField("Optional notes…", text: notesBinding, axis: .vertical)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textPrimary)
                            .lineLimit(2...6)
                    }
                    .lkCard()
                    .padding(.horizontal, LKSpacing.md)
                } else if let notes = session.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: LKSpacing.xs) {
                        LKSectionLabel(text: "NOTES")
                        Text(notes)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lkCard()
                    .padding(.horizontal, LKSpacing.md)
                }
                // Do Again
                if !isEditing {
                    Button {
                        vm.loadFromSession(session)
                    } label: {
                        Label("Do Again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(LKSecondaryButtonStyle())
                    .padding(.horizontal, LKSpacing.md)
                    .tint(LKColor.accent)
                }
            }
            .padding(.vertical, LKSpacing.md)
        }
        .navigationTitle(session.name)
        .background(LKColor.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { attemptExit() }
                        .foregroundColor(LKColor.danger)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? (isDirty ? "Save" : "Done") : "Edit") {
                    if isEditing {
                        if isDirty { applyEdits() }
                        exitEditing()
                    } else {
                        isEditing = true
                    }
                }
                .foregroundColor(LKColor.accent)
                .fontWeight(isEditing && isDirty ? .bold : .regular)
            }
        }
        .sheet(item: $editingTarget) { target in
            HistorySetEditSheet(
                initial: effective(target.set),
                isTimed: target.set.isTimed,
                setNumber: target.set.setNumber
            ) { draft in
                drafts[target.set.id] = draft
            }
        }
        .confirmationDialog("You have unsaved edits", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Save") { applyEdits(); exitEditing() }
            Button("Discard", role: .destructive) { exitEditing() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { notesEdited ? draftNotes : (session.notes ?? "") },
            set: { draftNotes = $0; notesEdited = true }
        )
    }

    /// Stages a set deletion (applied on Save).
    private func deleteSet(_ set: SetRecord) {
        deletedSetIDs.insert(set.id)
        drafts[set.id] = nil
        HapticManager.shared.buttonTap()
    }

    private func attemptExit() {
        if isDirty { showDiscardConfirm = true } else { exitEditing() }
    }

    /// Applies all staged edits/deletions/notes to the models and persists.
    private func applyEdits() {
        for set in session.entries.flatMap({ $0.sets }) {
            if deletedSetIDs.contains(set.id) {
                context.delete(set)
                continue
            }
            if let d = drafts[set.id] {
                set.weight = d.weight
                set.reps = d.reps
                set.duration = d.duration
                set.rpe = d.rpe
                set.setType = d.setType
            }
        }
        if notesEdited {
            let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            session.notes = trimmed.isEmpty ? nil : trimmed
        }
        try? context.save()
        clearDrafts()
    }

    private func exitEditing() {
        clearDrafts()
        isEditing = false
    }

    private func clearDrafts() {
        drafts.removeAll()
        deletedSetIDs.removeAll()
        draftNotes = ""
        notesEdited = false
    }

    private var summarySection: some View {
        HStack(spacing: 0) {
            statCell(value: session.formattedDuration, label: "Duration")
            Divider().background(LKColor.surfaceElevated)
            statCell(value: "\(session.entries.count)", label: "Exercises")
            Divider().background(LKColor.surfaceElevated)
            statCell(value: "\(Int(session.totalVolume)) lb", label: "Volume")
            Divider().background(LKColor.surfaceElevated)
            statCell(value: session.timerType?.rawValue ?? "—", label: "Type")
        }
        .lkCard()
        .padding(.horizontal, LKSpacing.md)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseSection(entry: WorkoutEntry) -> some View {
        let sets = entry.sortedSets
        return VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack {
                Text(entry.exercise?.name ?? "Exercise")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                if entry.supersetGroup != nil {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LKColor.accent)
                        .accessibilityLabel("Superset")
                }
                Spacer()
                if let eq = entry.exercise?.equipmentEnum, eq != .none {
                    Label(eq.rawValue, systemImage: eq.sfSymbol)
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LKColor.surfaceElevated)
                        .clipShape(Capsule())
                }
            }

            if !sets.isEmpty {
                // Summary: "3 sets · 30 reps · 95 lb"
                let totalReps = sets.compactMap(\.reps).reduce(0, +)
                let firstWeight = sets.first?.weight
                let unit = sets.first?.weightUnit ?? ""
                HStack(spacing: 4) {
                    Text("\(sets.count) set\(sets.count == 1 ? "" : "s")")
                    if totalReps > 0 {
                        Text("·").foregroundColor(LKColor.textMuted)
                        Text("\(totalReps) reps")
                    }
                    if let w = firstWeight, w > 0 {
                        Text("·").foregroundColor(LKColor.textMuted)
                        Text("\(Int(w)) \(unit)")
                    }
                }
                .font(LKFont.caption)
                .foregroundColor(LKColor.textSecondary)

                ForEach(sets.filter { !deletedSetIDs.contains($0.id) }) { set in
                    if isEditing {
                        HStack(spacing: LKSpacing.sm) {
                            Button { editingTarget = EditingSetTarget(id: set.id, set: set) } label: { setRow(set: set) }
                                .buttonStyle(.plain)
                            Button(role: .destructive) { deleteSet(set) } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(LKColor.danger)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete set \(set.setNumber)")
                        }
                    } else {
                        setRow(set: set)
                    }
                }
            }
        }
        .lkCard()
        .padding(.horizontal, LKSpacing.md)
    }

    /// Formats a hold time: "45s" under a minute, "1:30" otherwise.
    static func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func setRow(set: SetRecord) -> some View {
        let eff = effective(set)
        return HStack {
            Text("Set \(set.setNumber)")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .frame(width: 44, alignment: .leading)

            if let badge = eff.setType.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 16, height: 16)
                    .background(eff.setType == .failure ? LKColor.danger : LKColor.accent)
                    .clipShape(Circle())
            }

            if let weight = eff.weight {
                Text("\(Int(weight)) \(set.weightUnit)")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                if let planned = set.plannedWeight, abs(planned - weight) > 0.5 {
                    Text("(\(Int(planned)))")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                }
            }

            if let reps = eff.reps {
                Text("×")
                    .foregroundColor(LKColor.textMuted)
                Text("\(reps) reps")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                if let planned = set.plannedReps, planned != reps {
                    Text("(\(planned))")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                }
            } else if let duration = eff.duration {
                Text(Self.durationLabel(Int(duration)))
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                if let planned = set.plannedDuration, planned != Int(duration) {
                    Text("(\(Self.durationLabel(planned)))")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                }
            }
            Spacer()
            if let rpe = eff.rpe {
                Text("Rate of Perceived Exertion: \(rpe == rpe.rounded() ? "\(Int(rpe))" : String(format: "%.1f", rpe))")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if isEditing {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(LKColor.textMuted)
            }
        }
    }
}

// MARK: - Edit a logged set (history)

struct HistorySetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightIncrement") private var weightIncrement: Double = 5

    let isTimed: Bool
    let setNumber: Int
    let onSave: (SetDraft) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var duration: Int
    @State private var rpe: Double?
    @State private var setType: SetType

    private let rpeOptions: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    init(initial: SetDraft, isTimed: Bool, setNumber: Int, onSave: @escaping (SetDraft) -> Void) {
        self.isTimed = isTimed
        self.setNumber = setNumber
        self.onSave = onSave
        _weight = State(initialValue: initial.weight ?? 0)
        _reps = State(initialValue: initial.reps ?? 0)
        _duration = State(initialValue: Int(initial.duration ?? 0))
        _rpe = State(initialValue: initial.rpe)
        _setType = State(initialValue: initial.setType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                        Stepper("", value: $weight, in: 0...2000, step: weightIncrement)
                            .labelsHidden()
                    }
                }
                if isTimed {
                    Section("Seconds") {
                        HStack {
                            TextField("0", value: $duration, format: .number)
                                .keyboardType(.numberPad)
                            Stepper("", value: $duration, in: 0...600, step: 5)
                                .labelsHidden()
                        }
                    }
                } else {
                    Section("Reps") {
                        HStack {
                            TextField("0", value: $reps, format: .number)
                                .keyboardType(.numberPad)
                            Stepper("", value: $reps, in: 0...100)
                                .labelsHidden()
                        }
                    }
                }
                Section {
                    Picker("RPE", selection: $rpe) {
                        Text("—").tag(Double?.none)
                        ForEach(rpeOptions, id: \.self) { v in
                            Text(v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v))
                                .tag(Double?.some(v))
                        }
                    }
                } header: {
                    Text("Rate of Perceived Exertion")
                } footer: {
                    Text("How hard the set felt, 1 (very easy) to 10 (maximal effort).")
                }
                Section("Set Type") {
                    Picker("Type", selection: $setType) {
                        ForEach(SetType.allCases) { t in Text(t.label).tag(t) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(SetDraft(
                            weight: weight > 0 ? weight : nil,
                            reps: isTimed ? nil : (reps > 0 ? reps : nil),
                            duration: isTimed ? (duration > 0 ? TimeInterval(duration) : nil) : nil,
                            rpe: rpe,
                            setType: setType
                        ))
                        dismiss()
                    }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
