import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutSchedule.date) private var schedules: [WorkoutSchedule]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var healthProfiles: [HealthProfile]
    @AppStorage("availableEquipment") private var availableEquipmentRaw = EquipmentPrefs.defaultRaw

    @Bindable var vm: WorkoutViewModel

    @State private var showCalendarPicker = false
    @State private var showSeriesSchedule = false

    private var userProfile: UserProfile? { profiles.first }
    private var isPremium: Bool { userProfile?.isPremium ?? false }

    /// Uncompleted schedules due today or carried forward from a missed day.
    private var dueSchedules: [WorkoutSchedule] {
        let today = Calendar.current.startOfDay(for: Date())
        return schedules.filter {
            !$0.isCompleted && Calendar.current.startOfDay(for: $0.date) <= today
        }
    }

    private var visibleTemplates: [WorkoutTemplate] {
        let limit = isPremium ? UserProfile.maxVisibleTemplates : UserProfile.maxFreeTemplates
        return Array(templates.prefix(limit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.lg) {
                    // Start Workout button
                    Button {
                        HapticManager.shared.buttonTap()
                        vm.showTypePicker = true
                    } label: {
                        Label("Start Workout Timer", systemImage: "play.fill")
                    }
                    .buttonStyle(LKPrimaryButtonStyle())
                    .accessibilityHint("Choose a workout type to start")
                    .padding(.horizontal, LKSpacing.md)

                    // Calendar (premium only)
                    if isPremium {
                        WorkoutCalendarView(vm: vm)
                            .padding(.horizontal, LKSpacing.md)
                    }

                    // Today / carried-forward scheduled workouts
                    dueWorkoutsSection

                    // Recommended workouts
                    recommendedSection

                    // Plans section
                    plansSection
                }
                .padding(.vertical, LKSpacing.md)
            }
            .background(LKColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                vm.userProfile = userProfile
                ExerciseLibrary.shared.seedIfNeeded(context: context)
                ExerciseLibrary.shared.backfillMuscles(context: context)
            }
        }
        .sheet(isPresented: $vm.showTypePicker) {
            WorkoutTypePickerView(vm: vm)
        }
        .sheet(isPresented: $vm.showWorkoutSetup) {
            NavigationStack {
                WorkoutSetupView(vm: vm, type: vm.selectedTimerType)
            }
        }
        .sheet(isPresented: $vm.showLogin) {
            LoginView(vm: vm)
        }
        .sheet(isPresented: $showSeriesSchedule) {
            SeriesScheduleSheet()
        }
        .fullScreenCover(isPresented: $vm.showActiveWorkout) {
            ActiveWorkoutView(vm: vm)
        }
    }

    // MARK: - Due workouts (today / carried forward)
    @ViewBuilder
    private var dueWorkoutsSection: some View {
        if !dueSchedules.isEmpty {
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                Text("TODAY")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .tracking(2)
                    .padding(.horizontal, LKSpacing.md)

                ForEach(dueSchedules) { sched in
                    let info = dueLabel(sched.date)
                    SwipeToDeleteRow(enabled: true, onDelete: { clearSchedule(sched) }) {
                        DueWorkoutCard(schedule: sched, dateLabel: info.text, overdue: info.overdue) {
                            startScheduled(sched)
                        }
                    }
                    .padding(.horizontal, LKSpacing.md)
                }
            }
        }
    }

    private func dueLabel(_ date: Date) -> (text: String, overdue: Bool) {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: Date())
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        if d == today { return ("Today", false) }
        let days = cal.dateComponents([.day], from: d, to: today).day ?? 0
        if days == 1 { return ("Yesterday · overdue", true) }
        if days > 1 { return ("\(f.string(from: date)) · overdue", true) }
        return (f.string(from: date), false)
    }

    private func startScheduled(_ sched: WorkoutSchedule) {
        guard let template = sched.template else { return }
        sched.isCompleted = true
        WorkoutReminders.cancel(sched)
        try? context.save()
        vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
        vm.markTemplateUsed(template, context: context)
        vm.showWorkoutSetup = true
    }

    private func clearSchedule(_ sched: WorkoutSchedule) {
        WorkoutReminders.cancel(sched)
        context.delete(sched)
        try? context.save()
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("LiftKit")
                .font(.system(size: 34, weight: .heavy))
                .foregroundColor(LKColor.textPrimary)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if let profile = userProfile {
                loggedInChip(profile: profile)
            } else {
                loginButton
            }
        }
    }

    private func loggedInChip(profile: UserProfile) -> some View {
        HStack(spacing: LKSpacing.xs) {
            Image(systemName: "person.fill")
                .font(.caption)
            Text(profile.displayName ?? "Premium")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LKColor.textSecondary)
            if profile.isPremium {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(LKColor.accent)
            }
        }
        .padding(.horizontal, LKSpacing.sm)
        .padding(.vertical, LKSpacing.xs)
        .overlay(
            Capsule().strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
        )
    }

    private var loginButton: some View {
        Button {
            vm.showLogin = true
        } label: {
            HStack(spacing: LKSpacing.xs) {
                Image(systemName: "person.fill")
                    .font(.caption)
                Text("Log In")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(LKColor.textSecondary)
            .padding(.horizontal, LKSpacing.sm)
            .padding(.vertical, LKSpacing.xs)
            .overlay(Capsule().strokeBorder(LKColor.surfaceElevated, lineWidth: 1))
        }
    }

    // MARK: - Recommended section
    /// Top 6 picks, personalized by recent training, recovery load, goal, and
    /// the equipment the user has marked available.
    private var recommendedPicks: [WorkoutRecommender.Pick] {
        WorkoutRecommender.top(6, sessions: sessions, health: healthProfiles.first,
                               available: EquipmentPrefs.available(availableEquipmentRaw))
    }

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("RECOMMENDED FOR YOU")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(2)
                .padding(.horizontal, LKSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LKSpacing.md) {
                    ForEach(recommendedPicks) { pick in
                        RecommendedCard(rec: pick.workout, reason: pick.reason) {
                            HapticManager.shared.buttonTap()
                            vm.loadRecommended(pick.workout)
                        }
                    }
                }
                .padding(.horizontal, LKSpacing.md)
            }

            NavigationLink(destination: AllWorkoutsView(vm: vm)) {
                HStack(spacing: LKSpacing.sm) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(LKColor.accent)
                    Text("Additional Workouts")
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.accent)
                    Spacer()
                }
                .padding(LKSpacing.md)
                .frame(maxWidth: .infinity)
                .background(LKColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: LKRadius.large)
                        .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
                )
                .cornerRadius(LKRadius.large)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, LKSpacing.md)
        }
    }

    // MARK: - Plans section
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack {
                Text("YOUR WORKOUT PLANS")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .tracking(2)
                Spacer()
                if !templates.isEmpty {
                    Button {
                        showSeriesSchedule = true
                        HapticManager.shared.buttonTap()
                    } label: {
                        Label("Schedule", systemImage: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(LKColor.accent)
                    }
                }
            }
            .padding(.horizontal, LKSpacing.md)

            ForEach(visibleTemplates) { template in
                SwipeToDeleteRow(enabled: true, onDelete: {
                    context.delete(template)
                    try? context.save()
                }) {
                    PlanCard(template: template) {
                        vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                        vm.markTemplateUsed(template, context: context)
                        vm.showWorkoutSetup = true
                    }
                }
                .padding(.horizontal, LKSpacing.md)
            }

            // Add button or upgrade prompt
            if isPremium || templates.count < UserProfile.maxFreeTemplates {
                Button {
                    vm.showTypePicker = true
                    HapticManager.shared.buttonTap()
                } label: {
                    HStack(spacing: LKSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(LKColor.accent)
                        Text("Add New Workout Plan")
                            .font(LKFont.bodyBold)
                            .foregroundColor(LKColor.accent)
                    }
                    .padding(.horizontal, LKSpacing.md)
                    .padding(.vertical, LKSpacing.sm)
                }
                .padding(.horizontal, LKSpacing.md)

            } else {
                Text("Free accounts limited to 5 plans. Sign in for premium.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LKSpacing.md)
            }

            // Premium users with > 10 templates see "View All"
            if isPremium && templates.count > UserProfile.maxVisibleTemplates {
                NavigationLink(destination: AllTemplatesView(templates: templates, vm: vm)) {
                    Text("View All \(templates.count) Plans")
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(LKSpacing.md)
                        .background(LKColor.surfaceElevated)
                        .cornerRadius(LKRadius.medium)
                }
                .padding(.horizontal, LKSpacing.md)
            }
        }
    }
}

