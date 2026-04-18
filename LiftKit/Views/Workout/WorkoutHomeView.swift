import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]

    @Bindable var vm: WorkoutViewModel

    @State private var showSetup = false
    @State private var showCalendarPicker = false

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
            .sheet(isPresented: $vm.showTypePicker) {
                WorkoutTypePickerView(vm: vm)
            }
            .sheet(isPresented: $vm.showTypePicker.not) {} // placeholder
            .sheet(isPresented: $showSetup) {
                WorkoutSetupView(vm: vm, type: vm.selectedTimerType)
            }
            .sheet(isPresented: $vm.showCreateWorkout) {
                CreateWorkoutView(vm: vm)
            }
            .sheet(isPresented: $vm.showLogin) {
                LoginView(vm: vm)
            }
            .fullScreenCover(isPresented: $vm.showActiveWorkout) {
                ActiveWorkoutView(vm: vm)
            }
            .onChange(of: vm.showTypePicker) { _, showing in
                if !showing && vm.selectedTimerType != vm.selectedTimerType {
                    // no-op placeholder
                }
            }
            .onAppear {
                vm.userProfile = userProfile
                ExerciseLibrary.shared.seedIfNeeded(context: context)
            }
        }
        // Listen for type selection → show setup sheet
        .onChange(of: vm.showTypePicker) { old, new in
            if old == true && new == false {
                showSetup = true
            }
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
                PlanCard(template: template) {
                    vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                    vm.markTemplateUsed(template, context: context)
                    vm.startTimedWorkout(context: context)
                }
                .padding(.horizontal, LKSpacing.md)
            }

            // Add button or upgrade prompt
            if isPremium || templates.count < UserProfile.maxFreeTemplates {
                Button {
                    vm.showCreateWorkout = true
                    HapticManager.shared.buttonTap()
                } label: {
                    HStack {
                        Image(systemName: "plus").foregroundColor(LKColor.accent)
                        Text("Add New Workout Plan")
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
                .padding(.horizontal, LKSpacing.md)

            } else if !isPremium {
                Text("Free accounts limited to 5 plans. Sign in for premium.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LKSpacing.md)

                // Show "all templates" button for premium with > 10
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
            .background(LKColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.large)
                    .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
            )
            .cornerRadius(LKRadius.large)
        }
        .buttonStyle(.plain)
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
                    PlanCard(template: template) {
                        vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
                        vm.markTemplateUsed(template, context: context)
                        vm.startTimedWorkout(context: context)
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
