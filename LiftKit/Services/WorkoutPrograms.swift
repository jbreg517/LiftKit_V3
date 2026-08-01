import SwiftUI
import SwiftData

// MARK: - Program blueprint (declarative, shipped as data)
//
// A multi-week program is described declaratively here, then **materialised** into
// ordinary `WorkoutSchedule` rows (see `ProgramMaterializer`). There is deliberately
// no parallel scheduling system: the calendar, reminders, "Do Again" and completion
// all keep working because a program is just a smarter generator of the same rows a
// hand-built series produces. See `docs/WORKOUT-PROGRAMS.md`.
//
// Progression is expressed as **per-block set counts**. Weeks are grouped into blocks
// of `weeksPerBlock`, and each exercise carries a set count per block. This matches
// how most published programs read ("weeks 1–2 do X sets, weeks 3–4 do more…") and
// keeps authoring down to a handful of numbers. With an odd number of training days a
// two-session rotation flips the lead movement every week on its own, so the classic
// "week 2 is reversed" pattern needs no extra input.

struct ProgramBlueprint: Identifiable {
    let id: String
    let name: String
    let summary: String
    let weeks: Int
    let weeksPerBlock: Int
    /// Movements that rotate across the chosen days (e.g. Press-led, Complex-led).
    let sessions: [ProgramSession]
    /// Suggested training days (1 = Sunday … 7 = Saturday), pre-filled in the picker.
    let recommendedWeekdays: [Int]
    /// Coach / program this is adapted from, surfaced as an "Inspired by" link. The
    /// name itself is kept abstract per the catalog IP policy; pass just the credited
    /// name here (e.g. "Dan John's Armor Building Formula").
    let attribution: String?
    let attributionURL: String?

    /// Number of set-ramp blocks the program spans.
    var blocks: Int { max(1, Int(ceil(Double(weeks) / Double(max(1, weeksPerBlock))))) }

    /// "Wk 1–2" style label for a block.
    func blockLabel(_ block: Int) -> String {
        let startWk = block * weeksPerBlock + 1
        let endWk = min((block + 1) * weeksPerBlock, weeks)
        return startWk == endWk ? "Wk \(startWk)" : "Wk \(startWk)–\(endWk)"
    }
}

struct ProgramSession: Identifiable {
    let id = UUID()
    let name: String
    let exercises: [ProgramExercise]
}

struct ProgramExercise: Identifiable {
    let id = UUID()
    let name: String
    let equipment: Equipment
    let timerType: TimerType
    let reps: Int
    let weight: Double
    let weightUnit: WeightUnit
    let restSeconds: Int
    /// Sets per block; if shorter than the program's block count the last value
    /// repeats. This is where progressive overload lives.
    let setsPerBlock: [Int]

    func sets(inBlock block: Int) -> Int {
        guard !setsPerBlock.isEmpty else { return 3 }
        return setsPerBlock[min(block, setsPerBlock.count - 1)]
    }

    /// "5 sets" when flat, "5→7→8→10 sets" when it ramps across `blocks`.
    func setSummary(blocks: Int) -> String {
        let values = (0..<max(1, blocks)).map { sets(inBlock: $0) }
        if Set(values).count == 1 { return "\(values[0]) sets" }
        return values.map(String.init).joined(separator: "→") + " sets"
    }
}

// MARK: - Catalog (pre-loaded programs)

enum ProgramCatalog {
    static let all: [ProgramBlueprint] = [armorBuilder]

    /// Abstracted from Dan John's Armor Building Formula — the name is kept generic
    /// and the source is credited with a link, per the catalog IP policy (we never
    /// reproduce the prescription verbatim). Double-kettlebell press plus the Armor
    /// Building Complex (2 cleans + 1 press + 3 front squats = one set), three days a
    /// week, ramping the complex from 5 to 10 sets per session — 15 → 30 sets a week.
    static let armorBuilder = ProgramBlueprint(
        id: "armor-builder",
        name: "Kettlebell Armor Builder",
        summary: "8 weeks · 3 days/week. Double-KB press and complex, ramping to 30 complex sets a week.",
        weeks: 8,
        weeksPerBlock: 2,
        sessions: [
            ProgramSession(name: "Press + Complex", exercises: [press, complex]),
            ProgramSession(name: "Complex + Press", exercises: [complex, press]),
        ],
        recommendedWeekdays: [2, 4, 6],   // Mon / Wed / Fri
        attribution: "Dan John's Armor Building Formula",
        attributionURL: "https://www.youtube.com/results?search_query=dan+john+armor+building+complex"
    )