// MARK: - Recommended Card
struct RecommendedCard: View {
    let rec: RecommendedWorkout
    var reason: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                HStack(spacing: LKSpacing.xs) {
                    Image(systemName: rec.type.sfSymbol)
                        .font(.system(size: 12))
                        .foregroundColor(LKColor.accent)
                    Text(rec.type.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LKColor.textMuted)
                    Spacer()
                }
                Text(rec.name)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let reason {
                    HStack(alignment: .top, spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 9))
                        Text(reason)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(LKColor.accent)
                } else {
                    Text(rec.blurb)
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(rec.purposes) { p in
                        Text(p.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(LKColor.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(LKColor.surfaceElevated)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(LKSpacing.md)
            .frame(width: 230, height: 150, alignment: .topLeading)
            .background(LKColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.large)
                    .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
            )
            .cornerRadius(LKRadius.large)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rec.name), \(rec.type.rawValue)")
    }
}

// MARK: - Plan Card
struct PlanCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: LKSpacing.xs) {
                    Text(template.name)
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textPrimary)
                    Text("\(template.exercises.count) exercises")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                }
                Spacer()
                Text(template.lastUsedAt.relativeFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(LKColor.textSecondary)
            }
            .padding(LKSpacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(LKColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: LKRadius.large)
                .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
        )
        .cornerRadius(LKRadius.large)
        .accessibilityLabel("\(template.name), \(template.exercises.count) exercises")
        .accessibilityHint("Double tap to start this workout")
    }
}

