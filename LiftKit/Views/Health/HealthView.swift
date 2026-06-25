import SwiftUI
import SwiftData
import Charts

/// Premium "Health" tab: bodyweight + height, a rough BMR/TDEE, weight goals
/// with a calorie recommendation, daily macro logging, workout calorie-burn
/// estimates, and basic trends. Manual entry only — no food lookups or
/// third-party integrations, all on-device.
struct HealthView: View {
    @Bindable var vm: WorkoutViewModel

    @Environment(\.modelContext) private var context
    @Query private var userProfiles: [UserProfile]
    @Query private var healthProfiles: [HealthProfile]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \NutritionDay.date) private var nutritionDays: [NutritionDay]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    @State private var showGoals = false
    @State private var showWeightAdd = false
    @State private var showNutritionAdd = false
    @State private var showLogin = false

    private var isPremium: Bool { userProfiles.first?.isPremium ?? false }
    private var hp: HealthProfile? { healthProfiles.first }

    var body: some View {
        NavigationStack {
            Group {
                if isPremium {
                    premiumContent
                } else {
                    lockedView
                }
            }
            .navigationTitle("Health")
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                if isPremium {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showGoals = true } label: {
                            Image(systemName: "slider.horizontal.3").foregroundColor(LKColor.accent)
                        }
                        .accessibilityLabel("Edit goals & profile")
                    }
                }
            }
            .onAppear {
                if isPremium && healthProfiles.isEmpty {
                    context.insert(HealthProfile())
                    try? context.save()
                }
            }
            .sheet(isPresented: $showGoals) { HealthGoalsSheet() }
            .sheet(isPresented: $showWeightAdd) { AddBodyMetricSheet(defaultType: .bodyweight) }
            .sheet(isPresented: $showNutritionAdd) {
                NutritionQuickAddSheet { p, c, f, a in addMacros(p: p, c: c, f: f, a: a) }
            }
            .sheet(isPresented: $showLogin) { LoginView(vm: vm) }
        }
    }

    // MARK: - Premium content
    private var premiumContent: some View {
        ScrollView {
            VStack(spacing: LKSpacing.lg) {
                energySection
                weightGoalSection
                nutritionSection
                burnSection
                trendsSection
                measurementsLink
            }
            .padding(.vertical, LKSpacing.md)
        }
    }

    // MARK: - Energy (BMR / TDEE / target)
    private var energySection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            sectionHeader("DAILY ENERGY")
            if let bmr, let tdee, let goal = goalCalories {
                HStack(spacing: LKSpacing.sm) {
                    tile("BMR", "\(kcal(bmr))", "kcal", "bed.double.fill")
                    tile("Maintain", "\(kcal(tdee))", "kcal", "flame.fill")
                    tile("Target", "\(kcal(goal))", "kcal", "target")
                }
                .padding(.horizontal, LKSpacing.md)
                Text("Rough estimate (Mifflin–St Jeor) from your weight, height, age, sex and activity. Target reflects your weight goal.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
            } else {
                setupPrompt
            }
        }
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("Finish setting up to see your calorie numbers.")
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
            if latestWeightLb == nil {
                Button("Log Weight") { showWeightAdd = true }
                    .buttonStyle(LKPrimaryButtonStyle())
            }
            Button("Set Height, Age & Goal") { showGoals = true }
                .buttonStyle(LKPrimaryButtonStyle())
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Weight + goal
    private var weightGoalSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            sectionHeader("WEIGHT")
            HStack(spacing: LKSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current").font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    Text(latestWeightLb.map { "\(Int($0.rounded())) lb" } ?? "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(LKColor.textPrimary)
                }
                if let hp, hp.goalWeightLb > 0 {
                    Image(systemName: "arrow.right").foregroundColor(LKColor.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goal").font(LKFont.caption).foregroundColor(LKColor.textMuted)
                        Text("\(Int(hp.goalWeightLb.rounded())) lb")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(LKColor.accent)
                    }
                }
                Spacer()
                Button { showWeightAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(LKColor.accent)
                }
                .accessibilityLabel("Log weight")
            }
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)

            if let eta = goalETAText {
                Text(eta)
                    .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    // MARK: - Nutrition (today)
    private var nutritionSection: some View {
        let day = todayLog
        let consumed = day?.calories ?? 0
        return VStack(alignment: .leading, spacing: LKSpacing.sm) {
            HStack {
                Text("TODAY’S INTAKE")
                    .font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
                Spacer()
                if day != nil {
                    Button("Clear") { clearToday() }
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }
            }
            .padding(.horizontal, LKSpacing.md)
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(kcal(consumed))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(LKColor.textPrimary)
                    Text("kcal").foregroundColor(LKColor.textMuted)
                    Spacer()
                    if let goal = goalCalories {
                        Text("of \(kcal(goal)) target")
                            .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    }
                }
                if let goal = goalCalories {
                    calorieBar(consumed: consumed, goal: goal)
                }
                macroRow(day)
                Button { showNutritionAdd = true } label: {
                    Label("Log Macros", systemImage: "plus")
                        .font(LKFont.bodyBold)
                }
                .buttonStyle(LKSecondaryButtonStyle())
            }
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)
        }
    }

    private func macroRow(_ day: NutritionDay?) -> some View {
        let t = macroTargets
        return HStack(spacing: LKSpacing.sm) {
            macroPill("Protein", day?.proteinG ?? 0, t?.proteinG, LKColor.rest)
            macroPill("Carbs", day?.carbG ?? 0, t?.carbG, LKColor.work)
            macroPill("Fat", day?.fatG ?? 0, t?.fatG, LKColor.accent)
            macroPill("Alcohol", day?.alcoholG ?? 0, nil, LKColor.danger)
        }
    }

    private func macroPill(_ label: String, _ grams: Double, _ target: Double?, _ color: Color) -> some View {
        let hasTarget = (target ?? 0) > 0
        let fill = hasTarget ? min(1.0, grams / target!) : 0
        return VStack(spacing: 3) {
            Text(hasTarget ? "\(Int(grams.rounded()))/\(Int(target!.rounded()))g" : "\(Int(grams.rounded()))g")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LKColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundColor(LKColor.textMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.25))
                    Capsule().fill(color)
                        .frame(width: hasTarget ? max(0, geo.size.width * fill) : 0)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workout calorie burn
    private var burnSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            sectionHeader("WORKOUT BURN")
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                HStack(spacing: LKSpacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(LKFont.caption).foregroundColor(LKColor.textMuted)
                        Text("\(kcal(weekBurn)) kcal")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(LKColor.textPrimary)
                    }
                    Spacer()
                }
                ForEach(recentBurnSessions) { s in
                    HStack {
                        Image(systemName: s.timerType?.sfSymbol ?? "dumbbell.fill")
                            .font(.caption).foregroundColor(LKColor.accent).frame(width: 20)
                        Text(s.name.isEmpty ? (s.timerType?.rawValue ?? "Workout") : s.name)
                            .font(LKFont.body).foregroundColor(LKColor.textPrimary).lineLimit(1)
                        Spacer()
                        Text("~\(kcal(burn(for: s))) kcal")
                            .font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                    }
                }
                if latestWeightLb == nil {
                    Text("Log your bodyweight for burn estimates.")
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }
                Text("Estimated from duration and bodyweight. Your calorie target already includes everyday activity — don’t add these back twice.")
                    .font(.system(size: 11))
                    .foregroundColor(LKColor.textMuted)
            }
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)
        }
    }

    // MARK: - Trends
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            sectionHeader("TRENDS")
            weightTrend
            calorieTrend
        }
    }

    private var weightTrend: some View {
        let data = bodyMetrics.filter { $0.type == .bodyweight }.sorted { $0.date < $1.date }
        let smooth = movingAverage(data, days: 7)
        return VStack(alignment: .leading, spacing: LKSpacing.xs) {
            HStack {
                Text("Bodyweight").font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                Spacer()
                if data.count >= 2 {
                    Text("dots = weigh-ins · line = 7-day avg")
                        .font(.system(size: 10)).foregroundColor(LKColor.textMuted)
                }
            }
            .padding(.horizontal, LKSpacing.md)
            if data.count < 2 {
                emptyChart("Log weight on a few days to see the trend.")
            } else {
                Chart {
                    ForEach(data) { m in
                        PointMark(x: .value("Date", m.date), y: .value("lb", m.value))
                            .foregroundStyle(LKColor.textMuted.opacity(0.5))
                            .symbolSize(18)
                    }
                    ForEach(smooth) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Trend", p.value))
                            .foregroundStyle(LKColor.accent)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    private var calorieTrend: some View {
        let data = calorieSeries
        return VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text("Calories (last 14 days)").font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                .padding(.horizontal, LKSpacing.md)
            if data.isEmpty {
                emptyChart("Log macros to see your intake trend.")
            } else {
                Chart {
                    ForEach(data) { d in
                        BarMark(x: .value("Date", d.date), y: .value("kcal", d.calories))
                            .foregroundStyle(LKColor.accent)
                            .cornerRadius(3)
                    }
                    if let goal = goalCalories {
                        RuleMark(y: .value("Target", goal))
                            .foregroundStyle(LKColor.textMuted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    private var measurementsLink: some View {
        NavigationLink(destination: BodyTrackingView()) {
            HStack {
                Image(systemName: "ruler.fill").foregroundColor(LKColor.accent).frame(width: 24)
                Text("Body Measurements").font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                Spacer()
            }
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locked (non-premium)
    private var lockedView: some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 56)).foregroundColor(LKColor.accent)
            Text("Health Tracking").font(LKFont.title).foregroundColor(LKColor.textPrimary)
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                lockedBullet("scalemass.fill", "Bodyweight, height & BMR")
                lockedBullet("fork.knife", "Daily calories & macros")
                lockedBullet("target", "Weight goals & calorie targets")
                lockedBullet("flame.fill", "Workout calorie-burn estimates")
            }
            .padding(.horizontal, LKSpacing.xl)
            Text("A Premium feature. Everything stays on your device.")
                .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                .multilineTextAlignment(.center)
            Button("Sign In to Unlock") { showLogin = true }
                .buttonStyle(LKPrimaryButtonStyle())
                .padding(.horizontal, LKSpacing.xl)
            Spacer()
        }
        .padding(LKSpacing.md)
    }

    private func lockedBullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: LKSpacing.md) {
            Image(systemName: icon).foregroundColor(LKColor.accent).frame(width: 28)
            Text(text).font(LKFont.body).foregroundColor(LKColor.textSecondary)
            Spacer()
        }
    }

    // MARK: - Small components
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LKSpacing.md)
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ icon: String) -> some View {
        VStack(spacing: LKSpacing.xs) {
            Image(systemName: icon).font(.body).foregroundColor(LKColor.accent)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(LKColor.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.system(size: 10)).foregroundColor(LKColor.textMuted)
            Text(title).font(LKFont.caption).foregroundColor(LKColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
    }

    private func calorieBar(consumed: Double, goal: Double) -> some View {
        let frac = goal > 0 ? min(1.0, consumed / goal) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LKColor.surfaceElevated)
                Capsule().fill(consumed > goal ? LKColor.danger : LKColor.accent)
                    .frame(width: max(0, geo.size.width * frac))
            }
        }
        .frame(height: 10)
    }

    private func emptyChart(_ message: String) -> some View {
        Text(message)
            .font(LKFont.caption).foregroundColor(LKColor.textMuted)
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Derived values
    private var latestWeightLb: Double? {
        bodyMetrics.filter { $0.type == .bodyweight }.max(by: { $0.date < $1.date })?.value
    }
    private var bmr: Double? {
        guard let hp, let w = latestWeightLb else { return nil }
        return HealthCalculations.bmr(weightLb: w, heightInches: hp.heightInches, age: hp.age, sex: hp.biologicalSex)
    }
    private var tdee: Double? {
        guard let bmr, let hp else { return nil }
        return HealthCalculations.tdee(bmr: bmr, activity: hp.activityLevel)
    }
    private var goalCalories: Double? {
        guard let tdee, let hp else { return nil }
        return HealthCalculations.goalCalories(tdee: tdee, goal: hp.goalType, weeklyRateLb: hp.weeklyRateLb)
    }
    private var macroTargets: HealthCalculations.MacroTargets? {
        guard let goal = goalCalories, let w = latestWeightLb, let hp else { return nil }
        return HealthCalculations.macroTargets(calories: goal, weightLb: w,
                                               proteinPerLb: hp.proteinPerLb, fatPercent: hp.fatPercent)
    }
    /// Projected date to reach the goal weight at the chosen weekly rate.
    private var goalETAText: String? {
        guard let hp, hp.goalType != .maintain, hp.goalWeightLb > 0,
              let current = latestWeightLb, hp.weeklyRateLb > 0 else { return nil }
        let toward = hp.goalType == .lose ? (current - hp.goalWeightLb) : (hp.goalWeightLb - current)
        if toward <= 0 { return "Goal weight reached 🎉" }
        let weeks = toward / hp.weeklyRateLb
        guard let date = Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: Date()) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return "Est. goal: \(f.string(from: date)) · ~\(Int(weeks.rounded())) wk at \(fmtRate(hp.weeklyRateLb))/wk"
    }
    private func fmtRate(_ r: Double) -> String {
        (r == r.rounded() ? "\(Int(r))" : String(format: "%.2g", r)) + " lb"
    }
    private var todayLog: NutritionDay? {
        nutritionDays.first { Calendar.current.isDateInToday($0.date) }
    }
    private var completedSessions: [WorkoutSession] {
        sessions.filter { !$0.isActive }
    }
    private var recentBurnSessions: [WorkoutSession] {
        Array(completedSessions.sorted { $0.startedAt > $1.startedAt }.prefix(4))
    }
    private var weekBurn: Double {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return completedSessions.filter { $0.startedAt >= weekStart }.map { burn(for: $0) }.reduce(0, +)
    }
    private var calorieSeries: [NutritionDay] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return nutritionDays.filter { !$0.isEmpty && $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    private func bodyweight(on date: Date) -> Double? {
        let prior = bodyMetrics
            .filter { $0.type == .bodyweight && $0.date <= date }
            .max(by: { $0.date < $1.date })
        return prior?.value ?? latestWeightLb
    }
    private func burn(for s: WorkoutSession) -> Double {
        guard let w = bodyweight(on: s.startedAt) else { return 0 }
        return HealthCalculations.caloriesBurned(durationSeconds: s.duration, weightLb: w,
                                                 met: HealthCalculations.met(for: s.timerType))
    }

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
    /// Trailing N-day average at each weigh-in, smoothing daily fluctuation.
    private func movingAverage(_ data: [BodyMetric], days: Int) -> [TrendPoint] {
        guard data.count >= 2 else { return [] }
        return data.map { point in
            let start = Calendar.current.date(byAdding: .day, value: -days, to: point.date) ?? point.date
            let window = data.filter { $0.date <= point.date && $0.date >= start }
            let avg = window.map(\.value).reduce(0, +) / Double(max(1, window.count))
            return TrendPoint(date: point.date, value: avg)
        }
    }

    // MARK: - Mutations
    private func addMacros(p: Double, c: Double, f: Double, a: Double) {
        let day: NutritionDay
        if let existing = todayLog {
            day = existing
        } else {
            day = NutritionDay(date: Date())
            context.insert(day)
        }
        day.proteinG += p
        day.carbG += c
        day.fatG += f
        day.alcoholG += a
        try? context.save()
    }
    private func clearToday() {
        if let day = todayLog { context.delete(day); try? context.save() }
    }

    private func kcal(_ v: Double) -> String { "\(Int(v.rounded()))" }
}

// MARK: - Log macros sheet (manual entry, adds to today's totals)
struct NutritionQuickAddSheet: View {
    let onAdd: (Double, Double, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var protein = ""
    @State private var carb = ""
    @State private var fat = ""
    @State private var alcohol = ""

    private func g(_ s: String) -> Double { Double(s.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var addedCalories: Double { g(protein) * 4 + g(carb) * 4 + g(fat) * 9 + g(alcohol) * 7 }
    private var hasInput: Bool { addedCalories > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    macroField("Protein", $protein)
                    macroField("Carbs", $carb)
                    macroField("Fat", $fat)
                    macroField("Alcohol", $alcohol)
                } header: {
                    Text("Grams to add")
                } footer: {
                    Text("Adds to today’s totals. ≈ \(Int(addedCalories.rounded())) kcal.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Log Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(g(protein), g(carb), g(fat), g(alcohol))
                        HapticManager.shared.buttonTap()
                        dismiss()
                    }.bold().disabled(!hasInput)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func macroField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g").foregroundColor(LKColor.textMuted)
        }
    }
}

// MARK: - Goals & profile sheet
struct HealthGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [HealthProfile]

    @State private var heightFeet = 5
    @State private var heightInches = 8
    @State private var age = 30
    @State private var sex: BiologicalSex = .unspecified
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: WeightGoalType = .maintain
    @State private var rate: Double = 1.0
    @State private var goalWeight = ""
    @State private var proteinPerLb: Double = 0.8
    @State private var fatPercent: Double = 0.30
    @State private var loaded = false

    private let rates: [Double] = [0.25, 0.5, 1.0, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Height") {
                    Stepper("\(heightFeet) ft", value: $heightFeet, in: 3...8)
                    Stepper("\(heightInches) in", value: $heightInches, in: 0...11)
                }
                Section("About You") {
                    Stepper("Age: \(age)", value: $age, in: 13...100)
                    Picker("Sex", selection: $sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Picker("Activity", selection: $activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Activity Level")
                } footer: {
                    Text(activity.detail)
                }
                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(WeightGoalType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if goal != .maintain {
                        Picker("Rate", selection: $rate) {
                            ForEach(rates, id: \.self) { r in
                                Text(r == r.rounded() ? "\(Int(r)) lb/wk" : String(format: "%.2g lb/wk", r)).tag(r)
                            }
                        }
                    }
                    HStack {
                        Text("Goal Weight")
                        Spacer()
                        TextField("optional", text: $goalWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("lb").foregroundColor(LKColor.textMuted)
                    }
                }
                Section {
                    Picker("Protein", selection: $proteinPerLb) {
                        ForEach([0.5, 0.6, 0.7, 0.8, 0.9, 1.0], id: \.self) { v in
                            Text(String(format: "%.1f g/lb", v)).tag(v)
                        }
                    }
                    Picker("Fat", selection: $fatPercent) {
                        ForEach([0.20, 0.25, 0.30, 0.35, 0.40], id: \.self) { v in
                            Text("\(Int(v * 100))% of calories").tag(v)
                        }
                    }
                } header: {
                    Text("Macro Targets")
                } footer: {
                    Text("Protein scales with bodyweight; fat is a share of your calorie target; carbs fill the rest.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Goals & Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = profiles.first else { return }
        if p.heightInches > 0 {
            heightFeet = Int(p.heightInches) / 12
            heightInches = Int(p.heightInches) % 12
        }
        if p.age > 0 { age = p.age }
        sex = p.biologicalSex
        activity = p.activityLevel
        goal = p.goalType
        rate = p.weeklyRateLb
        if p.goalWeightLb > 0 { goalWeight = String(Int(p.goalWeightLb)) }
        if p.proteinPerLb > 0 { proteinPerLb = p.proteinPerLb }
        if p.fatPercent > 0 { fatPercent = p.fatPercent }
    }

    private func save() {
        let p: HealthProfile
        if let existing = profiles.first {
            p = existing
        } else {
            p = HealthProfile()
            context.insert(p)
        }
        p.heightInches = Double(heightFeet * 12 + heightInches)
        p.age = age
        p.biologicalSex = sex
        p.activityLevel = activity
        p.goalType = goal
        p.weeklyRateLb = rate
        p.goalWeightLb = Double(goalWeight.trimmingCharacters(in: .whitespaces)) ?? 0
        p.proteinPerLb = proteinPerLb
        p.fatPercent = fatPercent
        try? context.save()
        dismiss()
    }
}
