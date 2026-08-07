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

struct ProgramBlueprint: Identifiable, Codable {
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

struct ProgramSession: Identifiable, Codable {
    var id = UUID()
    var name: String
    /// The day's workout type and timings (AMRAP time limit, EMOM rounds, interval
    /// work/rest, For-Time cap, …). A program day is now a full workout of any type,
    /// authored with the real builder; sets still ramp via each exercise's
    /// `setsPerBlock`. Defaults to a Reps day for older programs decoded without it.
    var config: TimerConfig = TimerConfig(type: .reps)
    var exercises: [ProgramExercise]

    var timerType: TimerType { config.type }
}

struct ProgramExercise: Identifiable, Codable {
    var id = UUID()
    var name: String
    var equipment: Equipment
    /// Legacy per-exercise type. The day's type now lives on `ProgramSession.config`;
    /// kept for decoding older programs and never used for materialisation.
    var timerType: TimerType
    var reps: Int
    var weight: Double
    var weightUnit: WeightUnit
    var restSeconds: Int
    /// Sets per block; if shorter than the program's block count the last value
    /// repeats. This is where progressive overload lives.
    var setsPerBlock: [Int]
    /// Supersetted with the next exercise in the session — used to express a complex
    /// (e.g. clean → press → squat done back-to-back as one set).
    var linkedToNext: Bool = false
    /// Timed hold in seconds (e.g. a plank) for an exercise inside a timed day.
    /// 0 = rep-based.
    var durationSeconds: Int = 0
    /// AMRAP multi-round: a new timed round starts after this exercise.
    var roundBreakAfter: Bool = false
    /// AMRAP: minutes of the round this exercise starts (0 = not set).
    var roundMinutes: Int = 0
    /// Progressive overload for custom programs: sets added each block on top of the
    /// base (`setsPerBlock.first`). 0 = flat. Pre-loaded programs leave this 0 and
    /// spell their ramp out in `setsPerBlock` instead.
    var setsIncrementPerBlock: Int = 0

    func sets(inBlock block: Int) -> Int {
        let base = setsPerBlock.first ?? 3
        if setsIncrementPerBlock > 0 { return max(1, base + block * setsIncrementPerBlock) }
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

// Forgiving Codable (in extensions so the memberwise inits survive): every field
// falls back to a default when absent, so a program saved by an older build — before
// `config` or the timed/AMRAP fields existed — decodes cleanly instead of throwing
// and wiping the user's saved programs.
extension ProgramSession {
    private enum CodingKeys: String, CodingKey { case id, name, config, exercises }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? c.decode(UUID.self, forKey: .id)) ?? UUID(),
            name: (try? c.decode(String.self, forKey: .name)) ?? "Session",
            config: (try? c.decode(TimerConfig.self, forKey: .config)) ?? TimerConfig(type: .reps),
            exercises: (try? c.decode([ProgramExercise].self, forKey: .exercises)) ?? [])
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(config, forKey: .config)
        try c.encode(exercises, forKey: .exercises)
    }
}

extension ProgramExercise {
    private enum CodingKeys: String, CodingKey {
        case name, equipment, timerType, reps, weight, weightUnit, restSeconds
        case setsPerBlock, linkedToNext, durationSeconds, roundBreakAfter, roundMinutes
        case setsIncrementPerBlock
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: (try? c.decode(String.self, forKey: .name)) ?? "",
            equipment: (try? c.decode(Equipment.self, forKey: .equipment)) ?? .none,
            timerType: (try? c.decode(TimerType.self, forKey: .timerType)) ?? .reps,
            reps: (try? c.decode(Int.self, forKey: .reps)) ?? 10,
            weight: (try? c.decode(Double.self, forKey: .weight)) ?? 0,
            weightUnit: (try? c.decode(WeightUnit.self, forKey: .weightUnit)) ?? .lb,
            restSeconds: (try? c.decode(Int.self, forKey: .restSeconds)) ?? 90,
            setsPerBlock: (try? c.decode([Int].self, forKey: .setsPerBlock)) ?? [3],
            linkedToNext: (try? c.decode(Bool.self, forKey: .linkedToNext)) ?? false,
            durationSeconds: (try? c.decode(Int.self, forKey: .durationSeconds)) ?? 0,
            roundBreakAfter: (try? c.decode(Bool.self, forKey: .roundBreakAfter)) ?? false,
            roundMinutes: (try? c.decode(Int.self, forKey: .roundMinutes)) ?? 0,
            setsIncrementPerBlock: (try? c.decode(Int.self, forKey: .setsIncrementPerBlock)) ?? 0)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(equipment, forKey: .equipment)
        try c.encode(timerType, forKey: .timerType)
        try c.encode(reps, forKey: .reps)
        try c.encode(weight, forKey: .weight)
        try c.encode(weightUnit, forKey: .weightUnit)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(setsPerBlock, forKey: .setsPerBlock)
        try c.encode(linkedToNext, forKey: .linkedToNext)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(roundBreakAfter, forKey: .roundBreakAfter)
        try c.encode(roundMinutes, forKey: .roundMinutes)
        try c.encode(setsIncrementPerBlock, forKey: .setsIncrementPerBlock)
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
            ProgramSession(name: "Press + Complex", exercises: [press] + complex),
            ProgramSession(name: "Complex + Press", exercises: complex + [press]),
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