// MARK: - All Templates View (premium)
struct AllTemplatesView: View {
    let templates: [WorkoutTemplate]
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var sortOption = SortOption.recent

    enum SortOption: String, CaseIterable {
        case recent = "Recent"
        case name   = "Name"
    }

    private var filtered: [WorkoutTemplate] {
        var list = templates
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOption {
        case .recent: list.sort { $0.lastUsedAt > $1.lastUsedAt }
        case .name:   list.sort { $0.name < $1.name }
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.sm) {
                ForEach(filtered) { template in
                    SwipeToDeleteRow(enabled: true, onDelete: {
                        context.delete(template)
                        try? context.save()
                    }) {
                        PlanCard(template: template) {
                            vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                            vm.markTemplateUsed(template, context: context)
                            vm.showWorkoutSetup = true
                        }
                    }
                }
            }
            .padding(LKSpacing.md)
        }
        .navigationTitle("All Plans")
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .background(LKColor.background.ignoresSafeArea())
    }
}

// MARK: - Due Workout Card
struct DueWorkoutCard: View {
    let schedule: WorkoutSchedule
    let dateLabel: String
    let overdue: Bool
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: LKSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.displayName)
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textPrimary)
                        .lineLimit(1)
                    Text(dateLabel)
                        .font(LKFont.caption)
                        .foregroundColor(overdue ? LKColor.danger : LKColor.textMuted)
                }
                Spacer()
                if schedule.template != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(LKColor.accent)
                }
            }
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.large)
                    .strokeBorder(overdue ? LKColor.danger.opacity(0.45) : LKColor.surfaceElevated, lineWidth: 1)
            )
            .cornerRadius(LKRadius.large)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Swipe to clear this scheduled workout")
    }
}

