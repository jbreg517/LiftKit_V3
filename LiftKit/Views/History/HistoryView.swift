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
                                    vm.repeatWorkout(session: session, context: context)
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
        }
        .padding(.vertical, LKSpacing.xs)
    }
}

// MARK: - Workout Detail
struct WorkoutDetailView: View {
    let session: WorkoutSession
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.md) {
                // Summary
                summarySection
                // Exercises
                ForEach(session.sortedEntries) { entry in
                    exerciseSection(entry: entry)
                }
                // Notes
                if let notes = session.notes, !notes.isEmpty {
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
                Button {
                    vm.repeatWorkout(session: session, context: context)
                } label: {
                    Label("Do Again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(LKSecondaryButtonStyle())
                .padding(.horizontal, LKSpacing.md)
                .tint(LKColor.accent)
            }
            .padding(.vertical, LKSpacing.md)
        }
        .navigationTitle(session.name)
        .background(LKColor.background.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
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

            ForEach(entry.sortedSets) { set in
                setRow(set: set)
            }
        }
        .lkCard()
        .padding(.horizontal, LKSpacing.md)
    }

    private func setRow(set: SetRecord) -> some View {
        HStack {
            Text("Set \(set.setNumber)")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .frame(width: 44, alignment: .leading)

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
            }
            Spacer()
        }
    }
}
