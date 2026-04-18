import SwiftUI
import SwiftData

// MARK: - Active Workout View
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    @State private var engine = TimerEngine(notificationPrefix: "main")
    @State private var restEngine = TimerEngine(notificationPrefix: "rest")
    @State private var showEndDialog = false
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var templateError = ""
    @State private var soundOn = true
    @State private var numberEntry: NumberEntryItem?
    @State private var showInitialCountdown = true
    @State private var initialCountdown = 10

    private var type: TimerType { vm.activeConfig.type }

    var body: some View {
        ZStack {
            // Background
            backgroundColour.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar area
                navBar

                // Content
                Group {
                    switch type {
                    case .amrap:     amrapContent
                    case .emom:      emomContent
                    case .forTime:   forTimeContent
                    case .intervals: intervalsContent
                    case .reps:      repsContent
                    case .manual:    manualContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Initial countdown overlay
            if showInitialCountdown && type.hasInitialCountdown {
                initialCountdownOverlay
            }

            // Completion overlay
            if vm.isShowingComplete {
                WorkoutCompleteOverlay(vm: vm, engine: engine, rounds: vm.completedRounds)
            }

            // PR Banner
            if vm.showPRBanner {
                prBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .onAppear {
            soundOn = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
            if type.hasInitialCountdown {
                startInitialCountdown()
            } else {
                startMainTimer()
            }
        }
        .onDisappear {
            engine.stop()
            restEngine.stop()
        }
        .sheet(item: $numberEntry) { item in
            NumberEntrySheet(item: item)
                .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showSaveTemplate) { saveTemplateSheet }
        .confirmationDialog("End Workout?", isPresented: $showEndDialog, titleVisibility: .visible) {
            Button("Save & End")  { vm.endWorkout(context: context) }
            Button("Discard", role: .destructive) { vm.discardWorkout(context: context) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Background
    private var backgroundColour: Color {
        if type == .forTime && engine.elapsedTime > Double(vm.activeConfig.totalDuration) {
            return LKColor.danger.opacity(0.15)
        }
        if engine.phase == .rest || restEngine.phase == .rest {
            return LKColor.rest.opacity(0.10)
        }
        return LKColor.background
    }

    // MARK: - Nav Bar
    private var navBar: some View {
        HStack {
            Button("End") {
                showEndDialog = true
                HapticManager.shared.buttonTap()
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(LKColor.danger)

            Spacer()

            Text(navTitle)
                .font(.headline)
                .foregroundColor(LKColor.textPrimary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: LKSpacing.md) {
                Button {
                    showSaveTemplate = true
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(LKColor.textSecondary)
                }

                Button {
                    soundOn.toggle()
                    UserDefaults.standard.set(soundOn, forKey: "soundEnabled")
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(LKColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, LKSpacing.md)
        .padding(.vertical, LKSpacing.sm)
    }

    private var navTitle: String {
        if vm.activeSessionCards.indices.contains(vm.currentSessionIndex) {
            let name = vm.activeSessionCards[vm.currentSessionIndex].name
            return name.isEmpty ? type.rawValue : name
        }
        return type.rawValue
    }

    // MARK: - Timer Controls
    private func timerControls(engine: TimerEngine) -> some View {
        HStack(spacing: LKSpacing.xl) {
            // Skip
            Button { engine.skip(); HapticManager.shared.buttonTap() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(LKColor.textSecondary)
                    .frame(width: 60, height: 60)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Skip")

            // Pause / Resume
            Button {
                if engine.isRunning { engine.pause() } else { engine.resume() }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundColor(LKColor.background)
                    .frame(width: 88, height: 88)
                    .background(LKColor.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel(engine.isRunning ? "Pause" : "Resume")

            // Stop
            Button {
                vm.completeWorkout(context: context)
                engine.stop()
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundColor(LKColor.danger)
                    .frame(width: 60, height: 60)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop")
        }
    }

    // MARK: - Hero timer
    private func heroTimer(text: String, color: Color = LKColor.textPrimary) -> some View {
        Text(text)
            .font(LKFont.timer(112))
            .foregroundColor(color)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    // MARK: - Phase label
    private func phaseLabel(_ engine: TimerEngine) -> some View {
        Text(engine.phase.label)
            .font(LKFont.phase)
            .foregroundColor(engine.phase.color)
            .tracking(4)
            .textCase(.uppercase)
    }

    // MARK: - Weight chip (active)
    private func activeWeightChip(sessionIndex: Int) -> some View {
        let card = vm.activeSessionCards.indices.contains(sessionIndex)
            ? vm.activeSessionCards[sessionIndex]
            : SessionCard()
        return HStack(spacing: LKSpacing.sm) {
            if card.equipment != .none {
                Label(card.equipment.rawValue, systemImage: card.equipment.sfSymbol)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                    .padding(.horizontal, LKSpacing.sm)
                    .padding(.vertical, LKSpacing.xs)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Capsule())
            }
            HStack(spacing: LKSpacing.sm) {
                Button {
                    vm.adjustSessionWeight(sessionIndex: sessionIndex, delta: -5)
                    HapticManager.shared.buttonTap()
                } label: { Text("−5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }

                Button {
                    numberEntry = NumberEntryItem(
                        title: "Weight", message: "Enter weight",
                        currentValue: card.weight, minValue: 0, maxValue: 999
                    ) { vm.activeSessionCards[sessionIndex].weight = $0 }
                } label: {
                    Text("\(Int(card.weight)) \(card.weightUnit.rawValue)")
                        .font(LKFont.caption).foregroundColor(LKColor.accent).underline()
                }

                Button {
                    vm.adjustSessionWeight(sessionIndex: sessionIndex, delta: 5)
                    HapticManager.shared.buttonTap()
                } label: { Text("+5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }
            }
            .padding(.horizontal, LKSpacing.sm)
            .padding(.vertical, LKSpacing.xs)
            .background(LKColor.surfaceElevated)
            .clipShape(Capsule())
        }
    }

    // MARK: - Notes display
    private func notesDisplay() -> some View {
        Group {
            if let notes = vm.activeSession?.notes, !notes.isEmpty {
                Text(notes)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(LKSpacing.sm)
                    .background(LKColor.surface)
                    .cornerRadius(LKRadius.small)
                    .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    // MARK: - Multi-session indicator
    private func multiSessionIndicator() -> some View {
        Group {
            if vm.activeSessionCards.count > 1 {
                Text("Workout \(vm.currentSessionIndex + 1) of \(vm.activeSessionCards.count)")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
            }
        }
    }

    // MARK: - Initial countdown overlay
    private var initialCountdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: LKSpacing.lg) {
                Text("Starting in")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textSecondary)
                Text("\(initialCountdown)")
                    .font(LKFont.timer(120))
                    .foregroundColor(LKColor.accent)
                    .contentTransition(.numericText())
            }
        }
        .transition(.opacity)
    }

    // MARK: - PR Banner
    private var prBanner: some View {
        VStack {
            HStack(spacing: LKSpacing.sm) {
                Image(systemName: "trophy.fill").foregroundColor(.yellow)
                Text(vm.prBannerMessage)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Image(systemName: "trophy.fill").foregroundColor(.yellow)
            }
            .padding(LKSpacing.md)
            .background(.ultraThickMaterial)
            .cornerRadius(LKRadius.large)
            .shadow(radius: 8)
            .padding(.horizontal, LKSpacing.md)
            Spacer()
        }
        .padding(.top, LKSpacing.lg)
    }

    // MARK: - Save template sheet
    private var saveTemplateSheet: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.lg) {
                Text("Save as Template")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                VStack(alignment: .leading) {
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
            .padding(.top, LKSpacing.xl)
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveTemplate = false }
                        .foregroundColor(LKColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Start helpers
    private func startInitialCountdown() {
        initialCountdown = 10
        showInitialCountdown = true
        var count = 10
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            count -= 1
            withAnimation { initialCountdown = count }
            if count <= 0 {
                t.invalidate()
                withAnimation { showInitialCountdown = false }
                startMainTimer()
            }
        }
    }

    private func startMainTimer() {
        engine.start(config: vm.activeConfig)
        engine.onComplete = {
            DispatchQueue.main.async {
                vm.completeWorkout(context: context)
            }
        }
    }

    // MARK: ============================================================
    // MARK: TYPE-SPECIFIC CONTENT
    // MARK: ============================================================

    // MARK: - AMRAP
    private var amrapContent: some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            multiSessionIndicator()
            phaseLabel(engine)
            heroTimer(text: engine.formattedTime)
                .padding(.vertical, LKSpacing.sm)
            activeWeightChip(sessionIndex: vm.currentSessionIndex)
            // Rounds counter
            VStack(spacing: LKSpacing.xs) {
                Text("ROUNDS COMPLETED")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .tracking(1)
                HStack(spacing: LKSpacing.xl) {
                    Button {
                        vm.completedRounds = max(0, vm.completedRounds - 1)
                        HapticManager.shared.buttonTap()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title)
                            .foregroundColor(LKColor.textSecondary)
                    }
                    Button {
                        numberEntry = NumberEntryItem(
                            title: "Rounds Completed",
                            message: "Enter rounds completed",
                            currentValue: Double(vm.completedRounds),
                            minValue: 0, maxValue: 999
                        ) { vm.completedRounds = Int($0) }
                    } label: {
                        Text("\(vm.completedRounds)")
                            .font(LKFont.timer(56))
                            .foregroundColor(LKColor.accent)
                            .contentTransition(.numericText())
                    }
                    Button {
                        vm.completedRounds += 1
                        HapticManager.shared.buttonTap()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(LKColor.accent)
                    }
                }
            }
            timerControls(engine: engine)
            notesDisplay()
            Spacer()
        }
    }

    // MARK: - EMOM
    private var emomContent: some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            let sessionIdx = (engine.currentRound - 1) % max(1, vm.activeSessionCards.count)
            let sessionName = vm.activeSessionCards.indices.contains(sessionIdx)
                ? vm.activeSessionCards[sessionIdx].name
                : ""
            Text(sessionName.isEmpty ? "Workout \(sessionIdx + 1)" : sessionName)
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            phaseLabel(engine)
            heroTimer(text: engine.formattedTime)
            Text("Minute \(engine.currentRound) of \(engine.totalRounds)")
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
            activeWeightChip(sessionIndex: sessionIdx)
            timerControls(engine: engine)
            // Up Next
            if vm.activeSessionCards.count > 1 {
                let nextIdx = engine.currentRound % max(1, vm.activeSessionCards.count)
                if vm.activeSessionCards.indices.contains(nextIdx) {
                    VStack(spacing: LKSpacing.xs) {
                        Text("UP NEXT")
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.textMuted)
                            .tracking(1)
                        let nextName = vm.activeSessionCards[nextIdx].name
                        Text(nextName.isEmpty ? "Workout \(nextIdx + 1)" : nextName)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textSecondary)
                    }
                }
            }
            notesDisplay()
            Spacer()
        }
    }

    // MARK: - For Time
    private var forTimeContent: some View {
        let isOverCap = engine.elapsedTime > vm.activeConfig.totalDuration
        return VStack(spacing: LKSpacing.lg) {
            Spacer()
            multiSessionIndicator()
            if isOverCap {
                Text("TIME CAP")
                    .font(LKFont.phase)
                    .foregroundColor(LKColor.danger)
                    .tracking(4)
            } else {
                phaseLabel(engine)
            }
            heroTimer(text: engine.formattedTime, color: isOverCap ? LKColor.danger : LKColor.textPrimary)
            Text("Cap: \(TimerEngine.format(vm.activeConfig.totalDuration))")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
            activeWeightChip(sessionIndex: vm.currentSessionIndex)
            // Mark Complete
            Button {
                let nextIdx = vm.currentSessionIndex + 1
                if nextIdx < vm.activeSessionCards.count {
                    vm.currentSessionIndex = nextIdx
                } else {
                    vm.completeWorkout(context: context)
                    engine.stop()
                }
                HapticManager.shared.buttonTap()
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(LKFont.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(LKSpacing.md)
                    .background(LKColor.work)
                    .cornerRadius(LKRadius.medium)
            }
            .padding(.horizontal, LKSpacing.md)
            timerControls(engine: engine)
            notesDisplay()
            Spacer()
        }
    }

    // MARK: - Intervals
    private var intervalsContent: some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            multiSessionIndicator()
            phaseLabel(engine)
            heroTimer(text: engine.formattedTime)
            Text("Round \(engine.currentRound) of \(engine.totalRounds)")
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
            activeWeightChip(sessionIndex: vm.currentSessionIndex)
            timerControls(engine: engine)
            notesDisplay()
            Spacer()
        }
    }

    // MARK: - Reps
    private var repsContent: some View {
        VStack(spacing: 0) {
            // Rest banner
            if restEngine.phase == .rest || restEngine.phase == .work {
                restBanner
            }
            // Exercise list
            ScrollView {
                VStack(spacing: LKSpacing.md) {
                    ForEach(Array(vm.activeExercises.enumerated()), id: \.element.id) { (exIdx, ex) in
                        exerciseCard(exIdx: exIdx, ex: ex)
                    }
                }
                .padding(LKSpacing.md)
            }
        }
    }

    private var restBanner: some View {
        VStack(spacing: LKSpacing.xs) {
            HStack {
                Text(restEngine.phase == .rest ? "REST" : "GO")
                    .font(LKFont.phase)
                    .foregroundColor(restEngine.phase == .rest ? LKColor.rest : LKColor.work)
                    .tracking(4)
                Spacer()
                Button("Skip") {
                    restEngine.skipRestTimer()
                    HapticManager.shared.buttonTap()
                }
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.accent)
            }
            Text(restEngine.formattedTime)
                .font(LKFont.timer(48))
                .foregroundColor(restEngine.phase == .rest ? LKColor.textPrimary : LKColor.work)
                .contentTransition(.numericText())
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
    }

    private func exerciseCard(exIdx: Int, ex: ActiveExercise) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            HStack {
                Text(ex.name)
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                Spacer()
                // Equipment + weight chip
                HStack(spacing: LKSpacing.sm) {
                    if ex.equipment != .none {
                        Label(ex.equipment.rawValue, systemImage: ex.equipment.sfSymbol)
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.textSecondary)
                            .padding(.horizontal, LKSpacing.sm)
                            .padding(.vertical, LKSpacing.xs)
                            .background(LKColor.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: LKSpacing.sm) {
                        Button {
                            vm.adjustWeight(exerciseIndex: exIdx, delta: -5)
                            HapticManager.shared.buttonTap()
                        } label: { Text("−5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }

                        Button {
                            numberEntry = NumberEntryItem(
                                title: "Weight", message: "Enter weight",
                                currentValue: ex.weight, minValue: 0, maxValue: 999
                            ) { vm.activeExercises[exIdx].weight = $0 }
                        } label: {
                            Text("\(Int(ex.weight)) \(ex.weightUnit.rawValue)")
                                .font(LKFont.caption).foregroundColor(LKColor.accent).underline()
                        }

                        Button {
                            vm.adjustWeight(exerciseIndex: exIdx, delta: 5)
                            HapticManager.shared.buttonTap()
                        } label: { Text("+5").font(LKFont.caption).foregroundColor(LKColor.textSecondary) }
                    }
                    .padding(.horizontal, LKSpacing.sm)
                    .padding(.vertical, LKSpacing.xs)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Capsule())
                }
            }

            // Set circles
            HStack(spacing: LKSpacing.sm) {
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { (setIdx, set) in
                    setCircle(exIdx: exIdx, setIdx: setIdx, set: set)
                }
            }
        }
        .lkCard()
    }

    private func setCircle(exIdx: Int, setIdx: Int, set: ActiveSet) -> some View {
        Button {
            if set.isCompleted {
                // Tap completed → adjust reps
                numberEntry = NumberEntryItem(
                    title: "Adjust Reps",
                    message: "Set \(set.setNumber) reps (0 = incomplete)",
                    currentValue: Double(set.actualReps),
                    minValue: 0, maxValue: 100
                ) { vm.adjustReps(exerciseIndex: exIdx, setIndex: setIdx, newReps: Int($0)) }
            } else {
                // Mark complete, start rest timer
                vm.logSet(exerciseIndex: exIdx, setIndex: setIdx, context: context)
                let rest = Double(vm.activeConfig.restBetweenSets)
                if rest > 0 {
                    restEngine.startRestTimer(rest)
                }
                HapticManager.shared.setLogged()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(set.isCompleted ? LKColor.success : LKColor.surfaceElevated)
                    .frame(width: 48, height: 48)
                Text("\(set.actualReps)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(set.isCompleted ? .white : LKColor.textPrimary)
            }
        }
        .accessibilityLabel("Set \(set.setNumber), \(set.actualReps) reps, \(set.isCompleted ? "completed" : "incomplete")")
    }

    // MARK: - Manual
    private var manualContent: some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            let sessionName = vm.activeSessionCards.first?.name ?? ""
            if !sessionName.isEmpty {
                Text(sessionName)
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
            }
            heroTimer(text: engine.formattedTime)
            activeWeightChip(sessionIndex: 0)
            // Large play/pause
            Button {
                if engine.isRunning { engine.pause() } else { engine.resume() }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundColor(LKColor.background)
                    .frame(width: 88, height: 88)
                    .background(LKColor.accent)
                    .clipShape(Circle())
            }
            // Next session button
            if vm.activeSessionCards.count > 1 && vm.currentSessionIndex + 1 < vm.activeSessionCards.count {
                Button {
                    vm.currentSessionIndex += 1
                    HapticManager.shared.buttonTap()
                } label: {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("Next")
                    }
                    .foregroundColor(LKColor.textSecondary)
                    .frame(width: 60, height: 60)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
                }
            }
            Spacer()
        }
    }
}

// MARK: - Workout Complete Overlay
struct WorkoutCompleteOverlay: View {
    @Bindable var vm: WorkoutViewModel
    let engine: TimerEngine
    let rounds: Int
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { vm.endWorkout(context: context) }

            VStack(spacing: LKSpacing.lg) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundColor(LKColor.accent)

                Text("Workout Complete!")
                    .font(LKFont.title)
                    .foregroundColor(LKColor.textPrimary)

                if vm.activeConfig.type == .amrap {
                    Text("\(rounds) rounds")
                        .font(LKFont.heading)
                        .foregroundColor(LKColor.accent)
                }

                Text(vm.completionMessage)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LKSpacing.xl)

                Button("End Workout") {
                    vm.endWorkout(context: context)
                }
                .buttonStyle(LKPrimaryButtonStyle())
                .padding(.horizontal, LKSpacing.xl)

                Button("Go Back") {
                    vm.isShowingComplete = false
                }
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)

                Text("Tap anywhere to dismiss")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
            }
            .padding(LKSpacing.xl)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(LKSpacing.lg)
        }
        .transition(.opacity)
    }
}