    private static var press: ProgramExercise {
        ProgramExercise(
            name: "Double KB Military Press", equipment: .kettlebell, timerType: .reps,
            reps: 5, weight: 0, weightUnit: .lb, restSeconds: 90, setsPerBlock: [5, 5, 5, 5])
    }
    private static var complex: ProgramExercise {
        ProgramExercise(
            name: "Armor Building Complex (2 clean · 1 press · 3 squat)", equipment: .kettlebell,
            timerType: .reps, reps: 1, weight: 0, weightUnit: .lb, restSeconds: 90,
            setsPerBlock: [5, 7, 8, 10])
    }
}

// MARK: - Materializer

/// One dated session a program will create. Also powers the pre-commit preview, so
/// what the user sees is exactly what gets written.
struct ProgramOccurrence: Identifiable {
    let id = UUID()
    let date: Date
    let weekIndex: Int
    let block: Int
    let sessionIndex: Int
    let session: ProgramSession
}

enum ProgramMaterializer {
    /// The concrete sessions `blueprint` would create starting `startDate`, on
    /// `weekdays` — pure, side-effect free, so it drives both the preview and the
    /// write. The session rotation flips the lead movement each week whenever the
    /// number of training days is odd (the "week 2 reversed" behaviour).
    static func occurrences(for blueprint: ProgramBlueprint,
                            startDate: Date,
                            weekdays: Set<Int>) -> [ProgramOccurrence] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        guard !weekdays.isEmpty, !blueprint.sessions.isEmpty,
              let end = cal.date(byAdding: .day, value: blueprint.weeks * 7 - 1, to: start)
        else { return [] }

        var result: [ProgramOccurrence] = []
        var current = start
        var count = 0
        while current <= end {
            if weekdays.contains(cal.component(.weekday, from: current)) {
                let daysSince = cal.dateComponents([.day], from: start, to: current).day ?? 0
                let weekIndex = daysSince / 7
                let block = min(weekIndex / max(1, blueprint.weeksPerBlock), blueprint.blocks - 1)
                let sessionIndex = count % blueprint.sessions.count
                result.append(ProgramOccurrence(
                    date: current, weekIndex: weekIndex, block: block,
                    sessionIndex: sessionIndex, session: blueprint.sessions[sessionIndex]))
                count += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    /// Write the program into the calendar as `WorkoutSchedule` rows tied by one
    /// `seriesID`, reusing per-(session, block) templates so a set ramp needs at most
    /// `sessions × blocks` templates rather than one per day. Returns the number of
    /// sessions scheduled.
    @MainActor
    @discardableResult
    static func materialize(_ blueprint: ProgramBlueprint,
                            startDate: Date,
                            weekdays: Set<Int>,
                            context: ModelContext) -> Int {
        let occ = occurrences(for: blueprint, startDate: startDate, weekdays: weekdays)
        guard !occ.isEmpty else { return 0 }
        let seriesID = UUID()
        var cache: [String: WorkoutTemplate] = [:]
        for o in occ {
            let key = "\(o.sessionIndex)-\(o.block)"
            let template = cache[key] ?? makeTemplate(o.session, block: o.block, blueprint: blueprint, context: context)
            cache[key] = template
            let sched = WorkoutSchedule(date: o.date, template: template, seriesID: seriesID)
            context.insert(sched)
            WorkoutReminders.schedule(sched)
        }
        Persist.save(context)
        return occ.count
    }

    @MainActor
    private static func makeTemplate(_ session: ProgramSession, block: Int,
                                     blueprint: ProgramBlueprint, context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "\(blueprint.name) · \(session.name) · \(blueprint.blockLabel(block))")
        template.isProgramGenerated = true
        context.insert(template)
        for (i, ex) in session.exercises.enumerated() {
            let te = TemplateExercise(
                exerciseName: ex.name,
                timerType: ex.timerType,
                targetSets: ex.sets(inBlock: block),
                targetReps: ex.reps,
                targetDuration: 0,
                sortOrder: i,
                equipment: ex.equipment,
                targetWeight: ex.weight,
                weightUnit: ex.weightUnit,
                linkedToNext: false)
            te.restSeconds = ex.restSeconds
            te.template = template
            context.insert(te)
        }
        return template
    }
}

// MARK: - Browse

struct ProgramsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.md) {
                    Text("Pick a plan and it fills your calendar — sets ramp automatically week to week. You can still build your own series any time.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ProgramCatalog.all) { bp in
                        NavigationLink { ProgramDetailView(blueprint: bp) } label: { card(bp) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(LKSpacing.md)
            }
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
            }
        }
    }

    private func card(_ bp: ProgramBlueprint) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text(bp.name).font(LKFont.heading).foregroundColor(LKColor.textPrimary)
            Text(bp.summary).font(LKFont.caption).foregroundColor(LKColor.textSecondary)
            HStack(spacing: LKSpacing.sm) {
                pill("\(bp.weeks) weeks")
                pill("\(bp.recommendedWeekdays.count)×/week")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(LKColor.textMuted)
            }
            .padding(.top, LKSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lkCard()
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, LKSpacing.sm).padding(.vertical, 3)
            .background(LKColor.surfaceElevated).cornerRadius(LKRadius.small)
            .foregroundColor(LKColor.textSecondary)
    }
}

