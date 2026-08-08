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
    /// In the drill-down, the muscle whose line is isolated (others dimmed), or nil.
    /// Driven by tapping a legend chip.
    @State private var focusedMuscle: String?
    /// Scrub position on the exercise weight chart — the nearest logged point is
    /// called out. Interactivity belongs to this detail chart, not the sparklines.
    @State private var scrubDate: Date?
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
            // "Your typical" band = interquartile range of non-zero weeks, so a bar
            // above it reads as a harder-than-usual week (Whoop/Oura-style baseline,
            // computed from the user's own data — not an external prescription).
            let typicalBand: (lo: Double, hi: Double)? = {
                let loads = weeks.map(\.srpe).filter { $0 > 0 }.sorted()
                guard loads.count >= 4 else { return nil }
                return (loads[loads.count / 4], loads[(loads.count * 3) / 4])
            }()

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

                Chart {
                    if let typicalBand {
                        RectangleMark(
                            yStart: .value("Typical low", typicalBand.lo),
                            yEnd: .value("Typical high", typicalBand.hi)
                        )
                        .foregroundStyle(LKColor.accent.opacity(0.08))
                    }
                    ForEach(weeks) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Load", week.srpe)
                        )
                        .foregroundStyle(LKColor.accent)
                        .accessibilityLabel(week.weekStart.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(Int(week.srpe.rounded())) AU")
                    }
                }
                .chartYAxisLabel("AU")
                .lkTimeAxis(days: trainingWeeks.rawValue * 7)
                .frame(height: 160)
                .padding(.horizontal, LKSpacing.md)

                if typicalBand != nil {
                    Text("Shaded band is your typical weekly load — bars above it are harder-than-usual weeks.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .padding(.horizontal, LKSpacing.md)
                }

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
                            focusedMuscle = nil
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
            focusedMuscle = nil
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
                            .opacity(focusedMuscle == nil || focusedMuscle == muscle.label ? 1 : 0.18)
                            .interpolationMethod(.monotone)
                            PointMark(
                                x: .value("Week", week.weekStart),
                                y: .value("Sets", week.sets(for: muscle))
                            )
                            .foregroundStyle(by: .value("Muscle", muscle.label))
                            .opacity(focusedMuscle == nil || focusedMuscle == muscle.label ? 1 : 0.18)
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
                // Explicit scale so the tappable legend chips below match the lines.
                .chartForegroundStyleScale(
                    domain: muscles.map(\.label),
                    range: muscles.indices.map { LKChart.categorical[$0 % LKChart.categorical.count] }
                )
                .chartLegend(.hidden)

                // Tappable legend — tap a muscle to isolate its line (others dim),
                // tap again to clear. Colours match the lines above.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LKSpacing.sm) {
                        ForEach(Array(muscles.enumerated()), id: \.element.id) { idx, muscle in
                            let color = LKChart.categorical[idx % LKChart.categorical.count]
                            let on = focusedMuscle == muscle.label
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    focusedMuscle = on ? nil : muscle.label
                                }
                                HapticManager.shared.buttonTap()
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(color).frame(width: 9, height: 9)
                                    Text(muscle.label)
                                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                                        .foregroundColor(LKColor.textPrimary)
                                }
                                .opacity(focusedMuscle == nil || on ? 1 : 0.45)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(on ? color.opacity(0.15) : LKColor.surfaceElevated)
                                .overlay(Capsule().strokeBorder(on ? color : Color.clear, lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }

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
                // Aggregate to the range's cadence (weekly heaviest / best reps on
                // longer views; per-entry on 1W). Axis + dots come from the shared
                // chart style.
                let bucket = LKChartBucket.forRange(days: timeRange.days)
                let weightSeries = LKChart.aggregate(data.map { (date: $0.date, value: $0.weight) }, bucket: bucket, reducer: .max)
                let repsSeries = LKChart.aggregate(data.map { (date: $0.date, value: Double($0.reps)) }, bucket: bucket, reducer: .max)
                let xLower = timeRange.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) } ?? (data.first?.date ?? Date())
                let xUpper = Date()
                let scrubbed: LKAggPoint? = scrubDate.flatMap { d in
                    weightSeries.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) })
                }
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

                        // Weight chart — line with a dot per logged bucket, ringed in
                        // the background colour so it reads on top of the line.
                        Chart {
                            ForEach(weightSeries) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.value)
                                )
                                .foregroundStyle(LKColor.accent)
                                .interpolationMethod(.catmullRom)
                            }
                            ForEach(weightSeries) { point in
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.value)
                                )
                                .foregroundStyle(LKColor.background)
                                .symbolSize(70)
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", point.value)
                                )
                                .foregroundStyle(LKColor.accent)
                                .symbolSize(30)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(Int(point.value)) \(units.weightLabel)")
                            }
                            // Scrub read-out: a rule + callout at the nearest logged
                            // point while dragging across the chart.
                            if let scrubbed {
                                RuleMark(x: .value("Date", scrubbed.date))
                                    .foregroundStyle(LKColor.textMuted.opacity(0.4))
                                    .annotation(position: .top, alignment: .center, spacing: 4) {
                                        VStack(spacing: 1) {
                                            Text(scrubbed.date, format: .dateTime.month(.abbreviated).day())
                                                .font(.system(size: 9)).foregroundColor(LKColor.textMuted)
                                            Text("\(Int(scrubbed.value)) \(units.weightLabel)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(LKColor.textPrimary)
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(LKColor.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal, LKSpacing.md)
                        .chartXScale(domain: xLower...xUpper)
                        .chartXSelection(value: $scrubDate)
                        .lkTimeAxis(days: timeRange.days)
                        .chartYAxisLabel("Weight (\(units.weightLabel))")

                        // Reps chart — best reps per bucket.
                        Chart {
                            ForEach(repsSeries) { point in
                                BarMark(
                                    x: .value("Date", point.date),
                                    y: .value("Reps", point.value)
                                )
                                .foregroundStyle(LKColor.success.opacity(0.85))
                                .cornerRadius(4)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(Int(point.value)) reps")
                            }
                        }
                        .frame(height: 150)
                        .padding(.horizontal, LKSpacing.md)
                        .chartXScale(domain: xLower...xUpper)
                        .lkTimeAxis(days: timeRange.days)
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
                .lkTimeAxis(days: trainingWeeks.rawValue * 7)

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

// MARK: - Shared chart style (LiftKit)
//
// One cadence and one look for every graph in the app so Stats, Health and Body
// Tracking read the same way. The rules — aggregate longer ranges, ~4 centred
// axis labels, line-coloured dots on real entries, recency-weighted trends,
// dim-to-focus legends — are documented for RunKit and FuelKit in
// docs/CHART-STYLE.md so the suite stays visually consistent.

/// How a chart buckets its data. Short ranges stay per-entry; longer ranges
/// aggregate so a line isn't a cloud of points and the axis stays legible.
enum LKChartBucket {
    case day, week, month

    /// Data bucket for a range length in days (nil = "all"): ≤1wk per-entry,
    /// ≤~3mo weekly, longer monthly.
    static func forRange(days: Int?) -> LKChartBucket {
        guard let days else { return .month }
        if days <= 7 { return .day }
        if days <= 100 { return .week }
        return .month
    }

    var component: Calendar.Component {
        switch self {
        case .day:   return .day
        case .week:  return .weekOfYear
        case .month: return .month
        }
    }
}

/// How several values inside one bucket collapse to a single point.
enum LKChartReducer { case max, mean, sum, last }

/// A bucketed point, keyed on its period start so the x-axis is stable.
struct LKAggPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum LKChart {
    /// Categorical series palette, drawn from the app's own semantic colours first
    /// so a split chart still feels like LiftKit. Used for both the lines (via an
    /// explicit foreground-style scale) and the matching tappable legend chips.
    static let categorical: [Color] = [
        LKColor.accent, LKColor.rest, LKColor.success, LKColor.danger,
        .purple, .teal, .pink, .orange
    ]

    /// Aggregate raw (date, value) samples into bucketed points. `.day` passes
    /// through unchanged (per-entry).
    static func aggregate(_ points: [(date: Date, value: Double)],
                          bucket: LKChartBucket,
                          reducer: LKChartReducer,
                          calendar: Calendar = .current) -> [LKAggPoint] {
        guard bucket != .day else {
            return points.map { LKAggPoint(date: $0.date, value: $0.value) }
                         .sorted { $0.date < $1.date }
        }
        let groups = Dictionary(grouping: points) { p in
            calendar.dateInterval(of: bucket.component, for: p.date)?.start ?? p.date
        }
        return groups.map { (start, samples) -> LKAggPoint in
            let values = samples.map(\.value)
            let v: Double
            switch reducer {
            case .max:  v = values.max() ?? 0
            case .mean: v = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            case .sum:  v = values.reduce(0, +)
            case .last: v = samples.max(by: { $0.date < $1.date })?.value ?? 0
            }
            return LKAggPoint(date: start, value: v)
        }
        .sorted { $0.date < $1.date }
    }

    /// Recency-weighted trend line (irregular-interval EWMA). Tolerates sparse,
    /// unevenly spaced samples — where a fixed N-day average barely smooths — by
    /// decaying the running estimate toward each new sample by the time elapsed
    /// since the last. `halfLifeDays` sets the smoothing: larger is smoother/slower.
    static func recencyWeightedTrend(_ points: [(date: Date, value: Double)],
                                     halfLifeDays: Double = 10) -> [LKAggPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard var last = sorted.first else { return [] }
        let lambda = log(2.0) / max(0.5, halfLifeDays)
        var trend = last.value
        var out: [LKAggPoint] = []
        for p in sorted {
            let dtDays = p.date.timeIntervalSince(last.date) / 86_400.0
            let decay = exp(-lambda * max(0.0, dtDays))
            trend = decay * trend + (1.0 - decay) * p.value
            out.append(LKAggPoint(date: p.date, value: trend))
            last = p
        }
        return out
    }

    /// Slope of a trend over its most recent `overDays`, expressed per week.
    static func ratePerWeek(_ trend: [LKAggPoint], overDays: Double = 21) -> Double? {
        guard let last = trend.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-overDays * 86_400)
        let seg = trend.filter { $0.date >= cutoff }
        guard let a = seg.first, let b = seg.last, b.date > a.date else { return nil }
        let days = b.date.timeIntervalSince(a.date) / 86_400
        guard days > 0 else { return nil }
        return (b.value - a.value) / days * 7.0
    }
}

// MARK: Consistent time axis

private enum LKAxisKind { case autoDay, week, month, autoMonth }

private func lkAxisKind(days: Int?) -> LKAxisKind {
    guard let days else { return .autoMonth }
    if days <= 10 { return .autoDay }
    if days <= 45 { return .week }
    if days <= 130 { return .month }
    return .autoMonth
}

extension View {
    /// A consistent x-axis: ~4 evenly spaced labels, month/week labels centred
    /// under their span, faint gridlines. Pass the range length in days (nil = all).
    @ViewBuilder
    func lkTimeAxis(days: Int?) -> some View {
        let grid = LKColor.textMuted.opacity(0.15)
        switch lkAxisKind(days: days) {
        case .autoDay:
            chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10)).foregroundStyle(LKColor.textMuted)
                }
            }
        case .week:
            chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine().foregroundStyle(grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(.system(size: 10)).foregroundStyle(LKColor.textMuted)
                }
            }
        case .month:
            chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(.system(size: 10)).foregroundStyle(LKColor.textMuted)
                }
            }
        case .autoMonth:
            chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.system(size: 10)).foregroundStyle(LKColor.textMuted)
                }
            }
        }
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