    /// The Armor Building Complex, listed as its three movements done back-to-back
    /// (clean ×2 → press ×1 → front squat ×3), superset-linked so the app shows and
    /// counts each lift separately. The set ramp applies to the complex as a whole.
    private static var complex: [ProgramExercise] {
        let ramp = [5, 7, 8, 10]
        return [
            ProgramExercise(name: "Double KB Clean", equipment: .kettlebell, timerType: .reps,
                            reps: 2, weight: 0, weightUnit: .lb, restSeconds: 90,
                            setsPerBlock: ramp, linkedToNext: true),
            ProgramExercise(name: "Double KB Press", equipment: .kettlebell, timerType: .reps,
                            reps: 1, weight: 0, weightUnit: .lb, restSeconds: 90,
                            setsPerBlock: ramp, linkedToNext: true),
            ProgramExercise(name: "Double KB Front Squat", equipment: .kettlebell, timerType: .reps,
                            reps: 3, weight: 0, weightUnit: .lb, restSeconds: 90,
                            setsPerBlock: ramp, linkedToNext: false),
        ]
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
        // Carry the day's type + timings so the scheduled workout opens exactly as
        // built (AMRAP/EMOM/interval timings, not just reps).
        template.storedConfig = session.config
        context.insert(template)
        for (i, ex) in session.exercises.enumerated() {
            // A timed exercise inside a Reps day (e.g. a plank) is a For-Time hold,
            // mirroring how the setup builder saves it.
            let exType: TimerType = (session.config.type == .reps && ex.durationSeconds > 0) ? .forTime : session.config.type
            let te = TemplateExercise(
                exerciseName: ex.name,
                timerType: exType,
                targetSets: ex.sets(inBlock: block),
                targetReps: ex.reps,
                targetDuration: ex.durationSeconds,
                sortOrder: i,
                equipment: ex.equipment,
                targetWeight: ex.weight,
                weightUnit: ex.weightUnit,
                linkedToNext: ex.linkedToNext)
            te.restSeconds = ex.restSeconds
            te.roundBreakAfter = ex.roundBreakAfter
            te.roundMinutes = ex.roundMinutes
            te.template = template
            context.insert(te)
        }
        return template
    }
}

// MARK: - Browse

