import SwiftUI
import SwiftData

struct WorkoutSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    @State private var numberEntry: NumberEntryItem?
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var templateError = ""
    @State private var notesExpanded = false

    let type: TimerType

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.lg) {
                typeHeader
                nameSection
                typeControls
                notesSection
                startButton
            }
            .padding(LKSpacing.md)
        }
        .background(LKColor.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { dismiss() }
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.danger)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { showSaveTemplate = true }
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.accent)
            }
        }
        .sheet(item: $numberEntry) { item in
            NumberEntrySheet(item: item)
                .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showSaveTemplate) { saveTemplateSheet }
    }

    // MARK: - Header

    private var typeHeader: some View {
        VStack(spacing: LKSpacing.sm) {
            Image(systemName: type.sfSymbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(LKColor.accent)
            Text(type.rawValue)
                .font(LKFont.title)
                .foregroundColor(LKColor.textPrimary)
            Text(type.subtitle)
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, LKSpacing.sm)
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            LKSectionLabel(text: "WORKOUT NAME")
            TextField("e.g. Morning \(type.rawValue)", text: $vm.workoutName)
                .font(LKFont.body)
                .foregroundColor(LKColor.textPrimary)
                .padding(LKSpacing.md)
                .background(LKColor.surface)
                .cornerRadius(LKRadius.medium)
        }
    }

    // MARK: - Notes (collapsible)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { notesExpanded.toggle() }
            } label: {
                HStack {
                    LKSectionLabel(text: "NOTES")
                    Spacer()
                    Image(systemName: notesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LKColor.textMuted)
                }
            }

            if notesExpanded {
                TextField("Optional notes...", text: $vm.notes, axis: .vertical)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                    .lineLimit(3...6)
                    .padding(LKSpacing.md)
                    .background(LKColor.surface)
                    .cornerRadius(LKRadius.medium)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Start

    private var startButton: some View {
        Button {
            HapticManager.shared.buttonTap()
            vm.selectedTimerType = type
            vm.startTimedWorkout(context: context)
            vm.showTypePicker = false
        } label: {
            Label("Start \(type.rawValue)", systemImage: "play.fill")
        }
        .buttonStyle(LKPrimaryButtonStyle())
    }

    // MARK: - Type-specific controls

    @ViewBuilder
    private var typeControls: some View {
        switch type {
        case .amrap:     amrapControls
        case .emom:      emomControls
        case .forTime:   forTimeControls
        case .intervals: intervalsControls
        case .reps:      repsControls
        case .manual:    manualControls
        }
    }

    // MARK: AMRAP

    private var amrapControls: some View {
        VStack(spacing: LKSpacing.md) {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                LKSectionLabel(text: "TIME LIMIT")
                timePicker(minutes: $vm.timeLimitMinutes, seconds: $vm.timeLimitSeconds)
            }
            sessionsList(cards: $vm.sessions, label: "WORKOUTS")
        }
    }

    // MARK: EMOM

    private var emomControls: some View {
        VStack(spacing: LKSpacing.md) {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                LKSectionLabel(text: "TOTAL MINUTES")
                stepperRow(
                    value: $vm.emomMinutes, label: "min", min: 1, max: 60,
                    numberEntryTitle: "Minutes", numberEntryMessage: "Total EMOM duration",
                    minEntry: 1, maxEntry: 120
                )
            }
            sessionsList(cards: $vm.emomSessions, label: "WORKOUTS (cycle each minute)")
        }
    }

    // MARK: For Time

    private var forTimeControls: some View {
        VStack(spacing: LKSpacing.md) {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                LKSectionLabel(text: "TIME CAP")
                timePicker(minutes: $vm.timeLimitMinutes, seconds: $vm.timeLimitSeconds)
            }
            sessionsList(cards: $vm.sessions, label: "WORKOUTS")
        }
    }

    // MARK: Intervals

    private var intervalsControls: some View {
        VStack(spacing: LKSpacing.md) {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                LKSectionLabel(text: "INTERVALS")
                VStack(spacing: LKSpacing.sm) {
                    stepperRow(value: $vm.workSeconds,    label: "sec WORK",  min: 5,  max: 300, numberEntryTitle: "Work",   numberEntryMessage: "Work seconds", minEntry: 5,  maxEntry: 300)
                    stepperRow(value: $vm.restSeconds,    label: "sec REST",  min: 5,  max: 300, numberEntryTitle: "Rest",   numberEntryMessage: "Rest seconds",  minEntry: 5,  maxEntry: 300)
                    stepperRow(value: $vm.intervalRounds, label: "ROUNDS",    min: 1,  max: 50,  numberEntryTitle: "Rounds", numberEntryMessage: "Total rounds",  minEntry: 1,  maxEntry: 50)
                }
                .padding(LKSpacing.md)
                .background(LKColor.surface)
                .cornerRadius(LKRadius.large)
            }
            sessionsList(cards: $vm.intervalSessions, label: "WORKOUTS")
        }
    }

    // MARK: Reps

    private var repsControls: some View {
        VStack(spacing: LKSpacing.md) {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                LKSectionLabel(text: "REST BETWEEN SETS")
                stepperRow(value: $vm.restBetweenSets, label: "sec", min: 0, max: 300, numberEntryTitle: "Rest", numberEntryMessage: "Seconds between sets", minEntry: 0, maxEntry: 300)
            }
            exercisesList
        }
    }

    // MARK: Manual

    private var manualControls: some View {
        sessionsList(cards: $vm.manualSessions, label: "WORKOUTS")
    }

    // MARK: - Shared controls

    private func timePicker(minutes: Binding<Int>, seconds: Binding<Int>) -> some View {
        VStack(spacing: LKSpacing.sm) {
            HStack {
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Minutes", message: "Time limit minutes",
                        currentValue: Double(minutes.wrappedValue), minValue: 0, maxValue: 120
                    ) { minutes.wrappedValue = Int($0) }
                } label: {
                    Text("\(minutes.wrappedValue)")
                        .font(LKFont.numeric).foregroundColor(LKColor.accent)
                }
                Text("min").font(LKFont.body).foregroundColor(LKColor.textSecondary)
                Spacer()
                Stepper("", value: minutes, in: 0...120).labelsHidden()
            }
            HStack {
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Seconds", message: "Additional seconds (0–55)",
                        currentValue: Double(seconds.wrappedValue), minValue: 0, maxValue: 55
                    ) { seconds.wrappedValue = Int($0) }
                } label: {
                    Text("\(seconds.wrappedValue)")
                        .font(LKFont.numeric).foregroundColor(LKColor.accent)
                }
                Text("sec").font(LKFont.body).foregroundColor(LKColor.textSecondary)
                Spacer()
                Stepper("", value: seconds, in: 0...55, step: 5).labelsHidden()
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
    }

    private func stepperRow(
        value: Binding<Int>, label: String, min: Int, max: Int,
        numberEntryTitle: String, numberEntryMessage: String,
        minEntry: Double, maxEntry: Double
    ) -> some View {
        HStack {
            Button {
                numberEntry = NumberEntryItem(
                    title: numberEntryTitle, message: numberEntryMessage,
                    currentValue: Double(value.wrappedValue), minValue: minEntry, maxValue: maxEntry
                ) { value.wrappedValue = Int($0) }
            } label: {
                Text("\(value.wrappedValue)").font(LKFont.numeric).foregroundColor(LKColor.accent)
            }
            Text(label).font(LKFont.body).foregroundColor(LKColor.textSecondary)
            Spacer()
            HStack(spacing: LKSpacing.sm) {
                Button {
                    value.wrappedValue = Swift.max(min, value.wrappedValue - 1)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title2).foregroundColor(LKColor.textSecondary)
                }
                Button {
                    value.wrappedValue = Swift.min(max, value.wrappedValue + 1)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(LKColor.accent)
                }
            }
        }
    }

    // MARK: - Sessions list

    private func sessionsList(cards: Binding<[SessionCard]>, label: String) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            LKSectionLabel(text: label)
            ForEach(cards.indices, id: \.self) { i in
                SessionCardView(
                    card: cards[i],
                    canDelete: cards.wrappedValue.count > 1,
                    numberEntry: $numberEntry,
                    onDelete: { cards.wrappedValue.remove(at: i) }
                )
            }
            plainAddButton("Add Workout") {
                cards.wrappedValue.append(SessionCard())
            }
        }
    }

    // MARK: - Exercises list

    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            LKSectionLabel(text: "EXERCISES")
            ForEach($vm.exercises) { $card in
                ExerciseCardView(
                    card: $card,
                    canDelete: vm.exercises.count > 1,
                    numberEntry: $numberEntry,
                    context: context,
                    onDelete: { vm.exercises.removeAll { $0.id == card.id } }
                )
            }
            if vm.exercises.count < 20 {
                plainAddButton("Add Exercise") {
                    vm.exercises.append(ExerciseCard())
                }
            }
        }
    }

    private func plainAddButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LKSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(LKColor.accent)
                Text(label)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.accent)
            }
            .padding(.vertical, LKSpacing.xs)
        }
    }

    // MARK: - Save template sheet

    private var saveTemplateSheet: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.lg) {
                Text("Save as Template")
                    .font(LKFont.heading).foregroundColor(LKColor.textPrimary)

                VStack(alignment: .leading, spacing: LKSpacing.xs) {
                    TextField("Template name", text: $templateName)
                        .font(LKFont.body).foregroundColor(LKColor.textPrimary)
                        .padding(LKSpacing.md)
                        .background(LKColor.surface)
                        .cornerRadius(LKRadius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: LKRadius.medium)
                                .stroke(templateError.isEmpty ? Color.clear : LKColor.danger, lineWidth: 1)
                        )
                    if !templateError.isEmpty {
                        Text(templateError).font(LKFont.caption).foregroundColor(LKColor.danger)
                    }
                }
                .padding(.horizontal, LKSpacing.md)

                Button("Save") {
                    vm.selectedTimerType = type
                    if vm.saveAsTemplate(name: templateName, context: context) {
                        showSaveTemplate = false; templateName = ""; templateError = ""
                    } else {
                        templateError = vm.templateNameError
                    }
                }
                .buttonStyle(LKPrimaryButtonStyle())
                .padding(.horizontal, LKSpacing.md)

                Spacer()
            }
            .padding(.top, LKSpacing.lg)
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveTemplate = false; templateName = ""; templateError = ""
                    }
                    .foregroundColor(LKColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Session Card View
// Layout: name (full width) | two columns below: equipment left, reps+weight right

struct SessionCardView: View {
    @Binding var card: SessionCard
    let canDelete: Bool
    @Binding var numberEntry: NumberEntryItem?
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack {
                TextField("Workout name", text: $card.name)
                    .font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundColor(LKColor.danger)
                    }
                    .accessibilityLabel("Delete workout")
                }
            }

            HStack(alignment: .top, spacing: LKSpacing.md) {
                LKEquipmentMenu(
                    sfSymbol: card.equipment.sfSymbol,
                    label: card.equipment == .none ? "Equipment" : card.equipment.rawValue,
                    isPlaceholder: card.equipment == .none
                ) { card.equipment = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: LKSpacing.xs) {
                    LKCompactCounter(
                        value: $card.reps, min: 1, max: 100, label: "Reps",
                        numberEntry: $numberEntry,
                        entryTitle: "Reps", entryMessage: "Reps per round",
                        entryMin: 1, entryMax: 100
                    )
                    LKCompactWeightControls(
                        weight: $card.weight, unit: $card.weightUnit,
                        numberEntry: $numberEntry
                    )
                }
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .overlay(RoundedRectangle(cornerRadius: LKRadius.large).strokeBorder(LKColor.surfaceElevated, lineWidth: 1))
        .cornerRadius(LKRadius.large)
    }
}

