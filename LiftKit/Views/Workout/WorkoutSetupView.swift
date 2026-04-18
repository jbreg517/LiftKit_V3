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

    let type: TimerType

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.lg) {
                    // Type header
                    typeHeader
                    // Name
                    nameSection
                    // Type-specific controls
                    typeControls
                    // Notes
                    notesSection
                    // Start button
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

    // MARK: - Notes
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            LKSectionLabel(text: "NOTES")
            TextField("Optional notes...", text: $vm.notes, axis: .vertical)
                .font(LKFont.body)
                .foregroundColor(LKColor.textPrimary)
                .lineLimit(3...6)
                .padding(LKSpacing.md)
                .background(LKColor.surface)
                .cornerRadius(LKRadius.medium)
        }
    }

    // MARK: - Start
    private var startButton: some View {
        Button {
            HapticManager.shared.buttonTap()
            vm.selectedTimerType = type
            vm.startTimedWorkout(context: context)
        } label: {
            Label("Start \(type.rawValue)", systemImage: "play.fill")
        }
        .buttonStyle(LKPrimaryButtonStyle())
    }

    // MARK: - Type-specific controls
    @ViewBuilder
    private var typeControls: some View {
        switch type {
        case .amrap:    amrapControls
        case .emom:     emomControls
        case .forTime:  forTimeControls
        case .intervals: intervalsControls
        case .reps:     repsControls
        case .manual:   manualControls
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
                    value: $vm.emomMinutes,
                    label: "min",
                    min: 1, max: 60,
                    numberEntryTitle: "Minutes",
                    numberEntryMessage: "Total EMOM duration",
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
                    stepperRow(value: $vm.workSeconds,    label: "sec WORK",   min: 5,  max: 300, numberEntryTitle: "Work",   numberEntryMessage: "Work seconds",  minEntry: 5, maxEntry: 300)
                    stepperRow(value: $vm.restSeconds,    label: "sec REST",   min: 5,  max: 300, numberEntryTitle: "Rest",   numberEntryMessage: "Rest seconds",  minEntry: 5, maxEntry: 300)
                    stepperRow(value: $vm.intervalRounds, label: "ROUNDS",     min: 1,  max: 50,  numberEntryTitle: "Rounds", numberEntryMessage: "Total rounds",  minEntry: 1, maxEntry: 50)
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

    // MARK: - Shared UI Components

    private func timePicker(minutes: Binding<Int>, seconds: Binding<Int>) -> some View {
        VStack(spacing: LKSpacing.sm) {
            // Minutes row
            HStack {
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Minutes",
                        message: "Time limit minutes",
                        currentValue: Double(minutes.wrappedValue),
                        minValue: 0, maxValue: 120
                    ) { minutes.wrappedValue = Int($0) }
                } label: {
                    Text("\(minutes.wrappedValue)")
                        .font(LKFont.numeric)
                        .foregroundColor(LKColor.accent)
                }
                Text("min")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                Spacer()
                Stepper("", value: minutes, in: 0...120)
                    .labelsHidden()
            }
            // Seconds row
            HStack {
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Seconds",
                        message: "Additional seconds (0–55)",
                        currentValue: Double(seconds.wrappedValue),
                        minValue: 0, maxValue: 55
                    ) { seconds.wrappedValue = Int($0) }
                } label: {
                    Text("\(seconds.wrappedValue)")
                        .font(LKFont.numeric)
                        .foregroundColor(LKColor.accent)
                }
                Text("sec")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                Spacer()
                Stepper("", value: seconds, in: 0...55, step: 5)
                    .labelsHidden()
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
    }

    private func stepperRow(
        value: Binding<Int>,
        label: String,
        min: Int, max: Int,
        numberEntryTitle: String,
        numberEntryMessage: String,
        minEntry: Double, maxEntry: Double
    ) -> some View {
        HStack {
            Button {
                numberEntry = NumberEntryItem(
                    title: numberEntryTitle,
                    message: numberEntryMessage,
                    currentValue: Double(value.wrappedValue),
                    minValue: minEntry, maxValue: maxEntry
                ) { value.wrappedValue = Int($0) }
            } label: {
                Text("\(value.wrappedValue)")
                    .font(LKFont.numeric)
                    .foregroundColor(LKColor.accent)
            }
            Text(label)
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
            Spacer()
            HStack(spacing: LKSpacing.sm) {
                Button {
                    value.wrappedValue = Swift.max(min, value.wrappedValue - 1)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(LKColor.textSecondary)
                }
                Button {
                    value.wrappedValue = Swift.min(max, value.wrappedValue + 1)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(LKColor.accent)
                }
            }
        }
    }

    // MARK: Sessions list
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
            dashedAddButton("+ Add Workout") {
                cards.wrappedValue.append(SessionCard())
            }
        }
    }

    // MARK: Exercises list
    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            LKSectionLabel(text: "EXERCISES")
            ForEach($vm.exercises) { $card in
                ExerciseCardView(
                    card: $card,
                    canDelete: vm.exercises.count > 1,
                    numberEntry: $numberEntry,
                    context: context,
                    onDelete: {
                        vm.exercises.removeAll { $0.id == card.id }
                    }
                )
            }
            if vm.exercises.count < 20 {
                dashedAddButton("+ Add Exercise") {
                    vm.exercises.append(ExerciseCard())
                }
            }
        }
    }

    private func dashedAddButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus")
                    .foregroundColor(LKColor.accent)
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(LKColor.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(LKSpacing.md)
            .background(LKColor.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.medium)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundColor(LKColor.textMuted.opacity(0.4))
            )
            .cornerRadius(LKRadius.medium)
        }
    }

    // MARK: - Save template sheet
    private var saveTemplateSheet: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.lg) {
                Text("Save as Template")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)

                VStack(alignment: .leading, spacing: LKSpacing.xs) {
                    TextField("Template name", text: $templateName)
                        .font(LKFont.body)
                        .foregroundColor(LKColor.textPrimary)
                        .padding(LKSpacing.md)
                        .background(LKColor.surface)
                        .cornerRadius(LKRadius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: LKRadius.medium)
                                .stroke(templateError.isEmpty ? Color.clear : LKColor.danger, lineWidth: 1)
                        )
                    if !templateError.isEmpty {
                        Text(templateError)
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.danger)
                    }
                }
                .padding(.horizontal, LKSpacing.md)

                Button("Save") {
                    vm.selectedTimerType = type
                    if vm.saveAsTemplate(name: templateName, context: context) {
                        showSaveTemplate = false
                        templateName = ""
                        templateError = ""
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
                        showSaveTemplate = false
                        templateName = ""
                        templateError = ""
                    }
                    .foregroundColor(LKColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Session Card View
struct SessionCardView: View {
    @Binding var card: SessionCard
    let canDelete: Bool
    @Binding var numberEntry: NumberEntryItem?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: LKSpacing.sm) {
            HStack {
                TextField("Workout name", text: $card.name)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(LKColor.danger)
                    }
                    .accessibilityLabel("Delete workout")
                }
            }

            HStack {
                Menu {
                    ForEach(Equipment.allCases) { eq in
                        Button {
                            card.equipment = eq
                        } label: {
                            Label(eq.rawValue, systemImage: eq.sfSymbol)
                        }
                    }
                } label: {
                    HStack(spacing: LKSpacing.xs) {
                        Image(systemName: card.equipment.sfSymbol)
                        Text(card.equipment == .none ? "Equipment" : card.equipment.rawValue)
                    }
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                }
                Spacer()
                weightChip(weight: $card.weight, unit: card.weightUnit)
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .overlay(RoundedRectangle(cornerRadius: LKRadius.large).strokeBorder(LKColor.surfaceElevated, lineWidth: 1))
        .cornerRadius(LKRadius.large)
    }

    private func weightChip(weight: Binding<Double>, unit: WeightUnit) -> some View {
        HStack(spacing: LKSpacing.sm) {
            Button {
                weight.wrappedValue = max(0, weight.wrappedValue - 5)
                HapticManager.shared.buttonTap()
            } label: { Text("−5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }

            Button {
                numberEntry = NumberEntryItem(
                    title: "Weight", message: "Enter weight (\(unit.rawValue))",
                    currentValue: weight.wrappedValue, minValue: 0, maxValue: 999
                ) { weight.wrappedValue = $0 }
            } label: {
                Text("\(Int(weight.wrappedValue)) \(unit.rawValue)")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.accent)
                    .underline()
            }

            Button {
                weight.wrappedValue = min(999, weight.wrappedValue + 5)
                HapticManager.shared.buttonTap()
            } label: { Text("+5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }
        }
        .padding(.horizontal, LKSpacing.sm)
        .padding(.vertical, LKSpacing.xs)
        .background(LKColor.surfaceElevated)
        .clipShape(Capsule())
    }
}

// MARK: - Exercise Card View (Reps setup)
struct ExerciseCardView: View {
    @Binding var card: ExerciseCard
    let canDelete: Bool
    @Binding var numberEntry: NumberEntryItem?
    let context: ModelContext
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: LKSpacing.sm) {
            HStack {
                TextField("Exercise name", text: $card.name)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
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

            HStack {
                Menu {
                    ForEach(Equipment.allCases) { eq in
                        Button {
                            card.equipment = eq
                        } label: {
                            Label(eq.rawValue, systemImage: eq.sfSymbol)
                        }
                    }
                } label: {
                    HStack(spacing: LKSpacing.xs) {
                        Image(systemName: card.equipment.sfSymbol)
                        Text(card.equipment == .none ? "Equipment" : card.equipment.rawValue)
                    }
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                }
                Spacer()
                weightChip
            }

            Divider().background(LKColor.surfaceElevated)

            HStack {
                Text("Sets")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                Spacer()
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Sets", message: "Number of sets",
                        currentValue: Double(card.sets), minValue: 1, maxValue: 20
                    ) { card.sets = Int($0) }
                } label: {
                    Text("\(card.sets)")
                        .font(LKFont.numeric)
                        .foregroundColor(LKColor.accent)
                }
                HStack(spacing: LKSpacing.sm) {
                    Button { card.sets = max(1, card.sets - 1) } label: {
                        Image(systemName: "minus.circle.fill").foregroundColor(LKColor.textSecondary)
                    }
                    Button { card.sets = min(20, card.sets + 1) } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(LKColor.accent)
                    }
                }
            }

            HStack {
                Text("Reps")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                Spacer()
                Button {
                    numberEntry = NumberEntryItem(
                        title: "Reps", message: "Target reps per set",
                        currentValue: Double(card.reps), minValue: 1, maxValue: 100
                    ) { card.reps = Int($0) }
                } label: {
                    Text("\(card.reps)")
                        .font(LKFont.numeric)
                        .foregroundColor(LKColor.accent)
                }
                HStack(spacing: LKSpacing.sm) {
                    Button { card.reps = max(1, card.reps - 1) } label: {
                        Image(systemName: "minus.circle.fill").foregroundColor(LKColor.textSecondary)
                    }
                    Button { card.reps = min(100, card.reps + 1) } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(LKColor.accent)
                    }
                }
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .overlay(RoundedRectangle(cornerRadius: LKRadius.large).strokeBorder(LKColor.surfaceElevated, lineWidth: 1))
        .cornerRadius(LKRadius.large)
    }

    private var weightChip: some View {
        HStack(spacing: LKSpacing.sm) {
            Button { card.weight = max(0, card.weight - 5); HapticManager.shared.buttonTap() }
            label: { Text("−5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }

            Button {
                numberEntry = NumberEntryItem(
                    title: "Weight", message: "Enter weight (\(card.weightUnit.rawValue))",
                    currentValue: card.weight, minValue: 0, maxValue: 999
                ) { card.weight = $0 }
            } label: {
                Text("\(Int(card.weight)) \(card.weightUnit.rawValue)")
                    .font(LKFont.caption).foregroundColor(LKColor.accent).underline()
            }

            Button { card.weight = min(999, card.weight + 5); HapticManager.shared.buttonTap() }
            label: { Text("+5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }
        }
        .padding(.horizontal, LKSpacing.sm)
        .padding(.vertical, LKSpacing.xs)
        .background(LKColor.surfaceElevated)
        .clipShape(Capsule())
    }
}