// MARK: - Detail

struct ProgramDetailView: View {
    let blueprint: ProgramBlueprint
    @State private var showStart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.lg) {
                VStack(alignment: .leading, spacing: LKSpacing.sm) {
                    Text(blueprint.summary).font(LKFont.body).foregroundColor(LKColor.textSecondary)
                    if let name = blueprint.attribution {
                        InspiredByLink(name: name, urlString: blueprint.attributionURL)
                    }
                }

                VStack(alignment: .leading, spacing: LKSpacing.md) {
                    Text("EACH WEEK").font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
                    ForEach(blueprint.sessions) { session in
                        VStack(alignment: .leading, spacing: LKSpacing.xs) {
                            Text(session.name).font(LKFont.heading).foregroundColor(LKColor.textPrimary)
                            ForEach(session.exercises) { ex in
                                Text("• \(ex.name) — \(ex.reps) rep\(ex.reps == 1 ? "" : "s") · \(ex.setSummary(blocks: blueprint.blocks))")
                                    .font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lkCard()
                    }
                    Text("Sessions alternate across your chosen days, so the lead movement flips each week.")
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }

                Button {
                    showStart = true
                    HapticManager.shared.buttonTap()
                } label: {
                    Label("Start Program", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(LKPrimaryButtonStyle())
            }
            .padding(LKSpacing.md)
            .readableWidth()
        }
        .background(LKColor.background.ignoresSafeArea())
        .navigationTitle(blueprint.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStart) { StartProgramSheet(blueprint: blueprint) }
    }
}

// MARK: - Start (schedule into the calendar)

struct StartProgramSheet: View {
    let blueprint: ProgramBlueprint
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var weekdays: Set<Int>

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    init(blueprint: ProgramBlueprint) {
        self.blueprint = blueprint
        _startDate = State(initialValue: Calendar.current.startOfDay(for: Date()))
        _weekdays = State(initialValue: Set(blueprint.recommendedWeekdays))
    }

    private var occurrences: [ProgramOccurrence] {
        ProgramMaterializer.occurrences(for: blueprint, startDate: startDate, weekdays: weekdays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start") {
                    DatePicker("Start date", selection: $startDate, in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                        .tint(LKColor.accent)
                }

                Section("Train on") {
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

                Section("Preview") {
                    Text(summary).font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                    ForEach(occurrences.prefix(6)) { o in
                        HStack {
                            Text(o.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(LKFont.caption).foregroundColor(LKColor.textPrimary)
                            Spacer()
                            Text(o.session.name)
                                .font(LKFont.caption).foregroundColor(LKColor.textSecondary)
                        }
                    }
                    if occurrences.count > 6 {
                        Text("+ \(occurrences.count - 6) more").font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Start \(blueprint.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Calendar") {
                        ProgramMaterializer.materialize(blueprint, startDate: startDate, weekdays: weekdays, context: context)
                        HapticManager.shared.buttonTap()
                        dismiss()
                    }
                    .bold()
                    .disabled(occurrences.isEmpty)
                }
            }
        }
    }

    private var summary: String {
        if weekdays.isEmpty { return "Pick the days you'll train." }
        return "\(occurrences.count) session\(occurrences.count == 1 ? "" : "s") over \(blueprint.weeks) weeks."
    }
}