// MARK: - Exercise Card View
// Layout: name (full width) | two columns: equipment left, sets+reps+weight right

struct ExerciseCardView: View {
    @Binding var card: ExerciseCard
    let canDelete: Bool
    @Binding var numberEntry: NumberEntryItem?
    let context: ModelContext
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack {
                TextField("Exercise name", text: $card.name)
                    .font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                    .onChange(of: card.name) { _, newName in
                        if newName.count >= 3 {
                            if let cached = WeightCache.shared.lookup(exerciseName: newName, in: context) {
                                if card.weight == 0 { card.weight = cached.weight }
                                if cached.equipment != nil && card.equipment == .none {
                                    card.equipment = cached.equipment ?? .none
                                }
                            }
                        }
                    }
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundColor(LKColor.danger)
                    }
                }
            }

            HStack(alignment: .top, spacing: LKSpacing.md) {
                LKEquipmentMenu(
                    sfSymbol: card.equipment.sfSymbol,
                    label: card.equipment == .none ? "Equipment" : card.equipment.rawValue,
                    isPlaceholder: card.equipment == .none
                ) { card.equipment = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: LKSpacing.xs) {
                    LKCompactCounter(
                        value: $card.sets, min: 1, max: 20, label: "Sets",
                        numberEntry: $numberEntry,
                        entryTitle: "Sets", entryMessage: "Number of sets",
                        entryMin: 1, entryMax: 20
                    )
                    LKCompactCounter(
                        value: $card.reps, min: 1, max: 100, label: "Reps",
                        numberEntry: $numberEntry,
                        entryTitle: "Reps", entryMessage: "Target reps per set",
                        entryMin: 1, entryMax: 100
                    )
                    LKCompactWeightControls(
                        weight: $card.weight, unit: $card.weightUnit,
                        numberEntry: $numberEntry
                    )
                }
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .overlay(RoundedRectangle(cornerRadius: LKRadius.large).strokeBorder(LKColor.surfaceElevated, lineWidth: 1))
        .cornerRadius(LKRadius.large)
    }
}

