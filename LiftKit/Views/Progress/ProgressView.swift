import SwiftUI
import SwiftData
import Charts

struct ProgressView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var personalRecords: [PersonalRecord]
    @Query private var exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var timeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable {
        case week  = "1W"
        case month = "1M"
        case threeMonths = "3M"
        case year  = "1Y"
        case all   = "All"

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.lg) {
                    if weekStreak > 0 { streakBanner }
                    overviewGrid
                    muscleFocusSection
                    prBoard
                    exerciseChart
                    weeklyVolume
                }
                .padding(.vertical, LKSpacing.md)
            }
            .navigationTitle("Progress")
            .background(LKColor.background.ignoresSafeArea())
        }
    }

    // MARK: - Streak

    /// Consecutive weeks (including the current one) with at least one completed
    /// workout. The current week not yet having a workout doesn't break it.
    private var weekStreak: Int {
        let cal = Calendar.current
        let weeks = Set(sessions.filter { !$0.isActive }
            .compactMap { cal.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start })
        guard !weeks.isEmpty, var cursor = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(cursor) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private var streakBanner: some View {
        HStack(spacing: LKSpacing.sm) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(LKColor.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(weekStreak) week\(weekStreak == 1 ? "" : "s") in a row")
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Text("Keep the streak going")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
            }
            Spacer()
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Muscle focus

    private struct MuscleSetCount: Identifiable {
        let muscle: MuscleGroup
        let sets: Int
        var id: String { muscle.rawValue }
    }

    /// Working-set count per muscle group over the last `days`, highest first.
    private func setsByMuscle(days: Int) -> [MuscleSetCount] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var counts: [MuscleGroup: Int] = [:]
        for session in sessions where !session.isActive && session.startedAt >= cutoff {
            for entry in session.entries {
                guard let m = entry.exercise?.primaryMuscle else { continue }
                counts[m, default: 0] += entry.sets.count
            }
        }
        return counts.sorted { $0.value > $1.value }.map { MuscleSetCount(muscle: $0.key, sets: $0.value) }
    }

    private var muscleFocusSection: some View {
        let data = setsByMuscle(days: 7)
        return VStack(alignment: .leading, spacing: LKSpacing.md) {
            Text("This Week by Muscle")
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)
                .padding(.horizontal, LKSpacing.md)

            if data.isEmpty {
                ContentUnavailableView(
                    "No Sets This Week",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Log a workout to see your muscle-group balance.")
                )
                .frame(height: 120)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Sets", item.sets),
                        y: .value("Muscle", item.muscle.label)
                    )
                    .foregroundStyle(LKColor.accent)
                    .annotation(position: .trailing) {
                        Text("\(item.sets)")
                            .font(.caption2)
                            .foregroundColor(LKColor.textMuted)
                    }
                }
                .chartXAxisLabel("Sets · last 7 days")
                .frame(height: CGFloat(data.count) * 34 + 40)
                .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    // MARK: - Overview
    private var overviewGrid: some View {
        let completed = sessions.filter { !$0.isActive }
        let totalVolume = completed.map(\.totalVolume).reduce(0, +)
        let avgDuration = completed.isEmpty ? 0 : completed.map(\.duration).reduce(0, +) / Double(completed.count)
        let prCount = Set(personalRecords.compactMap { $0.exercise?.name }).count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LKSpacing.md) {
            StatCard(icon: "figure.strengthtraining.traditional", value: "\(completed.count)", label: "Total Workouts", color: .blue)
            StatCard(icon: "scalemass.fill", value: "\(Int(totalVolume)) lb", label: "Total Volume", color: .green)
            StatCard(icon: "clock.fill", value: TimerEngine.format(avgDuration), label: "Avg Duration", color: .orange)
            StatCard(icon: "trophy.fill", value: "\(prCount)", label: "Personal Records", color: .yellow)
        }
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - PR Board
    private var prBoard: some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            Text("Personal Records")
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)
                .padding(.horizontal, LKSpacing.md)

            if personalRecords.isEmpty {
                ContentUnavailableView(
                    "No PRs Yet",
                    systemImage: "trophy.fill",
                    description: Text("Complete workouts to start setting records.")
                )
                .frame(height: 120)
            } else {
                let grouped = Dictionary(grouping: personalRecords) { $0.exercise?.name ?? "Unknown" }
                ForEach(grouped.keys.sorted(), id: \.self) { exName in
                    if let prs = grouped[exName] {
                        PRRow(exerciseName: exName, prs: prs)
                            .lkCard()
                            .padding(.horizontal, LKSpacing.md)
                    }
                }
            }
        }
    }

    // MARK: - Exercise Chart
    private var exerciseChart: some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            HStack {
                Text("Exercise Progress")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                Spacer()
                Menu {
                    ForEach(exercises, id: \.id) { ex in
                        Button(ex.name) { selectedExercise = ex }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedExercise?.name ?? "Select Exercise")
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(LKColor.accent)
                    }
                }
            }
            .padding(.horizontal, LKSpacing.md)

            if let exercise = selectedExercise {
                let data = chartData(for: exercise)
                if data.isEmpty {
                    noDataView(icon: "chart.line.downtrend.xyaxis")
                } else {
                    VStack(spacing: LKSpacing.sm) {
                        Picker("Range", selection: $timeRange) {
                            ForEach(TimeRange.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, LKSpacing.md)

                        // Estimated 1RM (Epley) from the best set in range
                        if let e1rm = data.map({ $0.weight * (1 + Double($0.reps) / 30.0) }).max(), e1rm > 0 {
                            HStack {
                                Text("Est. 1RM")
                                    .font(LKFont.caption)
                                    .foregroundColor(LKColor.textMuted)
                                Spacer()
                                Text("\(Int(e1rm.rounded())) lb")
                                    .font(LKFont.bodyBold)
                                    .foregroundColor(LKColor.accent)
                            }
                            .padding(.horizontal, LKSpacing.md)
                        }

                        // Weight chart
                        Chart {
                            ForEach(data, id: \.date) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.weight)
                                )
                                .foregroundStyle(Color.blue)
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.weight)
                                )
                                .foregroundStyle(Color.blue)
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal, LKSpacing.md)
                        .chartYAxisLabel("Weight (lb)")

                        // Reps chart
                        Chart {
                            ForEach(data, id: \.date) { point in
                                BarMark(
                                    x: .value("Date", point.date),
                                    y: .value("Reps", point.reps)
                                )
                                .foregroundStyle(Color.green.opacity(0.7))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 150)
                        .padding(.horizontal, LKSpacing.md)
                        .chartYAxisLabel("Best Reps")
                    }
                }
            } else {
                noDataView(icon: "chart.line.downtrend.xyaxis")
            }
        }
    }

    // MARK: - Weekly Volume
    private var weeklyVolume: some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            Text("Weekly Volume")
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)
                .padding(.horizontal, LKSpacing.md)

            let weeks = weeklyVolumeData()
            if weeks.isEmpty {
                noDataView(icon: "chart.bar")
            } else {
                Chart {
                    ForEach(weeks, id: \.week) { item in
                        BarMark(
                            x: .value("Week", item.week),
                            y: .value("Volume", item.volume)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .blue.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        )
                        .cornerRadius(6)
                    }
                }
                .frame(height: 180)
                .padding(.horizontal, LKSpacing.md)
                .chartYAxisLabel("Volume (lb)")
            }
        }
    }

    // MARK: - Helpers

    private struct ChartPoint {
        let date: Date
        let weight: Double
        let reps: Int
    }

    private func chartData(for exercise: Exercise) -> [ChartPoint] {
        let cutoff: Date
        if let days = timeRange.days {
            cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        } else {
            cutoff = .distantPast
        }

        return exercise.entries
            .filter { !($0.session?.isActive ?? false) }
            .flatMap { $0.sets }
            .filter { $0.completedAt >= cutoff }
            .compactMap { set -> ChartPoint? in
                guard let w = set.weight, let r = set.reps else { return nil }
                let lbs = set.weightUnitEnum == .kg ? w * 2.20462 : w
                return ChartPoint(date: set.completedAt, weight: lbs, reps: r)
            }
            .sorted { $0.date < $1.date }
    }

    private struct WeekVolume {
        let week: String
        let volume: Double
    }

    private func weeklyVolumeData() -> [WeekVolume] {
        let cal = Calendar.current
        let now = Date()
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return (0..<8).compactMap { weekOffset -> WeekVolume? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeekStart),
                  let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return nil }
            let vol = sessions
                .filter { !$0.isActive && $0.startedAt >= weekStart && $0.startedAt < weekEnd }
                .map(\.totalVolume).reduce(0, +)
            return WeekVolume(week: formatter.string(from: weekStart), volume: vol)
        }
        .reversed()
    }

    private func noDataView(icon: String) -> some View {
        ContentUnavailableView("No Data", systemImage: icon)
            .frame(height: 120)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: LKSpacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(LKColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
    }
}

// MARK: - PR Row
struct PRRow: View {
    let exerciseName: String
    let prs: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text(exerciseName)
                .font(.headline)
                .foregroundColor(LKColor.textPrimary)

            HStack(spacing: LKSpacing.md) {
                ForEach(PRType.allCases) { type in
                    if let pr = prs.filter({ $0.prType == type }).max(by: { $0.value < $1.value }) {
                        VStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                            Text("\(Int(pr.value)) \(type.shortLabel)")
                                .font(LKFont.caption)
                                .foregroundColor(LKColor.textPrimary)
                            Text(type.label)
                                .font(.system(size: 10))
                                .foregroundColor(LKColor.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
