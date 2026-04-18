import SwiftUI
import SwiftData

struct WorkoutCalendarView: View {
    @Bindable var vm: WorkoutViewModel
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutSchedule.date)     private var schedules: [WorkoutSchedule]

    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var showDatePicker = false
    @State private var showScheduleEdit = false
    @State private var editingSchedule: WorkoutSchedule?

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
        .sheet(isPresented: $showScheduleEdit) {
            if let sched = editingSchedule {
                ScheduleEditView(schedule: sched, vm: vm)
            } else {
                // New schedule for selected date
                let newSched = WorkoutSchedule(date: selectedDate ?? Date())
                ScheduleEditView(schedule: newSched, vm: vm)
            }
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
        HStack(spacing: 0) {
            ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(LKColor.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(daysInMonth, id: \.self) { date in
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
        let hasSchedule = schedules.contains { !$0.isCompleted && calendar.isDate($0.date, inSameDayAs: date) }

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
                    if hasSchedule {
                        Circle()
                            .fill(LKColor.work)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Scheduled workout")
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
                Button {
                    vm.showActiveWorkout = false
                } label: {
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
                Button {
                    editingSchedule = sched
                    showScheduleEdit = true
                } label: {
                    HStack {
                        Circle().fill(LKColor.work).frame(width: 8, height: 8)
                        Text(sched.displayName)
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textPrimary)
                        Spacer()
                        Text("Planned")
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.work)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(LKColor.work.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }

            if daySessions.isEmpty && daySchedules.isEmpty {
                Button {
                    editingSchedule = nil
                    showScheduleEdit = true
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
            if calendar.isDate(current, equalTo: monthInterval.start, toGranularity: .month) ||
               calendar.isDate(current, equalTo: monthInterval.end, toGranularity: .month) ||
               (current >= monthInterval.start && current < monthInterval.end) {
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