// MARK: - Reusable card components

struct LKEquipmentMenu: View {
    let sfSymbol: String
    let label: String
    let isPlaceholder: Bool
    let onSelect: (Equipment) -> Void

    var body: some View {
        Menu {
            ForEach(Equipment.allCases) { eq in
                Button { onSelect(eq) } label: {
                    Label(eq.rawValue, systemImage: eq.sfSymbol)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sfSymbol).font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(isPlaceholder ? LKColor.textMuted : LKColor.textSecondary)
            .padding(.horizontal, LKSpacing.xs + 2)
            .padding(.vertical, LKSpacing.xs)
            .background(LKColor.surfaceElevated)
            .cornerRadius(LKRadius.small)
        }
    }
}

// [−] [num] [+] Label — compact, no Spacers so buttons never overlap
struct LKCompactCounter: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let label: String
    @Binding var numberEntry: NumberEntryItem?
    let entryTitle: String
    let entryMessage: String
    let entryMin: Double
    let entryMax: Double

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Button {
                value = Swift.max(min, value - 1)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3).foregroundColor(LKColor.textSecondary)
            }

            Button {
                numberEntry = NumberEntryItem(
                    title: entryTitle, message: entryMessage,
                    currentValue: Double(value), minValue: entryMin, maxValue: entryMax
                ) { value = Int($0) }
            } label: {
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(LKColor.accent)
                    .frame(minWidth: 28, alignment: .center)
            }

            Button {
                value = Swift.min(max, value + 1)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3).foregroundColor(LKColor.accent)
            }

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LKColor.textSecondary)
        }
    }
}

