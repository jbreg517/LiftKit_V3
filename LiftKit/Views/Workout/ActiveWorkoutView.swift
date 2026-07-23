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
    @ObservedObject private var quickActions = QuickActions.shared

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

    // Reps: ELAPSED header display, driven off the view model's active clock.
    @State private var repsElapsed: TimeInterval = 0
    @State private var repsTimer: Timer?

    // Live Activity mirror for reps mode: which exercise it's showing and
    // since when (the count-up anchor on that exercise).
    @State private var repsLAExercise: String?
    @State private var repsLAAnchor = Date()

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
            if type == .reps {
                startRepsTimer()
                // Mirror rest start/end (and skips) onto the Live Activity.
                restEngine.onPhaseChange = { _ in
                    DispatchQueue.main.async { updateRepsLiveActivity() }
                }
            }
            quickActions.control = nil   // discard any stale Siri command
        }
        .onChange(of: quickActions.control) { _, cmd in
            handleVoiceControl(cmd)
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

    /// Indices of the card(s) the athlete is on right now. EMOM rotates its
    /// minute-slots — cards linked in setup share a slot and are all done that
    /// minute (e.g. a kettlebell complex); the other types follow
    /// currentSessionIndex.
    private var currentSlot: [Int] {
        let count = vm.activeSessionCards.count
        guard count > 0 else { return [] }
        switch type {
        case .emom:
            let slots = vm.emomSlots
            guard !slots.isEmpty else { return [] }
            return slots[(engine.currentRound - 1) % slots.count]
        case .amrap:
            // The whole round is a circuit — every card in it is "current".
            let slots = vm.amrapSlots
            guard !slots.isEmpty else { return [] }
            return slots[min(max(0, engine.currentRound - 1), slots.count - 1)]
        default:
            return [min(vm.currentSessionIndex, count - 1)]
        }
    }

    private var currentCardIndex: Int { currentSlot.first ?? 0 }

    // The title always names the *current* exercise(s) (engine.currentRound is
    // observable, so this live-updates as EMOM rounds tick over).
    private var navTitle: String {
        let cards = vm.activeSessionCards
        let names = currentSlot.compactMap { idx -> String? in
            guard cards.indices.contains(idx), !cards[idx].name.isEmpty else { return nil }
            return cards[idx].name
        }
        if !names.isEmpty { return names.joined(separator: " + ") }
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
                if engine.isRunning { engine.pause(); vm.workoutClockPause() }
                else { engine.resume(); vm.workoutClockResume() }
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
        // Landscape shares the width with the info column, so the timer is a
        // touch smaller there and everything fits without scrolling.
        Text(text)
            .font(LKFont.timer(isLandscapePhone ? 100 : 112))
            .foregroundColor(color)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Adaptive timer layout
    /// Portrait stacks everything in one centered column; landscape puts the
    /// timer block beside the info block so the whole screen is visible
    /// without scrolling.
    @ViewBuilder
    private func timerLayout<T: View, I: View>(
        @ViewBuilder timer: () -> T,
        @ViewBuilder info: () -> I
    ) -> some View {
        if isLandscapePhone {
            HStack(alignment: .center, spacing: LKSpacing.lg) {
                VStack(spacing: LKSpacing.sm) { timer() }
                    .frame(maxWidth: .infinity)
                VStack(spacing: LKSpacing.md) { info() }
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, LKSpacing.md)
        } else {
            VStack(spacing: LKSpacing.lg) {
                timer()
                info()
            }
        }
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
    private func activeWeightChip(sessionIndex: Int, showName: Bool = false) -> some View {
        let card = vm.activeSessionCards.indices.contains(sessionIndex)
            ? vm.activeSessionCards[sessionIndex]
            : SessionCard()
        return HStack(spacing: LKSpacing.sm) {
            if showName {
                // In a multi-exercise minute the name identifies each row
                // (shown instead of the wider equipment capsule).
                Text(card.name.isEmpty ? "Workout \(sessionIndex + 1)" : card.name)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .leading)
            } else if card.equipment != .none {
                Label {
                    Text(card.equipment.rawValue)
                } icon: {
                    EquipmentIcon(equipment: card.equipment, size: 13)
                }
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                    .padding(.horizontal, LKSpacing.sm)
                    .padding(.vertical, LKSpacing.xs)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Capsule())
            }
            // Unified weight stepper [−  135 lb  +], matching the reps cards.
            HStack(spacing: 0) {
                Button {
                    vm.adjustSessionWeight(sessionIndex: sessionIndex, delta: -5)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LKColor.textSecondary)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("Decrease weight by 5")

                Button {
                    numberEntry = NumberEntryItem(
                        title: "Weight", message: "Enter weight",
                        currentValue: card.weight, minValue: 0, maxValue: 999
                    ) { vm.activeSessionCards[sessionIndex].weight = $0 }
                } label: {
                    VStack(spacing: 0) {
                        Text("\(Int(card.weight))")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(LKColor.accent)
                            .contentTransition(.numericText())
                        Text(card.weightUnit.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(LKColor.textMuted)
                    }
                    .frame(minWidth: 44)
                }
                .accessibilityLabel("\(Int(card.weight)) \(card.weightUnit.rawValue), edit weight")

                Button {
                    vm.adjustSessionWeight(sessionIndex: sessionIndex, delta: 5)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LKColor.accent)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("Increase weight by 5")
            }
            .background(LKColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Unified reps stepper [−  10 reps  +], adjustable mid-workout.
            HStack(spacing: 0) {
                Button {
                    if vm.activeSessionCards.indices.contains(sessionIndex) {
                        vm.activeSessionCards[sessionIndex].reps =
                            max(0, vm.activeSessionCards[sessionIndex].reps - 1)
                    }
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LKColor.textSecondary)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("Decrease reps")

                Button {
                    numberEntry = NumberEntryItem(
                        title: "Reps", message: "Enter reps",
                        currentValue: Double(card.reps), minValue: 0, maxValue: 999
                    ) { newValue in
                        if vm.activeSessionCards.indices.contains(sessionIndex) {
                            vm.activeSessionCards[sessionIndex].reps = Int(newValue)
                        }
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text("\(card.reps)")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(LKColor.accent)
                            .contentTransition(.numericText())
                        Text("reps")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(LKColor.textMuted)
                    }
                    .frame(minWidth: 40)
                }
                .accessibilityLabel("\(card.reps) reps, edit reps")

                Button {
                    if vm.activeSessionCards.indices.contains(sessionIndex) {
                        vm.activeSessionCards[sessionIndex].reps += 1
                    }
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(LKColor.accent)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("Increase reps")
            }
            .background(LKColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        case .amrap:     return engine.totalRounds > 1 ? "Round \(engine.currentRound)" : type.rawValue
        default:         return type.rawValue
        }
    }

    // MARK: - Siri / voice control

    /// Applies a Siri pause/resume/end command to the live workout. Pause/resume
    /// act on the main timer (and the rest timer if it's the one running); end
    /// saves and closes the workout.
    private func handleVoiceControl(_ cmd: WorkoutControl?) {
        guard let cmd else { return }
        quickActions.control = nil
        switch cmd {
        case .pause:
            engine.pause()
            restEngine.pause()
            vm.workoutClockPause()
            HapticManager.shared.buttonTap()
        case .resume:
            if engine.phase == .work || engine.phase == .rest { engine.resume() }
            if restEngine.phase == .work || restEngine.phase == .rest { restEngine.resume() }
            vm.workoutClockResume()
            HapticManager.shared.buttonTap()
        case .end:
            vm.endWorkout(context: context)
        }
    }

    // MARK: - Start helpers

    /// Drives the reps ELAPSED header off the shared active-time clock, so it
    /// shows working time (no countdown, no paused time) and matches the recorded
    /// duration. Anchored in the view model, so it survives backgrounding.
    private func startRepsTimer() {
        repsElapsed = vm.activeWorkoutSeconds
        repsTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            repsElapsed = vm.activeWorkoutSeconds
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
        vm.workoutClockStart()   // active-time clock begins after the countdown
        engine.start(config: vm.activeConfig)
        engine.onComplete = {
            DispatchQueue.main.async {
                vm.completeWorkout(context: context)
                LiveActivityManager.shared.stop()
            }
        }

        let workoutType = type
        // Card(s) the athlete is on for a given round. EMOM rotates its
        // minute-slots — cards linked in setup share a slot and are all done
        // that minute (e.g. a kettlebell complex); the other types follow
        // currentSessionIndex.
        let slotFor: (Int) -> [SessionCard] = { [weak vm] round in
            guard let vm, !vm.activeSessionCards.isEmpty else { return [] }
            let cards = vm.activeSessionCards
            switch workoutType {
            case .emom:
                let slots = WorkoutViewModel.minuteSlots(for: cards)
                guard !slots.isEmpty else { return [] }
                return slots[(round - 1) % slots.count].compactMap {
                    cards.indices.contains($0) ? cards[$0] : nil
                }
            case .amrap:
                // The round is a circuit — name every exercise in it.
                let slots = WorkoutViewModel.roundSlots(for: cards)
                guard !slots.isEmpty else { return [] }
                return slots[min(max(0, round - 1), slots.count - 1)].compactMap {
                    cards.indices.contains($0) ? cards[$0] : nil
                }
            default:
                return [cards[min(vm.currentSessionIndex, cards.count - 1)]]
            }
        }
        let sessionName = vm.activeSession?.name ?? workoutType.rawValue
        let nameFor: ([SessionCard]) -> String = { slot in
            let names = slot.compactMap { $0.name.isEmpty ? nil : $0.name }
            return names.isEmpty ? sessionName : names.joined(separator: " + ")
        }
        // One weight when the whole slot shares it (typical for a kettlebell
        // complex); mixed weights are spelled out per exercise in the
        // notification detail instead.
        let weightTextFor: ([SessionCard]) -> String? = { slot in
            guard let first = slot.first, first.weight > 0,
                  slot.allSatisfy({ $0.weight == first.weight && $0.weightUnit == first.weightUnit })
            else { return nil }
            return "\(Int(first.weight)) \(first.weightUnit.rawValue)"
        }
        let repsFor: ([SessionCard]) -> Int? = { slot in
            slot.count == 1 ? slot.first?.reps : nil
        }

        // Backgrounded notifications: the workout's name as the title, the
        // round's exercise(s)/reps/weight in the body.
        engine.notificationTitle = sessionName
        engine.roundDetail = { round in
            let slot = slotFor(round)
            guard !slot.isEmpty else { return nil }
            if slot.count == 1 {
                let card = slot[0]
                var parts = [nameFor(slot), "\(card.reps) reps"]
                if let w = weightTextFor(slot) { parts.append(w) }
                return parts.joined(separator: " · ")
            }
            // A linked complex — every exercise happens this minute,
            // e.g. "Clean ×2 · Press ×1 · Squat ×3 @ 53 lb".
            var detail = slot.enumerated()
                .map { i, card in "\(card.name.isEmpty ? "Workout \(i + 1)" : card.name) ×\(card.reps)" }
                .joined(separator: " · ")
            if let w = weightTextFor(slot) { detail += " @ \(w)" }
            return detail
        }

        // The Live Activity's countdown targets the *whole workout's* end, not
        // the current phase's. Per-phase updates can't fire while the app is
        // suspended in the background, so a per-minute countdown would freeze
        // at 0:00 — the workout-end date keeps ticking regardless (and for
        // EMOM its seconds column mirrors the per-minute countdown anyway).
        // Recomputed on every foreground phase change, so pauses self-correct.
        let cfg = vm.activeConfig
        let workoutEndFor: (TimerEngine) -> Date? = { engine in
            guard let phaseEnd = engine.phaseEndDate else { return nil }
            switch workoutType {
            case .emom:
                return phaseEnd.addingTimeInterval(Double(engine.totalRounds - engine.currentRound) * 60)
            case .intervals:
                let fullRoundsLeft = Double(engine.totalRounds - engine.currentRound) * (cfg.workDuration + cfg.restDuration)
                return phaseEnd.addingTimeInterval(engine.phase == .work ? cfg.restDuration + fullRoundsLeft : fullRoundsLeft)
            case .amrap:
                // Multi-round AMRAP: current round's end + the remaining rounds.
                let durations = cfg.roundDurations
                if durations.count > 1, engine.currentRound < durations.count {
                    let remaining = durations[engine.currentRound...].reduce(0, +)
                    return phaseEnd.addingTimeInterval(remaining)
                }
                return phaseEnd
            default:
                return phaseEnd
            }
        }
        let startedAt = Date()   // count-up anchor for For Time / Manual

        // Update the live activity whenever the timer phase changes
        engine.onPhaseChange = { [engine] _ in
            DispatchQueue.main.async {
                let label: String
                switch workoutType {
                case .emom:      label = "Minute \(engine.currentRound)"
                case .intervals: label = engine.phase == .work ? "Work" : "Rest"
                case .amrap:     label = engine.totalRounds > 1 ? "Round \(engine.currentRound)" : workoutType.rawValue
                default:         label = workoutType.rawValue
                }
                let slot = slotFor(engine.currentRound)
                let end = workoutEndFor(engine)
                LiveActivityManager.shared.update(
                    workoutName: nameFor(slot),
                    currentRound: engine.currentRound,
                    totalRounds: engine.totalRounds,
                    phaseLabel: label,
                    phaseEndDate: end,
                    phaseStartDate: end == nil ? startedAt : nil,
                    reps: repsFor(slot),
                    weightText: weightTextFor(slot)
                )
            }
        }
        // Start the Live Activity (lock screen + Dynamic Island)
        if workoutType == .reps {
            LiveActivityManager.shared.start(
                workoutName: sessionName,
                workoutType: workoutType.rawValue,
                currentRound: 1,
                totalRounds: 1,
                phaseLabel: "Workout",
                phaseEndDate: nil,
                phaseStartDate: startedAt
            )
            updateRepsLiveActivity()   // fills in the current exercise + sets
        } else {
            let startSlot = slotFor(engine.currentRound)
            let end = workoutEndFor(engine)
            LiveActivityManager.shared.start(
                workoutName: nameFor(startSlot),
                workoutType: workoutType.rawValue,
                currentRound: engine.currentRound,
                totalRounds: engine.totalRounds,
                phaseLabel: liveActivityPhaseLabel(engine: engine),
                phaseEndDate: end,
                phaseStartDate: end == nil ? startedAt : nil,
                reps: repsFor(startSlot),
                weightText: weightTextFor(startSlot)
            )
        }
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
    // The round is a circuit: all of its exercises show at once (via
    // slotWeightChips). Multi-round AMRAPs also show which timed round is up.
    private var amrapContent: some View {
        VStack(spacing: 0) {
            Spacer()
            timerLayout {
                phaseLabel(engine)
                heroTimer(text: engine.formattedTime)
                if engine.totalRounds > 1 {
                    Text("Round \(engine.currentRound) of \(engine.totalRounds)")
                        .font(LKFont.body)
                        .foregroundColor(LKColor.textSecondary)
                }
            } info: {
                slotWeightChips
                amrapUpNext
                roundsCounter
                timerControls(engine: engine)
                notesDisplay()
            }
            Spacer()
        }
    }

    // Previews the next timed round of a multi-round AMRAP.
    @ViewBuilder
    private var amrapUpNext: some View {
        let slots = vm.amrapSlots
        if slots.count > 1, engine.currentRound < slots.count {
            let cards = vm.activeSessionCards
            let label = slots[engine.currentRound]
                .map { cards.indices.contains($0) && !cards[$0].name.isEmpty ? cards[$0].name : "Workout \($0 + 1)" }
                .joined(separator: " + ")
            VStack(spacing: LKSpacing.xs) {
                Text("UP NEXT")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .tracking(1)
                Text(label)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // Rounds counter as one unified rounded control, matching the stepper
    // styling used across the workout cards.
    private var roundsCounter: some View {
        VStack(spacing: LKSpacing.xs) {
            Text("ROUNDS COMPLETED")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(1)
            HStack(spacing: 0) {
                Button {
                    vm.adjustCompletedRounds(by: -1, timedRound: engine.currentRound)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(LKColor.textSecondary)
                        .frame(width: 52, height: isLandscapePhone ? 56 : 68)
                }
                .accessibilityLabel("Subtract round")

                Button {
                    numberEntry = NumberEntryItem(
                        title: "Rounds Completed",
                        message: "Enter rounds completed",
                        currentValue: Double(vm.completedRounds),
                        minValue: 0, maxValue: 999
                    ) { vm.setCompletedRounds(Int($0), timedRound: engine.currentRound) }
                } label: {
                    Text("\(vm.completedRounds)")
                        .font(LKFont.timer(isLandscapePhone ? 40 : 48))
                        .foregroundColor(LKColor.accent)
                        .contentTransition(.numericText())
                        .frame(minWidth: 72)
                }
                .accessibilityLabel("\(vm.completedRounds) rounds completed, edit")

                Button {
                    vm.adjustCompletedRounds(by: 1, timedRound: engine.currentRound)
                    // Record the split at total elapsed time (earlier timed
                    // rounds + progress through the current one).
                    let durations = vm.activeConfig.roundDurations
                    let elapsed: TimeInterval
                    if durations.count > 1 {
                        let prior = durations.prefix(engine.currentRound - 1).reduce(0, +)
                        let current = durations[min(engine.currentRound - 1, durations.count - 1)]
                        elapsed = prior + max(0, current - engine.timeRemaining)
                    } else {
                        elapsed = vm.activeConfig.totalDuration - engine.timeRemaining
                    }
                    vm.recordSplit(elapsed, context: context)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(LKColor.accent)
                        .frame(width: 52, height: isLandscapePhone ? 56 : 68)
                }
                .accessibilityLabel("Add round")
            }
            .background(LKColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - EMOM
    // The current exercise's name lives in the nav bar (navTitle), so it isn't
    // repeated in the body.
    private var emomContent: some View {
        VStack(spacing: 0) {
            Spacer()
            timerLayout {
                phaseLabel(engine)
                heroTimer(text: engine.formattedTime)
                Text("Minute \(engine.currentRound) of \(engine.totalRounds)")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
            } info: {
                slotWeightChips
                upNextView
                timerControls(engine: engine)
                notesDisplay()
            }
            Spacer()
        }
    }

    /// Weight/reps chips for every exercise in the current minute — one row
    /// when minutes rotate single exercises, a named row per exercise when the
    /// minute is a linked complex.
    @ViewBuilder
    private var slotWeightChips: some View {
        let slot = currentSlot
        if slot.count <= 1 {
            activeWeightChip(sessionIndex: slot.first ?? 0)
        } else {
            VStack(spacing: LKSpacing.xs) {
                ForEach(slot, id: \.self) { idx in
                    activeWeightChip(sessionIndex: idx, showName: true)
                }
            }
        }
    }

    // "Up Next" previews the following minute-slot; hidden when every exercise
    // is linked into one slot (the same complex repeats every minute).
    @ViewBuilder
    private var upNextView: some View {
        let slots = vm.emomSlots
        if slots.count > 1 {
            let cards = vm.activeSessionCards
            let nextSlot = slots[engine.currentRound % slots.count]
            let label = nextSlot
                .map { cards.indices.contains($0) && !cards[$0].name.isEmpty ? cards[$0].name : "Workout \($0 + 1)" }
                .joined(separator: " + ")
            VStack(spacing: LKSpacing.xs) {
                Text("UP NEXT")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .tracking(1)
                Text(label)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - For Time
    private var forTimeContent: some View {
        let isOverCap = engine.elapsedTime > vm.activeConfig.totalDuration
        return VStack(spacing: 0) {
            Spacer()
            timerLayout {
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
            } info: {
                activeWeightChip(sessionIndex: vm.currentSessionIndex)
                markCompleteButton
                timerControls(engine: engine)
                notesDisplay()
            }
            Spacer()
        }
    }

    private var markCompleteButton: some View {
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
                .padding(isLandscapePhone ? LKSpacing.sm : LKSpacing.md)
                .background(LKColor.work)
                .cornerRadius(LKRadius.medium)
        }
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Intervals
    private var intervalsContent: some View {
        VStack(spacing: 0) {
            Spacer()
            timerLayout {
                multiSessionIndicator()
                phaseLabel(engine)
                heroTimer(text: engine.formattedTime)
                Text("Round \(engine.currentRound) of \(engine.totalRounds)")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
            } info: {
                activeWeightChip(sessionIndex: vm.currentSessionIndex)
                timerControls(engine: engine)
                notesDisplay()
            }
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
                        LiveActivityManager.shared.stop()
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
            updateRepsLiveActivity()   // keep the rest countdown in sync
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

            setsProgress(ex)

            // Plates / warm-up live on their own full-width row so they stay
            // on a single line instead of wrapping next to the weight stepper.
            accessoryButtons(ex: ex)

            if let last = ex.previousSummary {
                Text(last)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .lineLimit(1)
            }

            // Set tiles
            HStack(spacing: LKSpacing.sm) {
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { (setIdx, set) in
                    setCircle(exIdx: exIdx, setIdx: setIdx, set: set)
                }
            }
        }
        .lkCard()
    }

    /// Thin gold rail under the exercise header showing sets done vs planned.
    private func setsProgress(_ ex: ActiveExercise) -> some View {
        let done = ex.sets.filter(\.isCompleted).count
        let total = max(1, ex.sets.count)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LKColor.surfaceElevated)
                Capsule().fill(LKColor.accent)
                    .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.25), value: done)
        .accessibilityHidden(true)
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

    /// Equipment icon (icon-only) + the weight stepper as one unified rounded
    /// control ([−  135 lb  +]) rather than free-floating ± buttons.
    @ViewBuilder
    private func weightControls(exIdx: Int, ex: ActiveExercise) -> some View {
        HStack(spacing: LKSpacing.sm) {
            if ex.equipment != .none {
                EquipmentIcon(equipment: ex.equipment, size: 15)
                    .foregroundColor(LKColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(LKColor.surfaceElevated)
                    .clipShape(Circle())
                    .accessibilityLabel(ex.equipment.rawValue)
            }
            HStack(spacing: 0) {
                Button {
                    vm.adjustWeight(exerciseIndex: exIdx, delta: -weightIncrement)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(LKColor.textSecondary)
                        .frame(width: 38, height: 46)
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
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(LKColor.accent)
                            .contentTransition(.numericText())
                        Text(ex.weightUnit.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(LKColor.textMuted)
                    }
                    .frame(minWidth: 54)
                }
                .accessibilityLabel("\(Int(ex.weight)) \(ex.weightUnit.rawValue), edit weight")

                Button {
                    vm.adjustWeight(exerciseIndex: exIdx, delta: weightIncrement)
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(LKColor.accent)
                        .frame(width: 38, height: 46)
                }
                .accessibilityLabel("Increase weight by \(incLabel)")
            }
            .background(LKColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                afterSetLogged()
                HapticManager.shared.setLogged()
            }
        } label: {
            // Rounded tile with a "SET n" caption — LiftKit's own look for
            // set logging (deliberately not a plain circle row).
            VStack(spacing: 3) {
                Text("SET \(set.setNumber)")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(setCaptionColor(set: set, isRunning: isRunning))
                Text(setCircleLabel(set: set, isRunning: isRunning))
                    .font(.system(size: set.isTimed ? 14 : 16, weight: .bold))
                    .foregroundColor(setCircleTextColor(set: set, isRunning: isRunning))
                    .contentTransition(.numericText())
            }
            .frame(width: 52, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(setCircleFill(set: set, isRunning: isRunning))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(set.isCompleted && !isRunning ? LKColor.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .accessibilityLabel(setCircleAccessibility(set: set, isRunning: isRunning))
        .contextMenu {
            // Rep sets get a long-press menu: Complete on top, then a scrollable
            // 0…planned rep picker. (Timed holds keep their tap-to-start flow.)
            if !set.isTimed {
                Button {
                    completeSet(exIdx: exIdx, setIdx: setIdx, reps: set.plannedReps)
                } label: {
                    Label("Complete (\(set.plannedReps) reps)", systemImage: "checkmark.circle.fill")
                }
                Section("Reps completed") {
                    ForEach(0...max(0, set.plannedReps), id: \.self) { n in
                        Button("\(n) rep\(n == 1 ? "" : "s")") {
                            completeSet(exIdx: exIdx, setIdx: setIdx, reps: n)
                        }
                    }
                }
            }
        }
    }

    /// Records a chosen rep count for a set. If the set was already logged it
    /// edits the existing record; otherwise it logs it (and starts rest).
    private func completeSet(exIdx: Int, setIdx: Int, reps: Int) {
        guard exIdx < vm.activeExercises.count,
              setIdx < vm.activeExercises[exIdx].sets.count else { return }
        if vm.activeExercises[exIdx].sets[setIdx].isCompleted {
            let s = vm.activeExercises[exIdx].sets[setIdx]
            vm.updateSet(exerciseIndex: exIdx, setIndex: setIdx,
                         repsOrDuration: reps, rpe: s.rpe, setType: s.setType, context: context)
        } else {
            vm.activeExercises[exIdx].sets[setIdx].actualReps = reps
            vm.logSet(exerciseIndex: exIdx, setIndex: setIdx, context: context)
            afterSetLogged()
        }
        HapticManager.shared.setLogged()
    }

    // Tile states: idle = flat elevated tile; done = gold-outlined with gold
    // text; running hold = solid gold with dark text.
    private func setCircleFill(set: ActiveSet, isRunning: Bool) -> Color {
        if isRunning { return LKColor.accent }
        return set.isCompleted ? LKColor.accent.opacity(0.16) : LKColor.surfaceElevated
    }

    private func setCircleTextColor(set: ActiveSet, isRunning: Bool) -> Color {
        if isRunning { return LKColor.onAccent }        // dark text on gold
        return set.isCompleted ? LKColor.accent : LKColor.textPrimary
    }

    private func setCaptionColor(set: ActiveSet, isRunning: Bool) -> Color {
        if isRunning { return LKColor.onAccent.opacity(0.75) }
        return set.isCompleted ? LKColor.accent.opacity(0.85) : LKColor.textMuted
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
        if rest > 0 {
            restEngine.startRestTimer(rest)   // fires onPhaseChange → Live Activity
        } else {
            updateRepsLiveActivity()
        }
    }

    /// Post-set bookkeeping: start the rest timer, or end the Live Activity
    /// when that set finished the workout.
    private func afterSetLogged() {
        if vm.isShowingComplete {
            LiveActivityManager.shared.stop()
        } else {
            startRestIfNeeded()
        }
    }

    /// The exercise being worked right now: the first with unfinished sets
    /// (falling back to the last one when everything's done).
    private var currentRepsExercise: ActiveExercise? {
        vm.activeExercises.first { $0.sets.contains { !$0.isCompleted } } ?? vm.activeExercises.last
    }

    /// Mirrors reps progress onto the Live Activity: the current exercise with
    /// a running clock on it, or "Rest" with the rest countdown between sets.
    private func updateRepsLiveActivity() {
        guard type == .reps else { return }
        if restEngine.phase == .rest, let end = restEngine.phaseEndDate, end > Date() {
            LiveActivityManager.shared.update(
                workoutName: currentRepsExercise?.name ?? vm.activeSession?.name ?? "Workout",
                currentRound: 1,
                totalRounds: 1,
                phaseLabel: "Rest",
                phaseEndDate: end
            )
            return
        }
        guard let ex = currentRepsExercise else { return }
        if repsLAExercise != ex.name {
            repsLAExercise = ex.name
            repsLAAnchor = Date()
        }
        let totalSets = max(1, ex.sets.count)
        let currentSet = min(ex.sets.filter(\.isCompleted).count + 1, totalSets)
        let nextSet = ex.sets.first { !$0.isCompleted }
        LiveActivityManager.shared.update(
            workoutName: ex.name,
            currentRound: currentSet,
            totalRounds: totalSets,
            phaseLabel: "Set \(currentSet) of \(totalSets)",
            phaseEndDate: nil,
            phaseStartDate: repsLAAnchor,
            reps: (nextSet?.isTimed == false) ? nextSet?.plannedReps : nil,
            weightText: ex.weight > 0 ? "\(Int(ex.weight)) \(ex.weightUnit.rawValue)" : nil
        )
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
        afterSetLogged()
    }

    // MARK: - Manual
    // The current exercise's name lives in the nav bar (navTitle).
    private var manualContent: some View {
        VStack(spacing: stackSpacing) {
            Spacer()
            heroTimer(text: engine.formattedTime)
            activeWeightChip(sessionIndex: currentCardIndex)
            // Large play/pause (shrinks in landscape)
            Button {
                if engine.isRunning { engine.pause(); vm.workoutClockPause() }
                else { engine.resume(); vm.workoutClockResume() }
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
    /// Linear warm-up ramp to a working weight (bar ×2, then 40/60/80%).
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
