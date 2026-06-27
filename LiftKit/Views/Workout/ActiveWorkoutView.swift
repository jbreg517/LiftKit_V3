import SwiftUI
import SwiftData

// Identifies the currently-running timed set within the active exercise list.
struct TimedSetKey: Equatable {
    let exIdx: Int
    let setIdx: Int
}

// MARK: - Active Workout View
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel
    @AppStorage("weightIncrement") private var weightIncrement: Double = 5

    @State private var engine = TimerEngine(notificationPrefix: "main")
    @State private var restEngine = TimerEngine(notificationPrefix: "rest")
    @State private var showEndDialog = false
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var templateError = ""
    @State private var soundOn = true
    @State private var numberEntry: NumberEntryItem?
    @State private var plateTarget: PlateTarget?
    @State private var warmupTarget: PlateTarget?
    @State private var editingSet: SetEditTarget?
    @State private var showInitialCountdown = true
    @State private var initialCountdown = 10
    @State private var countdownTimer: Timer?

    // Per-set hold timer (timed exercises, e.g. planks)
    @State private var timedSet: TimedSetKey?
    @State private var timedRemaining = 0
    @State private var timedSetTimer: Timer?

    // Reps: total-workout count-up (the main engine stays idle for reps).
    // Anchored to a start date so it stays correct across backgrounding.
    @State private var repsStart: Date?
    @State private var repsElapsed: TimeInterval = 0
    @State private var repsTimer: Timer?

    private var type: TimerType { vm.activeConfig.type }

    // Landscape on iPhone reports a compact height. iPad stays .regular, so the
    // condensed "big timer / small controls" layout only kicks in on phones.
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isLandscapePhone: Bool { vSizeClass == .compact }
    private var stackSpacing: CGFloat { isLandscapePhone ? LKSpacing.sm : LKSpacing.lg }

    var body: some View {
        ZStack {
            // Background
            backgroundColour.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar area
                navBar

                // Content
                Group {
                    if type == .reps {
                        repsContent   // already its own ScrollView
                    } else {
                        // Timer-centric screens center when they fit and scroll
                        // only if a short landscape height can't show everything,
                        // so nothing ever clips.
                        GeometryReader { geo in
                            ScrollView {
                                timerCentricContent
                                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
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
            if type == .reps { startRepsTimer() }
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
            timedSetTimer?.invalidate()
            timedSetTimer = nil
            repsTimer?.invalidate()
            repsTimer = nil
            engine.stop()
            restEngine.stop()
            LiveActivityManager.shared.stop()
        }
        .sheet(item: $numberEntry) { item in
            NumberEntrySheet(item: item)
                .presentationDetents([.height(280)])
        }
        .sheet(item: $plateTarget) { PlateCalculatorView(target: $0) }
        .sheet(item: $warmupTarget) { WarmupView(target: $0) }
        .sheet(item: $editingSet) { t in
            if t.exIdx < vm.activeExercises.count, t.setIdx < vm.activeExercises[t.exIdx].sets.count {
                let s = vm.activeExercises[t.exIdx].sets[t.setIdx]
                SetEditSheet(
                    isTimed: s.isTimed,
                    setNumber: s.setNumber,
                    value: s.isTimed ? s.actualDuration : s.actualReps,
                    rpe: s.rpe,
                    setType: s.setType
                ) { value, rpe, type in
                    vm.updateSet(exerciseIndex: t.exIdx, setIndex: t.setIdx,
                                 repsOrDuration: value, rpe: rpe, setType: type, context: context)
                }
            }
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
            return name.isEmpty ? type.displayName : name
        }
        return type.displayName
    }

    // MARK: - Timer Controls
    private func timerControls(engine: TimerEngine) -> some View {
        // In landscape (compact height) the controls shrink so the timer can dominate.
        let mainSize: CGFloat = isLandscapePhone ? 60 : 88
        let sideSize: CGFloat = isLandscapePhone ? 44 : 60
        return HStack(spacing: isLandscapePhone ? LKSpacing.lg : LKSpacing.xl) {
            // Skip
            Button { engine.skip(); HapticManager.shared.buttonTap() } label: {
                Image(systemName: "forward.fill")
                    .font(isLandscapePhone ? .body : .title2)
                    .foregroundColor(LKColor.textSecondary)
                    .frame(width: sideSize, height: sideSize)
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
                    .font(isLandscapePhone ? .title2 : .title)
                    .foregroundColor(LKColor.onAccent)
                    .frame(width: mainSize, height: mainSize)
                    .background(LKColor.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel(engine.isRunning ? "Pause" : "Resume")

            // Stop
            Button {
                showEndDialog = true
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "stop.fill")
                    .font(isLandscapePhone ? .body : .title2)
                    .foregroundColor(LKColor.danger)
                    .frame(width: sideSize, height: sideSize)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop")
        }
    }

    // MARK: - Hero timer
    private func heroTimer(text: String, color: Color = LKColor.textPrimary) -> some View {
        // Landscape uses the extra width for a much larger readable timer.
        Text(text)
            .font(LKFont.timer(isLandscapePhone ? 150 : 112))
            .foregroundColor(color)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
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
            // Hidden in landscape focus mode to keep the timer dominant.
            if !isLandscapePhone, let notes = vm.activeSession?.notes, !notes.isEmpty {
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
            if !isLandscapePhone, vm.activeSessionCards.count > 1 {
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
                Button("Cancel") {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    engine.stop()
                    restEngine.stop()
                    vm.discardWorkout(context: context)
                }
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.danger)
                .padding(.top, LKSpacing.md)
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
                    if vm.saveAsTemplate(name: templateName, context: context) != nil {
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

    // MARK: - Live Activity helpers

    private func liveActivityPhaseLabel(engine: TimerEngine) -> String {
        switch type {
        case .emom:      return "Minute \(engine.currentRound)"
        case .intervals: return engine.phase == .work ? "Work" : "Rest"
        default:         return type.rawValue
        }
    }

    // MARK: - Start helpers

    /// Total-workout count-up for the reps screen. Recomputes from a fixed start
    /// date each tick, so it stays accurate even if the app was backgrounded.
    private func startRepsTimer() {
        let start = repsStart ?? Date()
        repsStart = start
        repsElapsed = Date().timeIntervalSince(start)
        repsTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            if let s = repsStart { repsElapsed = Date().timeIntervalSince(s) }
        }
        repsTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func startInitialCountdown() {
        initialCountdown = 10
        showInitialCountdown = true
        var count = 10
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            count -= 1
            withAnimation { initialCountdown = count }
            if count <= 0 {
                timer.invalidate()
                countdownTimer = nil
                withAnimation { showInitialCountdown = false }
                startMainTimer()
            }
        }
        countdownTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func startMainTimer() {
        engine.start(config: vm.activeConfig)
        engine.onComplete = {
            DispatchQueue.main.async {
                vm.completeWorkout(context: context)
                LiveActivityManager.shared.stop()
            }
        }
        // Update the live activity whenever the timer phase changes
        let workoutType = type
        engine.onPhaseChange = { [engine] _ in
            DispatchQueue.main.async {
                let label: String
                switch workoutType {
                case .emom:      label = "Minute \(engine.currentRound)"
                case .intervals: label = engine.phase == .work ? "Work" : "Rest"
                default:         label = workoutType.rawValue
                }
                LiveActivityManager.shared.update(
                    currentRound: engine.currentRound,
                    totalRounds: engine.totalRounds,
                    phaseLabel: label,
                    phaseEndDate: engine.phaseEndDate
                )
            }
        }
        // Start the Live Activity (lock screen + Dynamic Island)
        LiveActivityManager.shared.start(
            workoutName: vm.activeSession?.name ?? type.rawValue,
            workoutType: type.rawValue,
            currentRound: engine.currentRound,
            totalRounds: engine.totalRounds,
            phaseLabel: liveActivityPhaseLabel(engine: engine),
            phaseEndDate: engine.phaseEndDate
        )
    }

    // MARK: ============================================================
    // MARK: TYPE-SPECIFIC CONTENT
    // MARK: ============================================================

    // All timer-centric screens (everything except .reps, which is its own list).
    @ViewBuilder
    private var timerCentricContent: some View {
        switch type {
        case .amrap:     amrapContent
        case .emom:      emomContent
        case .forTime:   forTimeContent
        case .intervals: intervalsContent
        case .manual:    manualContent
        case .reps:      EmptyView()   // handled separately in body
        }
    }

    // MARK: - AMRAP
    private var amrapContent: some View {
        VStack(spacing: stackSpacing) {
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
                        // Record the split (elapsed = total − remaining) for this round.
                        vm.recordSplit(vm.activeConfig.totalDuration - engine.timeRemaining, context: context)
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
        VStack(spacing: stackSpacing) {
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
        return VStack(spacing: stackSpacing) {
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
                vm.recordSplit(engine.elapsedTime, context: context)
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
        VStack(spacing: stackSpacing) {
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
            // Total workout time
            repsTimerHeader
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

                    Button {
                        vm.completeWorkout(context: context)
                        HapticManager.shared.buttonTap()
                    } label: {
                        Label(vm.activeRepsAllComplete ? "Finish Workout" : "Finish Early",
                              systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(LKPrimaryButtonStyle())
                    .padding(.top, LKSpacing.sm)
                }
                .padding(LKSpacing.md)
            }
        }
    }

    private var repsTimerHeader: some View {
        HStack(spacing: LKSpacing.sm) {
            Image(systemName: "stopwatch")
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textSecondary)
            Text("ELAPSED")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(1)
            Text(TimerEngine.format(repsElapsed))
                .font(LKFont.numeric)
                .foregroundColor(LKColor.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LKSpacing.sm)
        .background(LKColor.surface)
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
            HStack(spacing: LKSpacing.md) {
                restAdjustButton(label: "−15", delta: -15)
                Text(restEngine.formattedTime)
                    .font(LKFont.timer(48))
                    .foregroundColor(restEngine.phase == .rest ? LKColor.textPrimary : LKColor.work)
                    .contentTransition(.numericText())
                    .frame(minWidth: 110)
                restAdjustButton(label: "+15", delta: 15)
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
    }

    private func restAdjustButton(label: String, delta: TimeInterval) -> some View {
        Button {
            restEngine.adjustRest(by: delta)
            HapticManager.shared.buttonTap()
        } label: {
            Text(label)
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textSecondary)
                .frame(width: 52, height: 40)
                .background(LKColor.surfaceElevated)
                .clipShape(Capsule())
        }
        .accessibilityLabel(delta < 0 ? "Subtract 15 seconds" : "Add 15 seconds")
    }

    private func exerciseCard(exIdx: Int, ex: ActiveExercise) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LKSpacing.xs) {
                    Text(ex.name)
                        .font(LKFont.heading)
                        .foregroundColor(LKColor.textPrimary)
                    if ex.supersetGroup != nil {
                        Label("SUPERSET", systemImage: "link")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(LKColor.accent)
                            .tracking(1)
                    }
                }
                Spacer()
                weightControls(exIdx: exIdx, ex: ex)
            }

            // Plates / warm-up live on their own full-width row so they stay
            // on a single line instead of wrapping next to the weight stepper.
            accessoryButtons(ex: ex)

            if let last = ex.previousSummary {
                Text(last)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .lineLimit(1)
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

    /// "Show Plates" / "Warm-up" buttons. Rendered as a single-line row; emits
    /// nothing when neither applies (so no empty gap appears in the card).
    @ViewBuilder
    private func accessoryButtons(ex: ActiveExercise) -> some View {
        let showPlates = ex.equipment == .barbell
        let showWarmup = !ex.isTimed && ex.weight > 0
        if showPlates || showWarmup {
            HStack(spacing: LKSpacing.sm) {
                if showPlates {
                    showPlatesButton(weight: ex.weight, unit: ex.weightUnit)
                }
                if showWarmup {
                    warmupButton(weight: ex.weight, unit: ex.weightUnit)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Equipment icon (icon-only) + a prominent weight stepper with full ± buttons.
    @ViewBuilder
    private func weightControls(exIdx: Int, ex: ActiveExercise) -> some View {
        HStack(spacing: LKSpacing.sm) {
            if ex.equipment != .none {
                Image(systemName: ex.equipment.sfSymbol)
                    .font(.system(size: 15))
                    .foregroundColor(LKColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
                    .accessibilityLabel(ex.equipment.rawValue)
            }
            Button {
                vm.adjustWeight(exerciseIndex: exIdx, delta: -weightIncrement)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(LKColor.textSecondary)
            }
            .accessibilityLabel("Decrease weight by \(incLabel)")

            Button {
                numberEntry = NumberEntryItem(
                    title: "Weight", message: "Enter weight",
                    currentValue: ex.weight, minValue: 0, maxValue: 999
                ) { vm.activeExercises[exIdx].weight = $0 }
            } label: {
                VStack(spacing: 0) {
                    Text("\(Int(ex.weight))")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(LKColor.accent)
                        .contentTransition(.numericText())
                    Text(ex.weightUnit.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(LKColor.textMuted)
                }
                .frame(minWidth: 58)
            }
            .accessibilityLabel("\(Int(ex.weight)) \(ex.weightUnit.rawValue), edit weight")

            Button {
                vm.adjustWeight(exerciseIndex: exIdx, delta: weightIncrement)
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(LKColor.accent)
            }
            .accessibilityLabel("Increase weight by \(incLabel)")
        }
    }

    private func showPlatesButton(weight: Double, unit: WeightUnit) -> some View {
        Button {
            plateTarget = PlateTarget(weight: weight, unit: unit)
            HapticManager.shared.buttonTap()
        } label: {
            Label("Show Plates", systemImage: "circle.grid.2x2.fill")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(LKColor.accent)
                .padding(.horizontal, LKSpacing.sm)
                .padding(.vertical, 5)
                .background(LKColor.surfaceElevated)
                .clipShape(Capsule())
                .fixedSize()
        }
    }

    private func warmupButton(weight: Double, unit: WeightUnit) -> some View {
        Button {
            warmupTarget = PlateTarget(weight: weight, unit: unit)
            HapticManager.shared.buttonTap()
        } label: {
            Label("Warm-up", systemImage: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(LKColor.accent)
                .padding(.horizontal, LKSpacing.sm)
                .padding(.vertical, 5)
                .background(LKColor.surfaceElevated)
                .clipShape(Capsule())
                .fixedSize()
        }
    }

    /// Whole-number increment label ("5", "2.5", …) for the ± weight buttons.
    private var incLabel: String {
        weightIncrement == weightIncrement.rounded() ? "\(Int(weightIncrement))" : String(format: "%.1f", weightIncrement)
    }

    private func setCircle(exIdx: Int, setIdx: Int, set: ActiveSet) -> some View {
        let isRunning = timedSet == TimedSetKey(exIdx: exIdx, setIdx: setIdx)
        return Button {
            if set.isTimed {
                handleTimedSetTap(exIdx: exIdx, setIdx: setIdx, set: set, isRunning: isRunning)
            } else if set.isCompleted {
                // Tap completed → edit reps + RPE + set type
                editingSet = SetEditTarget(exIdx: exIdx, setIdx: setIdx)
            } else {
                // Mark complete, start rest timer (unless that was the last set)
                vm.logSet(exerciseIndex: exIdx, setIndex: setIdx, context: context)
                if !vm.isShowingComplete { startRestIfNeeded() }
                HapticManager.shared.setLogged()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(setCircleFill(set: set, isRunning: isRunning))
                    .frame(width: 48, height: 48)
                Text(setCircleLabel(set: set, isRunning: isRunning))
                    .font(.system(size: set.isTimed ? 13 : 14, weight: .bold))
                    .foregroundColor(setCircleTextColor(set: set, isRunning: isRunning))
                    .contentTransition(.numericText())
            }
        }
        .accessibilityLabel(setCircleAccessibility(set: set, isRunning: isRunning))
    }

    private func setCircleFill(set: ActiveSet, isRunning: Bool) -> Color {
        if isRunning { return LKColor.accent }
        return set.isCompleted ? LKColor.success : LKColor.surfaceElevated
    }

    private func setCircleTextColor(set: ActiveSet, isRunning: Bool) -> Color {
        if isRunning { return LKColor.onAccent }        // dark text on gold
        return set.isCompleted ? .white : LKColor.textPrimary
    }

    private func setCircleLabel(set: ActiveSet, isRunning: Bool) -> String {
        if set.isTimed {
            return isRunning ? "\(timedRemaining)s" : "\(set.actualDuration)s"
        }
        return "\(set.actualReps)"
    }

    private func setCircleAccessibility(set: ActiveSet, isRunning: Bool) -> String {
        if set.isTimed {
            if isRunning { return "Set \(set.setNumber), \(timedRemaining) seconds remaining" }
            return "Set \(set.setNumber), \(set.actualDuration) second hold, \(set.isCompleted ? "completed" : "tap to start")"
        }
        return "Set \(set.setNumber), \(set.actualReps) reps, \(set.isCompleted ? "completed" : "incomplete")"
    }

    private func startRestIfNeeded() {
        let rest = Double(vm.activeConfig.restBetweenSets)
        if rest > 0 { restEngine.startRestTimer(rest) }
    }

    // MARK: - Timed set (hold) handling

    private func handleTimedSetTap(exIdx: Int, setIdx: Int, set: ActiveSet, isRunning: Bool) {
        if isRunning {
            // Stop early: log the elapsed hold time
            let elapsed = max(0, set.plannedDuration - timedRemaining)
            finishTimedSet(exIdx: exIdx, setIdx: setIdx, actual: elapsed)
        } else if set.isCompleted {
            editingSet = SetEditTarget(exIdx: exIdx, setIdx: setIdx)
        } else if timedSet == nil {
            startTimedSet(exIdx: exIdx, setIdx: setIdx, planned: set.plannedDuration)
        }
    }

    private func startTimedSet(exIdx: Int, setIdx: Int, planned: Int) {
        timedSetTimer?.invalidate()
        timedSet = TimedSetKey(exIdx: exIdx, setIdx: setIdx)
        timedRemaining = planned
        HapticManager.shared.phaseStart()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            if timedRemaining > 1 {
                withAnimation { timedRemaining -= 1 }
                if timedRemaining <= 3 { HapticManager.shared.countdownTick() }
            } else {
                finishTimedSet(exIdx: exIdx, setIdx: setIdx, actual: planned)
            }
        }
        timedSetTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func finishTimedSet(exIdx: Int, setIdx: Int, actual: Int) {
        timedSetTimer?.invalidate()
        timedSetTimer = nil
        timedSet = nil
        guard exIdx < vm.activeExercises.count, setIdx < vm.activeExercises[exIdx].sets.count else { return }
        vm.activeExercises[exIdx].sets[setIdx].actualDuration = actual
        vm.logSet(exerciseIndex: exIdx, setIndex: setIdx, context: context)
        HapticManager.shared.setLogged()
        if !vm.isShowingComplete { startRestIfNeeded() }
    }

    // MARK: - Manual
    private var manualContent: some View {
        VStack(spacing: stackSpacing) {
            Spacer()
            let sessionName = vm.activeSessionCards.first?.name ?? ""
            if !sessionName.isEmpty {
                Text(sessionName)
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
            }
            heroTimer(text: engine.formattedTime)
            activeWeightChip(sessionIndex: 0)
            // Large play/pause (shrinks in landscape)
            Button {
                if engine.isRunning { engine.pause() } else { engine.resume() }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(isLandscapePhone ? .title2 : .title)
                    .foregroundColor(LKColor.onAccent)
                    .frame(width: isLandscapePhone ? 60 : 88, height: isLandscapePhone ? 60 : 88)
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
                    .frame(width: isLandscapePhone ? 48 : 60, height: isLandscapePhone ? 48 : 60)
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
            Color.black.opacity(0.7).ignoresSafeArea()

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

                if let splits = vm.activeSession?.splits, !splits.isEmpty {
                    VStack(spacing: 2) {
                        Text("SPLITS")
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.textMuted)
                            .tracking(1)
                        ForEach(Array(splits.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1).  \(TimerEngine.format(s))")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(LKColor.textSecondary)
                        }
                    }
                    .padding(.vertical, LKSpacing.xs)
                }

                Text(vm.completionMessage)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LKSpacing.xl)

                Button {
                    vm.selectedTab = 1   // History tab
                    vm.endWorkout(context: context)
                } label: {
                    Label("Review & Edit in History", systemImage: "square.and.pencil")
                }
                .buttonStyle(LKSecondaryButtonStyle())
                .padding(.horizontal, LKSpacing.xl)

                Text("Tap anywhere to continue")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
            }
            .padding(LKSpacing.xl)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(LKSpacing.lg)
        }
        .onTapGesture { vm.endWorkout(context: context) }
        .transition(.opacity)
    }
}

// MARK: - Plate Calculator

struct PlateTarget: Identifiable {
    let id = UUID()
    let weight: Double
    let unit: WeightUnit
}

enum PlateMath {
    /// Plates to load per side of a standard barbell (45 lb / 20 kg) for a target
    /// total weight, largest first, plus any per-side remainder that can't be loaded.
    static func platesPerSide(target: Double, unit: WeightUnit) -> (bar: Double, plates: [Double], leftover: Double) {
        let bar: Double = unit == .lb ? 45 : 20
        guard target > bar else { return (bar, [], 0) }
        var perSide = (target - bar) / 2
        let sizes: [Double] = unit == .lb ? [45, 35, 25, 10, 5, 2.5] : [25, 20, 15, 10, 5, 2.5, 1.25]
        var plates: [Double] = []
        for s in sizes {
            while perSide >= s - 0.0001 {
                plates.append(s)
                perSide -= s
            }
        }
        return (bar, plates, max(0, perSide))
    }
}

struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    let target: PlateTarget

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.2f", v)
    }

    var body: some View {
        let r = PlateMath.platesPerSide(target: target.weight, unit: target.unit)
        let sizes = Set(r.plates).sorted(by: >)
        return NavigationStack {
            VStack(spacing: LKSpacing.lg) {
                Text("\(fmt(target.weight)) \(target.unit.rawValue)")
                    .font(LKFont.title)
                    .foregroundColor(LKColor.textPrimary)
                Text("\(fmt(r.bar)) \(target.unit.rawValue) bar + per side:")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)

                if r.plates.isEmpty {
                    Text("Just the bar")
                        .font(LKFont.heading)
                        .foregroundColor(LKColor.textSecondary)
                } else {
                    VStack(spacing: LKSpacing.sm) {
                        ForEach(sizes, id: \.self) { size in
                            let count = r.plates.filter { $0 == size }.count
                            HStack {
                                Text("\(fmt(size)) \(target.unit.rawValue)")
                                    .font(LKFont.bodyBold)
                                    .foregroundColor(LKColor.textPrimary)
                                Spacer()
                                Text("× \(count)")
                                    .font(LKFont.body)
                                    .foregroundColor(LKColor.accent)
                            }
                            .padding(.horizontal, LKSpacing.md)
                            .padding(.vertical, LKSpacing.sm)
                            .background(LKColor.surface)
                            .cornerRadius(LKRadius.medium)
                        }
                    }
                    .padding(.horizontal, LKSpacing.lg)
                }

                if r.leftover > 0.01 {
                    Text("+\(fmt(r.leftover)) \(target.unit.rawValue) per side not loadable")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.danger)
                }
                Spacer()
            }
            .padding(.top, LKSpacing.xl)
            .frame(maxWidth: .infinity)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(LKColor.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Set Edit Sheet (reps/duration + RPE + set type)

struct SetEditTarget: Identifiable {
    let id = UUID()
    let exIdx: Int
    let setIdx: Int
}

struct SetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isTimed: Bool
    let setNumber: Int
    let onSave: (Int, Double?, SetType) -> Void

    @State private var value: Int
    @State private var rpe: Double?
    @State private var setType: SetType

    private let rpeOptions: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    init(isTimed: Bool, setNumber: Int, value: Int, rpe: Double?, setType: SetType,
         onSave: @escaping (Int, Double?, SetType) -> Void) {
        self.isTimed = isTimed
        self.setNumber = setNumber
        self.onSave = onSave
        _value = State(initialValue: value)
        _rpe = State(initialValue: rpe)
        _setType = State(initialValue: setType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isTimed ? "Seconds" : "Reps") {
                    Stepper("\(value)", value: $value, in: 0...600, step: isTimed ? 5 : 1)
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
                    Button("Save") { onSave(value, rpe, setType); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Warm-up calculator

enum WarmupMath {
    /// Stronglifts-style warm-up ramp to a working weight (bar ×2, then 40/60/80%).
    static func sets(working: Double, unit: WeightUnit) -> [(weight: Double, reps: Int)] {
        let bar: Double = unit == .lb ? 45 : 20
        guard working > bar else { return [] }
        let step: Double = unit == .lb ? 5 : 2.5
        func roundToStep(_ w: Double) -> Double { max(bar, (w / step).rounded() * step) }
        var result: [(Double, Int)] = [(bar, 5), (bar, 5)]
        for (pct, reps) in [(0.4, 5), (0.6, 3), (0.8, 2)] {
            let w = roundToStep(working * pct)
            if w > bar && w < working { result.append((w, reps)) }
        }
        return result
    }
}

struct WarmupView: View {
    @Environment(\.dismiss) private var dismiss
    let target: PlateTarget

    private func fmt(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

    var body: some View {
        let sets = WarmupMath.sets(working: target.weight, unit: target.unit)
        return NavigationStack {
            VStack(spacing: LKSpacing.lg) {
                Text("Warm-up to \(fmt(target.weight)) \(target.unit.rawValue)")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)

                if sets.isEmpty {
                    Text("No warm-up needed for this weight.")
                        .font(LKFont.body)
                        .foregroundColor(LKColor.textSecondary)
                } else {
                    VStack(spacing: LKSpacing.sm) {
                        ForEach(Array(sets.enumerated()), id: \.offset) { i, set in
                            HStack {
                                Text("Set \(i + 1)")
                                    .font(LKFont.caption)
                                    .foregroundColor(LKColor.textMuted)
                                Spacer()
                                Text("\(fmt(set.weight)) \(target.unit.rawValue) × \(set.reps)")
                                    .font(LKFont.bodyBold)
                                    .foregroundColor(LKColor.textPrimary)
                            }
                            .padding(.horizontal, LKSpacing.md)
                            .padding(.vertical, LKSpacing.sm)
                            .background(LKColor.surface)
                            .cornerRadius(LKRadius.medium)
                        }
                    }
                    .padding(.horizontal, LKSpacing.lg)
                }
                Spacer()
            }
            .padding(.top, LKSpacing.xl)
            .frame(maxWidth: .infinity)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Warm-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(LKColor.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
