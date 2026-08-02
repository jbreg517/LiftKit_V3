# Multi-week workout programs

How LiftKit turns a multi-week plan (e.g. an Armor-Building-style block) into
scheduled workouts. Design + what shipped.

## Principle: extend the scheduler, don't rebuild it

A program is **not** a parallel scheduling system. It is a declarative blueprint
that *materialises* into ordinary `WorkoutSchedule` rows — exactly the rows the
hand-built "Schedule a Series" flow already produces — tied together by one
`seriesID`. So the calendar, reminders, "Do Again", completion and series
management all keep working with no new plumbing.

## Model (`Services/WorkoutPrograms.swift`)

- **`ProgramBlueprint`** — `name`, `summary`, `weeks`, `weeksPerBlock`, `sessions`,
  `recommendedWeekdays`, `attribution`/`attributionURL`. Value type, shipped as data.
- **`ProgramSession`** — a named session that rotates across the training days
  (e.g. "Press + Complex", "Complex + Press").
- **`ProgramExercise`** — movement + `reps`, `weight`, `equipment`, `restSeconds`,
  and **`setsPerBlock: [Int]`** — the progression. Weeks are grouped into blocks of
  `weeksPerBlock`; each block has its own set count (last value repeats if short).

Progression lives entirely in `setsPerBlock`, which reads the way published
programs are written ("weeks 1–2 do X sets, weeks 3–4 more…"). With an **odd**
number of training days a two-session rotation flips the lead movement every week
on its own — the classic "week 2 is reversed" pattern with zero extra authoring.

## Materialisation (`ProgramMaterializer`)

- `occurrences(for:startDate:weekdays:)` — pure, returns the concrete dated
  sessions. Drives both the pre-commit **preview** and the write, so what the user
  sees is exactly what gets scheduled.
- `materialize(...)` — writes `WorkoutSchedule` rows under one `seriesID`, reusing
  one `WorkoutTemplate` per **(session, block)** so a set ramp needs at most
  `sessions × blocks` templates (ABF: 2 × 4 = 8), not one per day. Those templates
  are flagged `isProgramGenerated` and hidden from the user's plan list and the
  schedule pickers (they're an implementation detail); the schedule rows that point
  at them launch normally via the existing `loadFromTemplate` path.

## Worked example — the Armor Builder (shipped)

`ProgramCatalog.armorBuilder`, abstracted from Dan John's Armor Building Formula
(name kept generic, credited with an "Inspired by" link per the catalog IP policy —
we never reproduce the prescription verbatim):

- 8 weeks, `weeksPerBlock = 2` → 4 blocks; recommended Mon/Wed/Fri.
- Sessions: **Press + Complex** and **Complex + Press** (same two movements, order
  swapped). Rotating them across 3 days flips the lead every week automatically.
- Double-KB Military Press: `setsPerBlock [5,5,5,5]` (flat), 5 reps.
- Armor Building Complex (2 clean · 1 press · 3 squat = 1 set): `setsPerBlock
  [5,7,8,10]` → 15 → 21 → 24 → **30 sets/week** by weeks 7–8.

User inputs to start it: pick it from **Browse Programs**, set a start date, confirm
the M/W/F mapping, tap **Add to Calendar**. Everything else is derived.

## UI (shipped)

`Workout ▸ Schedule ▸ Browse Programs` (Pro-gated, alongside "Schedule a Series"):
- **`ProgramsView`** — catalog list.
- **`ProgramDetailView`** — structure (each session's movements + set ramp) +
  "Inspired by" link + Start.
- **`StartProgramSheet`** — start date, weekday toggles (pre-filled), a live preview
  of the generated sessions, then materialise.

## Custom authoring (shipped 2026-08-01)

- **`ProgramBuilderView`** — author a program (name, weeks, training days, and
  sessions with exercises: equipment / sets / reps / superset). Produces a
  `ProgramBlueprint` that schedules through the same `ProgramMaterializer`.
- **`UserProgramStore`** — user programs persist as Codable JSON in Application
  Support (no SwiftData schema surface); they appear under "Your Programs" in
  `ProgramsView` with Create + delete.
- **`PasteImportView` / `ProgramTextImport`** — paste program text → a rough draft
  parsed **on-device** (no scraping/network) → opens in the builder for review and
  edit before saving, with an optional credit link. The review gate + user-owned
  result keep it IP-safe.

### Still deferred
- **Per-block set ramp in the builder.** v1 authors flat sets (`weeksPerBlock =
  weeks`, one block). The "4 numbers" ramp editor (which the pre-loaded Armor
  Builder already uses in data) is a v2.
- **On-device LLM parse.** v1's paste import is a line-based heuristic; swapping in
  Apple Foundation Models (iOS 26) is a drop-in upgrade behind the same
  `text → ProgramBlueprint` interface, deferred until the API can be verified on
  device.
- **First-class persisted `WorkoutProgram` entity** (for a "Week 3 of 8" progress
  header / mid-program edits). Today a program is a materialised series grouped by
  `seriesID`; adding the entity is additive.

## Suite tie-in

A program's upcoming sessions match the `SuitePlannedSession` shape on the
`SuiteActivity` channel (see `SUITE-HEALTH-SYNC.md`). Publishing them would let
FuelKit and RunKit prepare around planned training — the planned-session half of
that channel, currently unused on the LiftKit side.