struct ProgramsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userPrograms: [ProgramBlueprint] = UserProgramStore.load()
    @State private var showBuilder = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.md) {
                    Text("Pick a plan and it fills your calendar, or build your own. Editing before you start is always up to you.")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !userPrograms.isEmpty {
                        header("YOUR PROGRAMS")
                        ForEach(userPrograms) { bp in
                            NavigationLink { ProgramDetailView(blueprint: bp) } label: { card(bp) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { delete(bp) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    header("READY-MADE")
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showBuilder = true; HapticManager.shared.buttonTap() } label: {
                            Label("Create Program", systemImage: "plus")
                        }
                        Button { showImport = true; HapticManager.shared.buttonTap() } label: {
                            Label("Import from Text", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showBuilder) {
                NavigationStack {
                    ProgramBuilderView(draft: ProgramDraft(), onSave: save)
                }
            }
            .sheet(isPresented: $showImport) {
                NavigationStack {
                    PasteImportView(onSave: save)
                }
            }
        }
    }

    private func save(_ bp: ProgramBlueprint) {
        UserProgramStore.add(bp)
        userPrograms = UserProgramStore.load()
        showBuilder = false
        showImport = false
    }

    private func delete(_ bp: ProgramBlueprint) {
        UserProgramStore.delete(bp.id)
        userPrograms = UserProgramStore.load()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LKSpacing.xs)
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

// MARK: - User program store
//
// User-authored programs persist as Codable `ProgramBlueprint`s in a JSON file (not
// SwiftData — no schema/migration surface, and a program is a value type). They show
// under "Your Programs" and schedule through the same `ProgramMaterializer`.
enum UserProgramStore {
    private static var url: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "UserPrograms.json")
    }

    static func load() -> [ProgramBlueprint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ProgramBlueprint].self, from: data)) ?? []
    }

    static func save(_ programs: [ProgramBlueprint]) {
        guard let data = try? JSONEncoder().encode(programs) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func add(_ program: ProgramBlueprint) {
        var all = load()
        all.removeAll { $0.id == program.id }
        all.append(program)
        save(all)
    }

    static func delete(_ id: String) { save(load().filter { $0.id != id }) }
}

// MARK: - Editable draft (builder state)

struct ProgramDraft {
    var name = ""
    var weeks = 8
    var weekdays: Set<Int> = [2, 4, 6]     // Mon / Wed / Fri
    /// Each day is a full workout of any type, authored with the real builder.
    var days: [ProgramSession] = []
    /// Progressive overload: when on, reps-day sets ramp up every `weeksPerBlock`
    /// weeks, by each exercise's own per-block increment.
    var rampSets = false
    var weeksPerBlock = 2
    var attributionName = ""
    var attributionURL = ""
}

// MARK: - Custom program builder