// [−] [num] [+] [lb|kg] — all on one row, no Spacers
struct LKCompactWeightControls: View {
    @Binding var weight: Double
    @Binding var unit: WeightUnit
    @Binding var numberEntry: NumberEntryItem?

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Button {
                weight = max(0, weight - 5)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3).foregroundColor(LKColor.textSecondary)
            }

            Button {
                numberEntry = NumberEntryItem(
                    title: "Weight", message: "Enter weight (\(unit.rawValue))",
                    currentValue: weight, minValue: 0, maxValue: 999
                ) { weight = $0 }
            } label: {
                Text("\(Int(weight))")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(LKColor.accent)
                    .frame(minWidth: 28, alignment: .center)
            }

            Button {
                weight = min(999, weight + 5)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3).foregroundColor(LKColor.accent)
            }

            // lb / kg inline
            HStack(spacing: 0) {
                ForEach([WeightUnit.lb, WeightUnit.kg], id: \.self) { u in
                    Button {
                        unit = u
                        HapticManager.shared.buttonTap()
                    } label: {
                        Text(u.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 32)
                            .padding(.vertical, 5)
                            .background(unit == u ? LKColor.accent : Color.clear)
                            .foregroundColor(unit == u ? .black : LKColor.textMuted)
                    }
                }
            }
            .background(LKColor.surfaceElevated)
            .cornerRadius(LKRadius.small)
        }
    }
}
