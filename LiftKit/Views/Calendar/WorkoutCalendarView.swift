import SwiftUI
import SwiftData

// Identifies what the schedule-edit sheet should show. Building the target at
// tap time (not inside the sheet builder) makes presentation reliable.
struct ScheduleEditTarget: Identifiable {
    let id = UUID()
    let schedule: WorkoutSchedule
    let isNew: Bool
}

struct WorkoutCalendarView: View {
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutSchedule.date)     private var schedules: [WorkoutSchedule]

    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var showDatePicker = false
    @State private var scheduleEditTarget: ScheduleEditTarget?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: LKSpacing.sm) {
            monthHeader
            dayOfWeekRow
            calendarGrid
            if let date = selectedDate {
                selectedDateInfo(date: date)
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(item: $scheduleEditTarget) { target in
            ScheduleEditView(schedule: target.schedule, vm: vm, isNew: target.isNew)
        }
    }

    // MARK: - Month Header
    private var monthHeader: some View {
        HStack {
            Button {
                currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LKColor.textSecondary)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Button {
                showDatePicker = true
            } label: {
                Text(monthYearString)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
            }

            Spacer()

            Button {
                currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LKColor.textSecondary)
            }
            .accessibilityLabel("Next month")
        }
    }

    // MARK: - Day of Week Row
    private var dayOfWeekRow: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { i in
                Text(symbols[i])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(LKColor.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    dayCell(date: date)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func dayCell(date: Date) -> some View {
        let isToday    = calendar.isDateInToday(date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let hasHistory  = sessions.contains { !$0.isActive && calendar.isDate($0.startedAt, inSameDayAs: date) }
        let incompleteSchedule = schedules.contains { !$0.isCompleted && calendar.isDate($0.date, inSameDayAs: date) }
        let isPast = calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
        let isPastDue  = incompleteSchedule && isPast
        let isUpcoming = incompleteSchedule && !isPast

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = isSelected ? nil : date
            }
            HapticManager.shared.buttonTap()
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? LKColor.accent : LKColor.textPrimary)

                HStack(spacing: 3) {
                    if hasHistory {
                        Circle()
                            .fill(LKColor.accent)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Completed workout")
                    }
                    if isUpcoming {
                        Circle()
                            .fill(LKColor.work)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Scheduled workout")
                    }
                    if isPastDue {
                        Circle()
                            .fill(LKColor.textMuted)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Missed workout")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                Group {
                    if isSelected {
                        LKColor.accent.opacity(0.2)
                    } else if isToday {
                        LKColor.surfaceElevated
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Date Info
    private func selectedDateInfo(date: Date) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            let daySessions = sessions.filter { !$0.isActive && calendar.isDate($0.startedAt, inSameDayAs: date) }
            let daySchedules = schedules.filter { calendar.isDate($0.date, inSameDayAs: date) }

            ForEach(daySessions) { session in
                NavigationLink(destination: WorkoutDetailView(session: session, vm: vm)) {
                    HStack {
                        Circle().fill(LKColor.accent).frame(width: 8, height: 8)
                        Text(session.name)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(LKColor.textMuted)
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(daySchedules) { sched in
                let overdue = !sched.isCompleted && calendar.startOfDay(for: sched.date) < calendar.startOfDay(for: Date())
                let statusColor: Color = sched.isCompleted ? LKColor.accent : (overdue ? LKColor.textMuted : LKColor.work)
                let statusText = sched.isCompleted ? "Done" : (overdue ? "Overdue" : "Planned")
                Button {
                    scheduleEditTarget = ScheduleEditTarget(schedule: sched, isNew: false)
                } label: {
                    HStack {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(sched.displayName)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textPrimary)
                        Spacer()
                        Text(statusText)
                            .font(LKFont.caption)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }

            if daySessions.isEmpty && daySchedules.isEmpty {
                Button {
                    scheduleEditTarget = ScheduleEditTarget(
                        schedule: WorkoutSchedule(date: date), isNew: true
                    )
                } label: {
                    Label("Schedule Workout", systemImage: "plus")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.accent)
                }
            }
        }
        .padding(.top, LKSpacing.sm)
    }

    // MARK: - Date Picker Sheet
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Select Month", selection: $currentMonth, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(LKColor.accent)
                .padding()
                .navigationTitle("Go to Month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDatePicker = false }
                    }
                }
        }
    }

    // MARK: - Helpers
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        var days: [Date?] = []
        var current = monthFirstWeek.start

        while current < monthInterval.end || days.count % 7 != 0 {
            if current >= monthInterval.start && current < monthInterval.end {
                days.append(current)
            } else {
                days.append(nil)
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            if days.count > 42 { break }
        }
        return days
    }
}

// MARK: - Upcoming Schedules
//
// A flat, manageable list of everything still ahead. Recurring series (sharing a
// `seriesID`) collapse into one expandable row that can be cancelled as a unit;
// one-off schedules are listed individually. Editing/deleting a single occurrence
// reuses the same `ScheduleEditView` the calendar uses. Reached from the
// "Schedule ▸ Manage Upcoming" menu on the Workout home.
struct UpcomingSchedulesView: View {
    @Bindable var vm: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSchedule.date) private var allSchedules: [WorkoutSchedule]

    @State private var editTarget: ScheduleEditTarget?
    @State private var seriesToCancel: SeriesGroup?

    private let cal = Calendar.current
    private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private struct SeriesGroup: Identifiable {
        let id: UUID
        let schedules: [WorkoutSchedule]
    }

    // MARK: Derived

    private var upcoming: [WorkoutSchedule] {
        let today = cal.startOfDay(for: Date())
        return allSchedules.filter { !$0.isCompleted && cal.startOfDay(for: $0.date) >= today }
    }
    private var seriesGroups: [SeriesGroup] {
        let withSeries = upcoming.filter { $0.seriesID != nil }
        return Dictionary(grouping: withSeries) { $0.seriesID! }
            .map { SeriesGroup(id: $0.key, schedules: $0.value.sorted { $0.date < $1.date }) }
            .sorted { ($0.schedules.first?.date ?? .distantFuture) < ($1.schedules.first?.date ?? .distantFuture) }
    }
    private var oneOffs: [WorkoutSchedule] {
        upcoming.filter { $0.seriesID == nil }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if upcoming.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Workouts",
                        systemImage: "calendar",
                        description: Text("Schedule a series and it’ll show up here to edit or cancel."))
                } else {
                    List {
                        if !seriesGroups.isEmpty {
                            Section("Recurring Series") {
                                ForEach(seriesGroups) { group in
                                    DisclosureGroup {
                                        ForEach(group.schedules) { sched in
                                            occurrenceRow(sched)
                                                .swipeActions(edge: .trailing) {
                                                    Button(role: .destructive) { deleteSchedule(sched) } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                }
                                        }
                                    } label: {
                                        seriesLabel(group)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { seriesToCancel = group } label: {
                                            Label("Cancel Series", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        if !oneOffs.isEmpty {
                            Section(seriesGroups.isEmpty ? "Upcoming" : "One-off") {
                                ForEach(oneOffs) { sched in
                                    occurrenceRow(sched)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { deleteSchedule(sched) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Upcoming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editTarget) { target in
                ScheduleEditView(schedule: target.schedule, vm: vm, isNew: target.isNew)
            }
            .confirmationDialog(
                "Cancel this series?",
                isPresented: Binding(get: { seriesToCancel != nil },
                                     set: { if !$0 { seriesToCancel = nil } }),
                presenting: seriesToCancel
            ) { group in
                Button("Cancel \(group.schedules.count) Upcoming", role: .destructive) {
                    cancelSeries(group)
                    seriesToCancel = nil
                }
                Button("Keep", role: .cancel) { seriesToCancel = nil }
            } message: { group in
                Text("Removes the \(group.schedules.count) upcoming session\(group.schedules.count == 1 ? "" : "s") in this series and their reminders. Past workouts are kept.")
            }
        }
    }

    // MARK: Rows

    private func seriesLabel(_ group: SeriesGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(planNames(group.schedules))
                .font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
            Text("\(weekdaySummary(group.schedules)) · \(group.schedules.count) left · ends \(shortDate(group.schedules.map(\.date).max() ?? Date()))")
                .font(LKFont.caption).foregroundColor(LKColor.textMuted)
        }
    }

    private func occurrenceRow(_ sched: WorkoutSchedule) -> some View {
        Button {
            editTarget = ScheduleEditTarget(schedule: sched, isNew: false)
        } label: {
            HStack {
                Text(sched.displayName).font(LKFont.body).foregroundColor(LKColor.textPrimary)
                Spacer()
                Text(rowDate(sched.date)).font(LKFont.caption).foregroundColor(LKColor.textMuted)
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(LKColor.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Mutations

    private func deleteSchedule(_ sched: WorkoutSchedule) {
        WorkoutReminders.cancel(sched)
        context.delete(sched)
        try? context.save()
    }
    private func cancelSeries(_ group: SeriesGroup) {
        for s in group.schedules {
            WorkoutReminders.cancel(s)
            context.delete(s)
        }
        try? context.save()
    }

    // MARK: Formatting

    /// Distinct plan names in first-seen order (a rotation reads "A → B → C").
    private func planNames(_ schedules: [WorkoutSchedule]) -> String {
        var seen = Set<String>()
        return schedules.map(\.displayName).filter { seen.insert($0).inserted }.joined(separator: " → ")
    }
    private func weekdaySummary(_ schedules: [WorkoutSchedule]) -> String {
        Set(schedules.map { cal.component(.weekday, from: $0.date) }).sorted()
            .map { weekdayLabels[$0 - 1] }.joined(separator: "/")
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    private func rowDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
