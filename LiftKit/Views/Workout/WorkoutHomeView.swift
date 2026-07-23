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
    @ObservedObject private var store = StoreManager.shared

    @State private var showCalendarPicker = false
    @State private var showSeriesSchedule = false
    @State private var showUpcoming = false

    private var userProfile: UserProfile? { profiles.first }
    private var isPremium: Bool { store.isPro }

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

                    // Calendar (Pro only)
                    if isPremium {
                        WorkoutCalendarView(vm: vm)
                            .padding(.horizontal, LKSpacing.md)
                    } else {
                        lockedCalendarCard
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
                .readableWidth()
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
        .sheet(isPresented: $showSeriesSchedule) {
            SeriesScheduleSheet()
        }
        .sheet(isPresented: $showUpcoming) {
            UpcomingSchedulesView(vm: vm)
        }
        // Note: showWorkoutSetup / showActiveWorkout are presented at the root
        // (LiftKitApp.RootTabView) so only one presenter drives each binding.
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
                .font(LKFont.largeTitle)
                .foregroundColor(LKColor.textPrimary)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if store.isPro {
                proBadge
            } else {
                upgradePill
            }
        }
    }

    private var proBadge: some View {
        HStack(spacing: LKSpacing.xs) {
            Image(systemName: "crown.fill")
                .font(.system(size: 11))
                .foregroundColor(LKColor.accent)
            Text("Pro")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LKColor.textSecondary)
        }
        .padding(.horizontal, LKSpacing.sm)
        .padding(.vertical, LKSpacing.xs)
        .overlay(
            Capsule().strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
        )
        .accessibilityLabel("LiftKit Pro")
    }

    private var upgradePill: some View {
        Button {
            vm.paywallFeature = nil
            vm.showPaywall = true
            HapticManager.shared.buttonTap()
        } label: {
            HStack(spacing: LKSpacing.xs) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                Text("Upgrade")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(LKColor.accent)
            .padding(.horizontal, LKSpacing.sm)
            .padding(.vertical, LKSpacing.xs)
            .overlay(Capsule().strokeBorder(LKColor.accent.opacity(0.5), lineWidth: 1))
        }
        .accessibilityLabel("Upgrade to LiftKit Pro")
    }

    private var lockedCalendarCard: some View {
        Button {
            vm.paywallFeature = .scheduling
            vm.showPaywall = true
            HapticManager.shared.buttonTap()
        } label: {
            HStack(spacing: LKSpacing.md) {
                Image(systemName: "calendar")
                    .font(.system(size: 22))
                    .foregroundColor(LKColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: LKSpacing.xs) {
                        Text("Workout Calendar")
                            .font(LKFont.bodyBold)
                            .foregroundColor(LKColor.textPrimary)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(LKColor.textMuted)
                    }
                    Text("Schedule sessions ahead with LiftKit Pro.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LKColor.textMuted)
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
        .accessibilityLabel("Workout calendar, a Pro feature. Double tap to learn more.")
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
                    Menu {
                        Button {
                            showSeriesSchedule = true
                            HapticManager.shared.buttonTap()
                        } label: {
                            Label("Schedule a Series", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            showUpcoming = true
                            HapticManager.shared.buttonTap()
                        } label: {
                            Label("Manage Upcoming", systemImage: "calendar.badge.clock")
                        }
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
                    PlanCard(template: template, onTap: {
                        vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                        vm.markTemplateUsed(template, context: context)
                        vm.showWorkoutSetup = true
                    }, onToggleFavorite: {
                        template.isFavorite.toggle()
                        try? context.save()
                        HapticManager.shared.buttonTap()
                    })
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
                Button {
                    vm.paywallFeature = .plans
                    vm.showPaywall = true
                    HapticManager.shared.buttonTap()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: LKSpacing.xs) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16))
                            Text("Unlock unlimited plans")
                                .font(LKFont.bodyBold)
                        }
                        .foregroundColor(LKColor.accent)
                        Text("Your free plan holds \(UserProfile.maxFreeTemplates). Upgrade to LiftKit Pro for more.")
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(LKSpacing.md)
                    .background(LKColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: LKRadius.large)
                            .strokeBorder(LKColor.accent.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(LKRadius.large)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
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
            .accessibilityLabel("\(template.name), \(template.exercises.count) exercises")
            .accessibilityHint("Double tap to start this workout")

            Button(action: onToggleFavorite) {
                Image(systemName: template.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundColor(template.isFavorite ? LKColor.accent : LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(template.isFavorite ? "Unfavorite \(template.name)" : "Favorite \(template.name)")
        }
        .background(LKColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: LKRadius.large)
                .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
        )
        .cornerRadius(LKRadius.large)
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
                        PlanCard(template: template, onTap: {
                            vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                            vm.markTemplateUsed(template, context: context)
                            vm.showWorkoutSetup = true
                        }, onToggleFavorite: {
                            template.isFavorite.toggle()
                            try? context.save()
                            HapticManager.shared.buttonTap()
                        })
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
    @State private var search = ""
    @State private var weekdays: Set<Int> = []
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    private let cal = Calendar.current
    private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    private let maxTemplates = 5

    private var selected: [WorkoutTemplate] {
        selectedIDs.compactMap { id in templates.first { $0.id == id } }
    }

    /// While searching: matching plans. Otherwise: favorites + 5 most recent,
    /// plus any already-selected plans (so selections never vanish).
    private var visibleTemplates: [WorkoutTemplate] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return templates.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        let favorites = templates.filter { $0.isFavorite }
        let recent = Array(templates.prefix(5))   // templates already sorted most-recent first
        var seen = Set<UUID>()
        return (favorites + recent + selected).filter { seen.insert($0.id).inserted }
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
                    ForEach(visibleTemplates) { t in
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
                                if t.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(LKColor.accent)
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
                    Text("Pick up to \(maxTemplates). They rotate across your chosen days — e.g. A, B, A, B… Showing favorites and recent; search to find others.")
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
            .searchable(text: $search, prompt: "Search workouts")
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
        let seriesID = UUID()
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        var i = 0
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) {
                let sched = WorkoutSchedule(date: current, template: temps[i % temps.count], seriesID: seriesID)
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
        let seriesID = UUID()
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) {
                let sched = WorkoutSchedule(date: current, template: template, seriesID: seriesID)
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
