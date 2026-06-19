import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]

    @Bindable var vm: WorkoutViewModel

    @State private var showCalendarPicker = false
    @State private var scheduleTemplate: WorkoutTemplate?

    private var userProfile: UserProfile? { profiles.first }
    private var isPremium: Bool { userProfile?.isPremium ?? false }

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
            }
        }
        .sheet(isPresented: $vm.showTypePicker) {
            WorkoutTypePickerView(vm: vm)
        }
        .sheet(isPresented: $vm.showCreateWorkout) {
            CreateWorkoutView(vm: vm)
        }
        .sheet(isPresented: $vm.showWorkoutSetup) {
            NavigationStack {
                WorkoutSetupView(vm: vm, type: vm.selectedTimerType)
            }
        }
        .sheet(isPresented: $vm.showLogin) {
            LoginView(vm: vm)
        }
        .sheet(item: $scheduleTemplate) { template in
            RecurringScheduleSheet(template: template)
        }
        .fullScreenCover(isPresented: $vm.showActiveWorkout) {
            ActiveWorkoutView(vm: vm)
        }
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

    // MARK: - Plans section
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("YOUR WORKOUT PLANS")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(2)
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
                    } onSchedule: {
                        scheduleTemplate = template
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

// MARK: - Plan Card
struct PlanCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void
    let onSchedule: () -> Void

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
                    VStack(alignment: .trailing, spacing: LKSpacing.xs) {
                        Text(template.lastUsedAt.relativeFormatted)
                            .font(.system(size: 12))
                            .foregroundColor(LKColor.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(LKColor.textMuted)
                    }
                }
                .padding(LKSpacing.md)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(template.name), \(template.exercises.count) exercises")
            .accessibilityHint("Double tap to start this workout")

            Button(action: onSchedule) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 16))
                    .foregroundColor(LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schedule \(template.name)")
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
    @State private var scheduleTemplate: WorkoutTemplate?

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
                        } onSchedule: {
                            scheduleTemplate = template
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
        .sheet(item: $scheduleTemplate) { template in
            RecurringScheduleSheet(template: template)
        }
    }
}

// MARK: - Recurring Schedule Sheet

struct RecurringScheduleSheet: View {
    let template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var selectedWeekdays: Set<Int> = []
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    private let cal = Calendar.current
    // weekday 1=Sun … 7=Sat, labels align to that
    private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    var body: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.lg) {

                // Day toggles
                VStack(alignment: .leading, spacing: LKSpacing.sm) {
                    Text("REPEAT ON")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .tracking(1.5)

                    HStack(spacing: LKSpacing.xs) {
                        ForEach(1...7, id: \.self) { weekday in
                            let label    = weekdayLabels[weekday - 1]
                            let selected = selectedWeekdays.contains(weekday)
                            Button {
                                if selected { selectedWeekdays.remove(weekday) }
                                else        { selectedWeekdays.insert(weekday) }
                                HapticManager.shared.buttonTap()
                            } label: {
                                Text(label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, LKSpacing.sm)
                                    .background(selected ? LKColor.accent : LKColor.surfaceElevated)
                                    .foregroundColor(selected ? .black : LKColor.textSecondary)
                                    .cornerRadius(LKRadius.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Date range
                VStack(spacing: 0) {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .tint(LKColor.accent)
                        .padding(.vertical, LKSpacing.sm)
                    Divider()
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .tint(LKColor.accent)
                        .padding(.vertical, LKSpacing.sm)
                }
                .padding(.horizontal, LKSpacing.md)
                .background(LKColor.surface)
                .cornerRadius(LKRadius.large)

                // Count hint
                let count = occurrenceCount
                Text(
                    selectedWeekdays.isEmpty ? "Select days above" :
                    count == 0              ? "No occurrences in this range" :
                    "\(count) workout\(count == 1 ? "" : "s") will be scheduled"
                )
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)

                Button("Schedule") { createSchedules() }
                    .buttonStyle(LKPrimaryButtonStyle())
                    .disabled(count == 0)

                Spacer()
            }
            .padding(LKSpacing.md)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LKColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var occurrenceCount: Int {
        guard !selectedWeekdays.isEmpty else { return 0 }
        var count = 0
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if selectedWeekdays.contains(cal.component(.weekday, from: current)) { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return count
    }

    private func createSchedules() {
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while current <= end {
            if selectedWeekdays.contains(cal.component(.weekday, from: current)) {
                let sched = WorkoutSchedule(date: current, template: template)
                context.insert(sched)
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