struct ProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ProgramBlueprint) -> Void
    @State private var draft: ProgramDraft
    @State private var expanded: Set<UUID> = []
    /// Drives the day-authoring sheet; `editingID == nil` means adding a new day.
    @State private var authoring = false
    @State private var editingID: UUID?

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    init(draft: ProgramDraft, onSave: @escaping (ProgramBlueprint) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        && !draft.weekdays.isEmpty
        && draft.days.contains { !$0.exercises.isEmpty }
    }

    var body: some View {
        Form {
            Section("Program") {
                TextField("Name", text: $draft.name)
                Stepper("Weeks: \(draft.weeks)", value: $draft.weeks, in: 1...52)
                Toggle("Progressive sets", isOn: $draft.rampSets)
                if draft.rampSets {
                    Stepper("Add sets every \(draft.weeksPerBlock) wk",
                            value: $draft.weeksPerBlock, in: 1...max(1, draft.weeks))
                    Text("\(blocks) block\(blocks == 1 ? "" : "s") — set each exercise's increase inside its day below. Only reps days ramp.")
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }
            }

            Section("Train on") {
                HStack(spacing: LKSpacing.xs) {
                    ForEach(1...7, id: \.self) { wd in
                        let on = draft.weekdays.contains(wd)
                        Button {
                            if on { draft.weekdays.remove(wd) } else { draft.weekdays.insert(wd) }
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

            Section {
                ForEach($draft.days) { $day in
                    dayCard($day)
                }
                Button {
                    editingID = nil
                    authoring = true
                } label: {
                    Label("Add a day", systemImage: "plus.circle")
                }
            } header: {
                Text("Days")
            } footer: {
                Text("Each day is a full workout of any type — pick the type, then build it with all the usual options. Days rotate across your training days; with an odd number of days a two-day plan alternates each week.")
            }

            Section("Credit (optional)") {
                TextField("Source (e.g. a coach's name)", text: $draft.attributionName)
                TextField("Link (https://…)", text: $draft.attributionURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .scrollContentBackground(.hidden)
        .background(LKColor.background.ignoresSafeArea())
        .navigationTitle("New Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(makeBlueprint()) }.bold().disabled(!canSave)
            }
        }
        .sheet(isPresented: $authoring) {
            ProgramDayAuthorSheet(existing: editingDay) { session in
                if let editingID, let i = draft.days.firstIndex(where: { $0.id == editingID }) {
                    var s = session
                    s.id = editingID
                    draft.days[i] = s
                } else {
                    draft.days.append(session)
                    expanded.insert(session.id)
                }
            }
        }
    }

    private var editingDay: ProgramSession? {
        guard let editingID else { return nil }
        return draft.days.first { $0.id == editingID }
    }

    @ViewBuilder
    private func dayCard(_ day: Binding<ProgramSession>) -> some View {
        let s = day.wrappedValue
        let showRamp = draft.rampSets && blocks > 1 && s.config.type == .reps
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(s.id) },
            set: { if $0 { expanded.insert(s.id) } else { expanded.remove(s.id) } }
        )) {
            ForEach($day.exercises) { $ex in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(ex.name).font(LKFont.body).foregroundColor(LKColor.textPrimary)
                        Spacer()
                        Text(exerciseDetail(ex, type: s.config.type))
                            .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    }
                    // Per-exercise ramp — so a main lift can climb while an accessory
                    // stays flat. Only on reps days; timed holds don't count sets.
                    if showRamp && ex.durationSeconds == 0 {
                        Stepper("Ramp: +\(ex.setsIncrementPerBlock) set/block",
                                value: $ex.setsIncrementPerBlock, in: 0...5)
                            .font(LKFont.caption)
                        if ex.setsIncrementPerBlock > 0 {
                            Text(rampPreview(ex))
                                .font(LKFont.caption).foregroundColor(LKColor.accent)
                        }
                    }
                }
            }
            Button {
                editingID = s.id
                authoring = true
            } label: {
                Label("Edit day", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                draft.days.removeAll { $0.id == s.id }
            } label: {
                Label("Delete day", systemImage: "trash")
            }
        } label: {
            HStack(spacing: LKSpacing.sm) {
                Image(systemName: s.config.type.sfSymbol).foregroundColor(LKColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name.isEmpty ? s.config.type.displayName : s.name)
                        .font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                    Text(daySummary(s)).font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }
            }
        }
    }

    /// Number of set-ramp blocks the program spans (1 when the ramp is off).
    private var blocks: Int {
        guard draft.rampSets else { return 1 }
        let wpb = max(1, min(draft.weeksPerBlock, draft.weeks))
        return max(1, Int(ceil(Double(draft.weeks) / Double(wpb))))
    }

    /// "5 → 7 → 9 → 11 sets" preview of one exercise's ramp across the blocks.
    private func rampPreview(_ ex: ProgramExercise) -> String {
        (0..<blocks).map { String(ex.sets(inBlock: $0)) }.joined(separator: " → ") + " sets"
    }

    private func daySummary(_ s: ProgramSession) -> String {
        let n = s.exercises.count
        let moves = "\(n) move\(n == 1 ? "" : "s")"
        let c = s.config
        switch c.type {
        case .amrap:     return "AMRAP · \(Int(c.totalTime / 60)) min · \(moves)"
        case .emom:      return "EMOM · \(c.rounds) min · \(moves)"
        case .forTime:   return "For Time · \(Int(c.totalDuration / 60)) min cap · \(moves)"
        case .intervals: return "Intervals · \(c.intervalRounds)× · \(moves)"
        case .reps:      return "Reps · \(moves)"
        case .manual:    return "Self-paced · \(moves)"
        }
    }

    private func exerciseDetail(_ ex: ProgramExercise, type: TimerType) -> String {
        if ex.durationSeconds > 0 { return "\(ex.durationSeconds)s" }
        if type == .reps {
            let sets = ex.setsPerBlock.first ?? 1
            return "\(sets)×\(ex.reps)"
        }
        return "\(ex.reps) reps"
    }

    private func makeBlueprint() -> ProgramBlueprint {
        let weeks = max(1, draft.weeks)
        let sessions = draft.days.filter { !$0.exercises.isEmpty }
        return ProgramBlueprint(
            id: "user-\(UUID().uuidString)",
            name: draft.name.trimmingCharacters(in: .whitespaces),
            summary: "\(weeks) week\(weeks == 1 ? "" : "s") · \(draft.weekdays.count)×/week",
            weeks: weeks,
            weeksPerBlock: draft.rampSets ? max(1, min(draft.weeksPerBlock, weeks)) : weeks,
            sessions: sessions,
            recommendedWeekdays: draft.weekdays.sorted(),
            attribution: draft.attributionName.isEmpty ? nil : draft.attributionName,
            attributionURL: draft.attributionURL.isEmpty ? nil : draft.attributionURL)
    }
}

