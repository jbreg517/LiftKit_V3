import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Bindable var vm: WorkoutViewModel

    var body: some View {
        NavigationStack {
            Group {
                if sessions.filter({ !$0.isActive }).isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Complete a workout and it will appear here.")
                    )
                } else {
                    List {
                        ForEach(sessions.filter { !$0.isActive }) { session in
                            NavigationLink(destination: WorkoutDetailView(session: session, vm: vm)) {
                                SessionRow(session: session)
                            }
                            .listRowBackground(LKColor.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(session)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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
                    Text(type.rawValue)
                        .font(.caption2)
                        .foregroundColor(LKColor.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(UIColor.systemGray5))
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
        .padding(.vertical, LKSpacing.xs)
    }
}

// MARK: - Workout Detail
struct WorkoutDetailView: View {
    @Bindable var session: WorkoutSession
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context

    @State private var isEditing = false
    @State private var editingSet: SetRecord?

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { try? context.save() }
                    isEditing.toggle()
                }
                .foregroundColor(LKColor.accent)
            }
        }
        .sheet(item: $editingSet) { set in
            HistorySetEditSheet(set: set)
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { session.notes ?? "" },
            set: { session.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private func deleteSet(_ set: SetRecord) {
        context.delete(set)
        try? context.save()
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

                ForEach(sets) { set in
                    if isEditing {
                        HStack(spacing: LKSpacing.sm) {
                            Button { editingSet = set } label: { setRow(set: set) }
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
        HStack {
            Text("Set \(set.setNumber)")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .frame(width: 44, alignment: .leading)

            if let badge = set.setType.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 16, height: 16)
                    .background(set.setType == .failure ? LKColor.danger : LKColor.accent)
                    .clipShape(Circle())
            }

            if let weight = set.weight {
                Text("\(Int(weight)) \(set.weightUnit)")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                if let planned = set.plannedWeight, abs(planned - weight) > 0.5 {
                    Text("(\(Int(planned)))")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                }
            }

            if let reps = set.reps {
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
            } else if let duration = set.duration {
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
            if let rpe = set.rpe {
                Text("RPE \(rpe == rpe.rounded() ? "\(Int(rpe))" : String(format: "%.1f", rpe))")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
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
    @Environment(\.modelContext) private var context
    @AppStorage("weightIncrement") private var weightIncrement: Double = 5

    let set: SetRecord
    private let isTimed: Bool

    @State private var weight: Double
    @State private var reps: Int
    @State private var duration: Int
    @State private var rpe: Double?
    @State private var setType: SetType

    private let rpeOptions: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    init(set: SetRecord) {
        self.set = set
        self.isTimed = set.isTimed
        _weight = State(initialValue: set.weight ?? 0)
        _reps = State(initialValue: set.reps ?? 0)
        _duration = State(initialValue: Int(set.duration ?? 0))
        _rpe = State(initialValue: set.rpe)
        _setType = State(initialValue: set.setType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight (\(set.weightUnit))") {
                    Stepper("\(Int(weight))", value: $weight, in: 0...2000, step: weightIncrement)
                }
                if isTimed {
                    Section("Seconds") {
                        Stepper("\(duration)", value: $duration, in: 0...600, step: 5)
                    }
                } else {
                    Section("Reps") {
                        Stepper("\(reps)", value: $reps, in: 0...100)
                    }
                }
                Section("RPE") {
                    Picker("RPE", selection: $rpe) {
                        Text("—").tag(Double?.none)
                        ForEach(rpeOptions, id: \.self) { v in
                            Text(v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v))
                                .tag(Double?.some(v))
                        }
                    }
                }
                Section("Set Type") {
                    Picker("Type", selection: $setType) {
                        ForEach(SetType.allCases) { t in Text(t.label).tag(t) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Set \(set.setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        set.weight = weight > 0 ? weight : nil
        if isTimed {
            set.duration = duration > 0 ? TimeInterval(duration) : nil
        } else {
            set.reps = reps > 0 ? reps : nil
        }
        set.rpe = rpe
        set.setType = setType
        try? context.save()
        dismiss()
    }
}
