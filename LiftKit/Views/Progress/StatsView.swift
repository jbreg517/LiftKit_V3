import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var personalRecords: [PersonalRecord]
    @Query private var exercises: [Exercise]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]

    @State private var selectedExercise: Exercise?
    @State private var timeRange: TimeRange = .month
    /// One range for the whole training block — load, sets and volume share it, so the
    /// three charts are always describing the same weeks. That shared x-axis is what
    /// turns three unrelated pictures into one story.
    @State private var trainingWeeks: TrainingWeeks = .twelve
    /// The muscle group drilled into, or nil for the four-row overview.
    @State private var expandedRegion: MuscleRegion?
    @AppStorage("unitSystem") private var unitSystemRaw = "imperial"
    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .imperial }

    enum TrainingWeeks: Int, CaseIterable, Identifiable {
        case eight = 8, twelve = 12, twentySix = 26
        var id: Int { rawValue }
        var label: String { "\(rawValue)w" }
    }

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
                    // One block, one week axis, three lenses on the same weeks: how
                    // hard (load), where it went (sets), what moved (volume).
                    trainingHeader
                    trainingLoadSection
                    muscleTrendSection
                    weeklyVolume
                    bodyMetricsCard
                    prBoard
                    exerciseChart
                }
                .padding(.vertical, LKSpacing.md)
                .readableWidth()
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

    // MARK: - Training block

    /// One range control for load, sets and volume. Kept out of the individual chart
    /// headers on purpose: three separate pickers invite three different ranges, and
    /// comparing charts across mismatched windows is how someone reads a story that
    /// isn't there.
    private var trainingHeader: some View {
        HStack {
            Text("TRAINING")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(1.5)
            Spacer()
            Picker("Weeks", selection: $trainingWeeks) {
                ForEach(TrainingWeeks.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Training load

    private var dayLoads: [TrainingLoad.DayLoad] { TrainingLoad.dailyLoads(sessions) }
    private var weekLoads: [TrainingLoad.WeekLoad] {
        TrainingLoad.weeklyLoads(sessions, weeks: trainingWeeks.rawValue)
    }

    /// The section is **absent**, not empty, until there's a rating to show. A chart of
    /// zeroes would read as "you did nothing" when it actually means "nobody answered
    /// the question".
    @ViewBuilder
    private var trainingLoadSection: some View {
        let weeks = weekLoads
        if weeks.contains(where: { $0.ratedSessions > 0 }) {
            let rated = weeks.reduce(0) { $0 + $1.ratedSessions }
            let total = weeks.reduce(0) { $0 + $1.sessions }
            let thisWeek = weeks.last
            let ratio = TrainingLoad.acuteChronicRatio(dayLoads)

            VStack(alignment: .leading, spacing: LKSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Load")
                        .font(LKFont.heading)
                        .foregroundColor(LKColor.textPrimary)
                    Text("Session RPE × active minutes, in arbitrary units")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                }
                .padding(.horizontal, LKSpacing.md)

                Chart(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Load", week.srpe)
                    )
                    .foregroundStyle(LKColor.accent)
                    .accessibilityLabel(week.weekStart.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(Int(week.srpe.rounded())) AU")
                }
                .chartYAxisLabel("AU")
                .frame(height: 160)
                .padding(.horizontal, LKSpacing.md)

                HStack(spacing: LKSpacing.md) {
                    loadStat("This week", value: "\(Int((thisWeek?.srpe ?? 0).rounded()))", unit: "AU")
                    loadStat("vs 4-week avg",
                             value: ratio.map { String(format: "%.2f", $0) } ?? "—",
                             unit: ratio == nil ? "needs 4 weeks" : "×")
                    loadStat("Sessions rated", value: "\(rated)", unit: "of \(total)")
                }
                .padding(.horizontal, LKSpacing.md)

                if rated < total {
                    Text("\(total - rated) session\(total - rated == 1 ? "" : "s") in this window had no effort rating, so the bars are lower than the training you actually did. You can add a rating to any past workout in History.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .padding(.horizontal, LKSpacing.md)
                }
            }
        }
    }

    private func loadStat(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(1)
            Text(value)
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textPrimary)
            Text(unit)
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hard sets by group

    /// One week's value on one line. A named type rather than a `(Date, Double)` pair
    /// because `ForEach` needs `Identifiable` or a key path, and Swift has no key paths
    /// into tuple members.
    private struct SeriesPoint: Identifiable {
        let weekStart: Date
        let sets: Double
        var id: Date { weekStart }
    }

    /// Recomputed on access, so it is read **once per render** and passed down. Every
    /// call walks every session's every set; fetching it per row turned one pass into
    /// fifteen.
    private var hardSetWeeks: [TrainingLoad.HardSetWeek] {
        TrainingLoad.weeklyHardSets(sessions, weeks: trainingWeeks.rawValue)
    }

    /// The four planning blocks, plus `other` only when it holds work — dropping
    /// whole-body and untagged sets silently would make the rows disagree with the
    /// session totals.
    private func visibleRegions(in weeks: [TrainingLoad.HardSetWeek]) -> [MuscleRegion] {
        var regions = MuscleRegion.primary
        if weeks.contains(where: { $0.sets(for: MuscleRegion.other) > 0 }) { regions.append(.other) }
        return regions
    }

    private func points(in weeks: [TrainingLoad.HardSetWeek], for region: MuscleRegion) -> [SeriesPoint] {
        weeks.map { SeriesPoint(weekStart: $0.weekStart, sets: $0.sets(for: region)) }
    }

    @ViewBuilder
    private var muscleTrendSection: some View {
        let weeks = hardSetWeeks
        if weeks.contains(where: { $0.total > 0 }) {
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                HStack {
                    Text("Hard Sets by Group")
                        .font(LKFont.heading)
                        .foregroundColor(LKColor.textPrimary)
                    Spacer()
                    if expandedRegion != nil {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) { expandedRegion = nil }
                        }
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.accent)
                    }
                }
                .padding(.horizontal, LKSpacing.md)

                if let region = expandedRegion {
                    expandedRegionChart(region, weeks: weeks)
                } else {
                    ForEach(visibleRegions(in: weeks)) { region in
                        regionRow(region, weeks: weeks)
                    }
                    Text("Warm-ups don't count, and neither does anything you rated below 5. Tap a group to see the muscles in it.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .padding(.horizontal, LKSpacing.md)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                Text("Hard Sets by Group")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                    .padding(.horizontal, LKSpacing.md)
                ContentUnavailableView(
                    "No Sets Logged",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Log a workout to see where your training is going. Warm-up sets aren't counted.")
                )
                .frame(height: 120)
            }
        }
    }

    /// One collapsed row: name, total, change, and a compact line.
    private func regionRow(_ region: MuscleRegion, weeks: [TrainingLoad.HardSetWeek]) -> some View {
        let series = points(in: weeks, for: region)
        let total = series.reduce(0) { $0 + $1.sets }
        let change = TrainingLoad.halfOverHalfChange(series.map(\.sets))

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { expandedRegion = region }
        } label: {
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(region.label)
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textPrimary)
                    Spacer()
                    Text(setsText(total))
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                    changeBadge(change)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(LKColor.textMuted)
                }
                sparkline(series)
                    .frame(height: 44)
            }
            .padding(LKSpacing.sm)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.medium)
            .padding(.horizontal, LKSpacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.label), \(setsText(total)) over \(trainingWeeks.rawValue) weeks")
        .accessibilityHint("Shows the muscles in this group")
    }

    /// Line with a point per week. Axes hidden — at this size they'd be unreadable, and
    /// the numbers that matter are already in the row header.
    private func sparkline(_ series: [SeriesPoint]) -> some View {
        let peak = series.map(\.sets).max() ?? 0
        return Chart(series) { point in
            LineMark(x: .value("Week", point.weekStart), y: .value("Sets", point.sets))
                .foregroundStyle(LKColor.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Week", point.weekStart), y: .value("Sets", point.sets))
                .foregroundStyle(LKColor.accent)
                .symbolSize(18)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // Anchored at zero so the shape means something. Left to auto-scale from its own
        // minimum, a group holding a steady 9–10 sets would draw the same dramatic
        // zigzag as one swinging 0–20.
        .chartYScale(domain: 0...max(1, peak * 1.15))
    }

    /// The drill-down: every muscle in the group as its own line.
    private func expandedRegionChart(_ region: MuscleRegion,
                                     weeks: [TrainingLoad.HardSetWeek]) -> some View {
        let series = points(in: weeks, for: region)
        let total = series.reduce(0) { $0 + $1.sets }
        let change = TrainingLoad.halfOverHalfChange(series.map(\.sets))
        // Only the muscles actually trained — an empty line for every untrained muscle
        // is legend clutter, and its absence is already visible in the group total.
        let muscles = region.muscles.filter { muscle in
            weeks.contains { $0.sets(for: muscle) > 0 }
        }

        return VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(region.label)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Spacer()
                Text(setsText(total))
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                changeBadge(change)
            }

            if muscles.isEmpty {
                Text("Nothing logged for this group in the last \(trainingWeeks.rawValue) weeks.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .frame(height: 100)
            } else {
                Chart {
                    ForEach(muscles) { muscle in
                        ForEach(weeks) { week in
                            LineMark(
                                x: .value("Week", week.weekStart),
                                y: .value("Sets", week.sets(for: muscle)),
                                series: .value("Muscle", muscle.label)
                            )
                            .foregroundStyle(by: .value("Muscle", muscle.label))
                            .interpolationMethod(.monotone)
                            PointMark(
                                x: .value("Week", week.weekStart),
                                y: .value("Sets", week.sets(for: muscle))
                            )
                            .foregroundStyle(by: .value("Muscle", muscle.label))
                            .symbolSize(28)
                        }
                    }
                    // Per muscle, so it belongs here and not on the group rows, where
                    // "Push" spans three muscles and the line would sit three times low.
                    RuleMark(y: .value("Reference", TrainingLoad.referenceSetsPerMuscleWeek))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(LKColor.textMuted)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("10/wk")
                                .font(.caption2)
                                .foregroundColor(LKColor.textMuted)
                        }
                }
                .frame(height: 220)
                .chartYAxisLabel("Hard sets")
                .chartLegend(position: .bottom, spacing: LKSpacing.xs)

                Text("The dashed line marks 10 sets a week per muscle — a figure often cited in the training literature, not a target LiftKit sets for you.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
            }
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
        .padding(.horizontal, LKSpacing.md)
    }

    private func setsText(_ sets: Double) -> String {
        let rounded = (sets * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(text) sets"
    }

    /// Second half of the window against the first, as a percentage.
    ///
    /// A direction and a number, never a colour that implies a verdict — a fall in
    /// pull volume is a deload to one lifter and neglect to another, and the chart
    /// can't tell which.
    @ViewBuilder
    private func changeBadge(_ change: Double?) -> some View {
        if let change {
            let up = change >= 0
            HStack(spacing: 1) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(Int(change.rounded())))%")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(LKColor.textSecondary)
        } else {
            Text("—")
                .font(.caption2)
                .foregroundColor(LKColor.textMuted)
        }
    }

    // MARK: - Body metrics entry
    private var bodyMetricsCard: some View {
        let latestWeight = bodyMetrics
            .filter { $0.type == .bodyweight }
            .max(by: { $0.date < $1.date })
        return NavigationLink(destination: BodyTrackingView()) {
            HStack(spacing: LKSpacing.md) {
                Image(systemName: "figure.arms.open")
                    .font(.title2)
                    .foregroundColor(LKColor.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Metrics")
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textPrimary)
                    Text(latestWeight.map { "Bodyweight \(Int(units.weightFromLb($0.value).rounded())) \(units.weightLabel)" }
                         ?? "Track bodyweight & measurements")
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
        .buttonStyle(.plain)
    }

    // MARK: - Overview
    private var overviewGrid: some View {
        let completed = sessions.filter { !$0.isActive }
        let totalVolume = completed.map(\.totalVolume).reduce(0, +)
        let avgDuration = completed.isEmpty ? 0 : completed.map(\.duration).reduce(0, +) / Double(completed.count)
        let prCount = Set(personalRecords.compactMap { $0.exercise?.name }).count
        let totalTime = completed.map(\.duration).reduce(0, +)
        let totalTimeLabel = totalTime >= 3600 ? "\(Int((totalTime / 3600).rounded()))h" : "\(Int((totalTime / 60).rounded()))m"
        let totalRounds = completed.compactMap(\.roundsCompleted).reduce(0, +)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LKSpacing.md) {
            StatCard(icon: "figure.strengthtraining.traditional", value: "\(completed.count)", label: "Total Workouts", color: .blue)
            StatCard(icon: "scalemass.fill", value: "\(Int(units.weightFromLb(totalVolume))) \(units.weightLabel)", label: "Total Volume", color: .green)
            StatCard(icon: "clock.fill", value: TimerEngine.format(avgDuration), label: "Avg Duration", color: .orange)
            StatCard(icon: "trophy.fill", value: "\(prCount)", label: "Personal Records", color: .yellow)
            StatCard(icon: "timer", value: totalTimeLabel, label: "Total Time", color: .teal)
            StatCard(icon: "arrow.triangle.2.circlepath", value: "\(totalRounds)", label: "Rounds Done", color: .indigo)
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
                                Text("\(Int(e1rm.rounded())) \(units.weightLabel)")
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
                                .foregroundStyle(LKColor.accent)
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.weight)
                                )
                                .foregroundStyle(LKColor.accent)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(Int(point.weight)) \(units.weightLabel)")
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal, LKSpacing.md)
                        .chartYAxisLabel("Weight (\(units.weightLabel))")

                        // Reps chart
                        Chart {
                            ForEach(data, id: \.date) { point in
                                BarMark(
                                    x: .value("Date", point.date),
                                    y: .value("Reps", point.reps)
                                )
                                .foregroundStyle(LKColor.success.opacity(0.85))
                                .cornerRadius(4)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(point.reps) reps")
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

    /// Tonnage, third and last on purpose.
    ///
    /// Volume load is dominated by exercise selection — a squat week and a curl week
    /// aren't comparable — so it's the weakest of the three signals and sits below the
    /// two that aren't. It stays because "how much did I move" is a question people
    /// genuinely want answered, and because the group chart above it now supplies the
    /// context that makes a swing interpretable: a tonnage jump next to a Legs jump is a
    /// different fact from a tonnage jump on its own.
    ///
    /// Absorbs the old standalone 30-day volume card. That card showed the same quantity
    /// as this chart with a different window, which meant two numbers on one screen
    /// disagreeing about how volume was going.
    private var weeklyVolume: some View {
        let weeks = weeklyVolumeData()
        let values = weeks.map(\.volume)
        let change = TrainingLoad.halfOverHalfChange(values)
        return VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight Moved")
                    .font(LKFont.heading)
                    .foregroundColor(LKColor.textPrimary)
                Spacer()
                Text("\(Int(units.weightFromLb(values.reduce(0, +)).rounded())) \(units.weightLabel)")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                changeBadge(change)
            }
            .padding(.horizontal, LKSpacing.md)

            if values.allSatisfy({ $0 == 0 }) {
                noDataView(icon: "chart.bar")
            } else {
                Chart {
                    ForEach(weeks) { item in
                        BarMark(
                            x: .value("Week", item.weekStart, unit: .weekOfYear),
                            y: .value("Volume", units.weightFromLb(item.volume))
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [LKColor.accent, LKColor.accent.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        )
                        .cornerRadius(4)
                        .accessibilityLabel(item.weekStart.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(Int(units.weightFromLb(item.volume))) \(units.weightLabel)")
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, LKSpacing.md)
                .chartYAxisLabel("Volume (\(units.weightLabel))")

                Text("Sets × weight, so this follows what you chose to train as much as how hard you trained — a leg week outweighs an arm week either way. Read it next to the groups above.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
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
                return ChartPoint(date: set.completedAt, weight: units.weightFromLb(lbs), reps: r)
            }
            .sorted { $0.date < $1.date }
    }

    private struct WeekVolume: Identifiable {
        let weekStart: Date
        let volume: Double
        var id: Date { weekStart }
    }

    /// Weekly tonnage over the shared window.
    ///
    /// Keyed on the week's **start date** rather than a formatted "MM/dd" string, which
    /// is what it used to be. A string axis can't line up with the load and set charts
    /// above, and lining the three up is the whole point of the block.
    private func weeklyVolumeData() -> [WeekVolume] {
        let cal = Calendar.current
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<trainingWeeks.rawValue).compactMap { weekOffset -> WeekVolume? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeekStart),
                  let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return nil }
            let vol = sessions
                .filter { !$0.isActive && $0.startedAt >= weekStart && $0.startedAt < weekEnd }
                .map(\.totalVolume).reduce(0, +)
            return WeekVolume(weekStart: weekStart, volume: vol)
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
