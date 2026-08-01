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

## Deferred (next step): custom authoring

The pre-loaded path exercises the whole model end to end. The **custom program
builder** — where a user defines their own sessions, weeks and set ramp — is not yet
built. It reuses the template builder for the sessions and adds a Weeks value plus a
per-block set ramp (the "4 numbers" flow), then calls the same `materialize`. It is
the biggest, most stateful screen, deferred so the core could ship and be verified
first.

Also deferred: a first-class persisted `WorkoutProgram` entity (for a "Week 3 of 8"
progress header and mid-program edits). Today a program is a materialised series;
the calendar already groups it by `seriesID`. Adding the entity is additive and can
come later without reworking the materialiser.

## Suite tie-in

A program's upcoming sessions match the `SuitePlannedSession` shape on the
`SuiteActivity` channel (see `SUITE-HEALTH-SYNC.md`). Publishing them would let
FuelKit and RunKit prepare around planned training — the planned-session half of
that channel, currently unused on the LiftKit side.