// MARK: - Series Schedule Sheet
// Schedule up to 5 plans that auto-alternate across the chosen weekdays.
struct SeriesScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]

    @State private var selectedIDs: [UUID] = []
    @State private var weekdays: Set<Int> = []
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    private let cal = Calendar.current
    private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    private let maxTemplates = 5

    private var selected: [WorkoutTemplate] {
        selectedIDs.compactMap { id in templates.first { $0.id == id } }
    }

    private var occurrenceCount: Int {
        guard !weekdays.isEmpty, !selected.isEmpty else { return 0 }
        var count = 0
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(templates) { t in
                        let order = selectedIDs.firstIndex(of: t.id)
                        Button {
                            toggle(t)
                            HapticManager.shared.buttonTap()
                        } label: {
                            HStack {
                                if let order {
                                    Text("\(order + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.black)
                                        .frame(width: 22, height: 22)
                                        .background(LKColor.accent)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(LKColor.textMuted)
                                }
                                Text(t.name).foregroundColor(LKColor.textPrimary)
                                Spacer()
                            }
                        }
                        .disabled(order == nil && selectedIDs.count >= maxTemplates)
                    }
                } header: {
                    Text("Workouts (alternate in this order)")
                } footer: {
                    Text("Pick up to \(maxTemplates). They rotate across your chosen days — e.g. A, B, A, B…")
                }

                Section("Repeat On") {
                    HStack(spacing: LKSpacing.xs) {
                        ForEach(1...7, id: \.self) { wd in
                            let on = weekdays.contains(wd)
                            Button {
                                if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                            } label: {
                                Text(weekdayLabels[wd - 1])
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, LKSpacing.sm)
                                    .background(on ? LKColor.accent : LKColor.surfaceElevated)
                                    .foregroundColor(on ? .black : LKColor.textSecondary)
                                    .cornerRadius(LKRadius.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Range") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date).tint(LKColor.accent)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date).tint(LKColor.accent)
                }

                Section {
                    Text(scheduleSummary)
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Schedule a Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") { createSeries() }
                        .bold()
                        .disabled(selected.isEmpty || weekdays.isEmpty || occurrenceCount == 0)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var scheduleSummary: String {
        if selected.isEmpty { return "Select at least one workout." }
        if weekdays.isEmpty { return "Select the days to repeat on." }
        return "\(occurrenceCount) workout\(occurrenceCount == 1 ? "" : "s") will be scheduled, alternating \(selected.map(\.name).joined(separator: " → "))."
    }

    private func toggle(_ t: WorkoutTemplate) {
        if let idx = selectedIDs.firstIndex(of: t.id) {
            selectedIDs.remove(at: idx)
        } else if selectedIDs.count < maxTemplates {
            selectedIDs.append(t.id)
        }
    }

    private func createSeries() {
        let temps = selected
        guard !temps.isEmpty, !weekdays.isEmpty else { return }
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        var i = 0
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) {
                let sched = WorkoutSchedule(date: current, template: temps[i % temps.count])
                context.insert(sched)
                WorkoutReminders.schedule(sched)
                i += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Recurring Schedule Sheet

struct RecurringScheduleSheet: View {
    let template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var weekdays: Set<Int> = []
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    private let cal = Calendar.current
    private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var occurrenceCount: Int {
        guard !weekdays.isEmpty else { return 0 }
        var count = 0
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat On") {
                    HStack(spacing: LKSpacing.xs) {
                        ForEach(1...7, id: \.self) { wd in
                            let on = weekdays.contains(wd)
                            Button {
                                if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                                HapticManager.shared.buttonTap()
                            } label: {
                                Text(weekdayLabels[wd - 1])
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, LKSpacing.sm)
                                    .background(on ? LKColor.accent : LKColor.surfaceElevated)
                                    .foregroundColor(on ? .black : LKColor.textSecondary)
                                    .cornerRadius(LKRadius.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Range") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date).tint(LKColor.accent)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date).tint(LKColor.accent)
                }

                Section {
                    Text(scheduleSummary)
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Schedule \(template.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") { createSchedules() }
                        .bold()
                        .disabled(weekdays.isEmpty || occurrenceCount == 0)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var scheduleSummary: String {
        if weekdays.isEmpty { return "Select the days to repeat on." }
        if occurrenceCount == 0 { return "No occurrences in this range." }
        return "\(occurrenceCount) session\(occurrenceCount == 1 ? "" : "s") of \(template.name) will be scheduled."
    }

    private func createSchedules() {
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) {
                let sched = WorkoutSchedule(date: current, template: template)
                context.insert(sched)
                WorkoutReminders.schedule(sched)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Date helper
extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Bool invert binding helper
extension Binding where Value == Bool {
    var not: Binding<Bool> {
        Binding<Bool>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