// MARK: - Day authoring sheet (reuses the real workout builder)

/// Type picker → the full `WorkoutSetupView` in authoring mode, so a program day is
/// built with exactly the same options as a normal workout. Hands the built
/// `ProgramSession` back via `onDone`. `existing` pre-loads a day for editing.
struct ProgramDayAuthorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: ProgramSession?
    let onDone: (ProgramSession) -> Void
    @State private var vm = WorkoutViewModel()
    @State private var chosenType: TimerType?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            if let type = chosenType {
                WorkoutSetupView(vm: vm, type: type, onSaveToProgram: onDone)
            } else {
                typeList
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                vm.loadProgramSession(existing)
                chosenType = existing.config.type
            }
        }
    }

    private var typeList: some View {
        List {
            ForEach(TimerType.allCases) { t in
                Button {
                    vm.resetSetup()
                    vm.selectedTimerType = t
                    chosenType = t
                } label: {
                    HStack(spacing: LKSpacing.md) {
                        Image(systemName: t.sfSymbol)
                            .foregroundColor(LKColor.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayName).font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                            Text(t.subtitle).font(LKFont.caption).foregroundColor(LKColor.textMuted)
                        }
                        Spacer()
                    }
                }
                .listRowBackground(LKColor.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LKColor.background.ignoresSafeArea())
        .navigationTitle("Choose Type")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - Paste-text import (assisted draft)
//
// A user pastes program text they found; a rough draft is parsed and opened in the
// builder for review/edit before saving. Deliberately kept to on-device text only
// (no scraping, no network). A smarter on-device LLM parse is a planned upgrade;
// the review gate + credit link keep this IP-safe (user-owned result, not the
// source's copyrighted text).
struct PasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ProgramBlueprint) -> Void
    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
            } header: {
                Text("Paste the program")
            } footer: {
                Text("One movement per line (e.g. \"Back Squat 5x5\"). A rough draft is created — review and edit everything before saving. If it's someone else's program, add a credit link in the next step.")
            }

            Section {
                NavigationLink {
                    ProgramBuilderView(draft: ProgramTextImport.parse(trimmed), onSave: onSave)
                } label: {
                    Label("Create Draft", systemImage: "wand.and.stars")
                }
                .disabled(trimmed.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LKColor.background.ignoresSafeArea())
        .navigationTitle("Import from Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

/// Heuristic first pass: one line → one exercise, pulling a "sets×reps" token when
/// present. Deliberately dumb — it just seeds the builder, which the user then fixes.
enum ProgramTextImport {
    static func parse(_ text: String) -> ProgramDraft {
        var draft = ProgramDraft()
        draft.name = "Imported Program"

        var exercises: [ProgramExercise] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.count >= 2, exercises.count < 30 else { continue }
            var sets = 3, reps = 10, name = line
            if let range = line.range(of: #"(\d{1,2})\s*[xX×]\s*(\d{1,3})"#, options: .regularExpression) {
                let nums = line[range].split { !$0.isNumber }.compactMap { Int($0) }
                if nums.count == 2 {
                    sets = min(20, max(1, nums[0]))
                    reps = min(100, max(1, nums[1]))
                }
                let stripped = line.replacingCharacters(in: range, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:•\t.,"))
                name = stripped.isEmpty ? line : stripped
            }
            exercises.append(ProgramExercise(
                name: name, equipment: .none, timerType: .reps,
                reps: reps, weight: 0, weightUnit: .lb, restSeconds: 90,
                setsPerBlock: [sets]))
        }
        if !exercises.isEmpty {
            draft.days = [ProgramSession(name: "Day A", config: TimerConfig(type: .reps), exercises: exercises)]
        }
        return draft
    }
}
