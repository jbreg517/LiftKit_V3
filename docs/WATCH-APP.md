# LiftKit watch app — design

A wrist companion for a **live workout**: see the timer, complete rounds and reps,
and start a session without pulling the phone out. Explicitly **not** a standalone
app — the phone stays the place you build workouts, review history and edit plans.

RunKit already ships a watch app; this borrows its architecture wholesale where it
fits and says plainly where lifting differs. See `RunKit/RunKitWatch/`.

## Decisions

| Question | Decision |
|---|---|
| Target creation | Migrate LiftKit to **XcodeGen**, matching RunKit and FuelKit |
| Timer ownership | **The watch runs its own `HKWorkoutSession`** |
| v1 scope | Timed types (AMRAP / EMOM / Intervals / For Time) **+ reps completion** |
| Start-from-wrist menu | **Scheduled today + saved plans** |

## Why the watch runs the clock

watchOS suspends an ordinary app within seconds of the wrist dropping. An
`HKWorkoutSession` is what buys background execution, the always-on wrist-raise
display and live heart rate. A "dumb mirror" of the phone's timer would freeze the
moment you stopped looking at it — which is precisely when a lifter needs the EMOM
minute to keep ticking.

So the watch owns a real session, exactly like RunKit's `WatchWorkoutController`. The
phone link syncs *what to run* and *what happened* — never the running of it.

### The double-write trap

LiftKit already writes a workout to HealthKit at `endWorkout`
(`exportToHealthKitIfEnabled`). If the watch also saves one, a single session lands in
Health twice — and doubled active energy flows into FuelKit as real intake headroom.
Deduplicating afterwards is not possible; both look legitimate.

Rule, lifted from RunKit's `RecordingOwner`: **whichever device you tapped Start on
owns the session and is the only one that writes to Health.** The other shows what's
running and offers nothing else. It's a courtesy signal over `sendMessage`, not a
lock — out of range neither device knows about the other, and a hard block that
depended on connectivity would strand someone mid-workout.

## Transports

Three mechanisms, each chosen for a different lifetime. This is the part of RunKit's
design most worth copying exactly.

| Need | Mechanism | Why |
|---|---|---|
| The menu of runnable workouts | `updateApplicationContext` | Retained and replayed by the system, so the menu is on disk for free and survives relaunch |
| "I'm recording" / "round done" | `sendMessage` | An event with a short useful life. Application context would replay a stale "still running" hours later |
| The finished session | `transferFile` | Queued to disk and retried, so a workout survives the phone being out of range for its whole duration |

## Wire format

A new `LiftKit/Shared/` folder holds files compiled into **both** targets.

- **`WatchMenu`** — a flattened snapshot of what the watch can start: today's
  scheduled workouts, then saved plans. Carries the resolved exercise list and a
  `TimerConfig` per item, plus a `referenceID` back to the `WorkoutSchedule` or
  `WorkoutTemplate` so a finished session can be reconciled and a scheduled workout
  ticked off.
- **`WatchWorkoutPayload`** — the finished session: type, timings, per-set results
  (reps / duration / distance), rounds completed, RPE if asked.
- **`RecordingOwner`** — the double-write guard above.

**No SwiftData type crosses the wire.** `WorkoutTemplate` and `WorkoutSchedule` stay
on the phone; the watch refers to them by id only.

**Every field decodes with `decodeIfPresent` and a default.** The phone app and the
watch app update on independent schedules — a watch running last month's build will
be handed today's payload, and a synthesised decoder throws on any absent key, which
would blank the menu rather than degrade it. RunKit learned this the same way.

### Shared source files

Beyond the wire format, these move to (or are shared from) `Shared/` so the two
devices can't drift on semantics:

- `TimerType`, `TimerPhase`, `TimerConfig` — the definition of what an EMOM *is*.
- **`TimerEngine`** if it will build for watchOS. Sharing the engine itself, rather
  than reimplementing round/minute advance on the wrist, is the single biggest
  guard against the two devices disagreeing about what round you're on. It currently
  lives in the same file as `TimerConfig` and imports `UserNotifications`; splitting
  the file is likely a prerequisite.
- `WeightUnit` / `UnitSystem`, `Equipment` — formatting and labels.

## Screens

1. **Start** — today's scheduled workouts first, then saved plans. Empty state
   distinguishes "nothing scheduled" from "never synced" (the phone hasn't paired
   yet), because telling someone to open their phone when they've simply saved
   nothing would be wrong.
2. **Active — timed** (AMRAP / EMOM / Intervals / For Time): the clock, the current
   round or minute, the movement for this round, and one large **round complete**
   target. Haptic on each phase change — the wrist is better at this than the phone.
3. **Active — reps**: the current exercise, planned sets, and a tap to complete a set
   at its planned reps and weight. **No editing on the watch in v1** — adjusting
   weight on a small screen mid-set is worse than reaching for the phone, and the
   planned values are already right the overwhelming majority of the time.
4. **Summary** — duration, rounds/sets completed, then hand off to the phone.

## Phasing

The migration is sequenced so the risky part is proven before anything depends on it.

1. ~~**Migrate to XcodeGen, no watch target.**~~ **Done** — validated by a signed
   build that shipped; `LiftKit.xcodeproj` is now generated and gitignored.
2. ~~**Add the watch target + `Shared/` wire format.**~~ **Done** (menu sync only:
   the watch lists what it could run and starts nothing).

   **The watch app is not embedded in the iOS app yet.** Embedding requires a
   provisioning profile for `com.ferrixguild.liftkit.watchkitapp`, and that App ID
   can't be created while the developer account is locked. Enabling it early would
   break a currently-green TestFlight pipeline for no gain. So the target lives on
   its own scheme, compiled on every CI run (`Build watch app (compile check)`,
   unsigned) so it can't rot. The commented-out `dependencies` entry in
   `project.yml` is the single switch to flip once the App ID exists.
3. ~~**Timed workouts on the wrist**~~ and 4. ~~**Reps completion**~~ — **Done.**
   `WatchWorkoutController` owns the `HKWorkoutSession`, runs the block clock, and
   collects heart rate and active energy from `HKLiveWorkoutBuilder`. Round
   completion for AMRAP/For-Time, set completion for reps, pause that preserves
   remaining time rather than burning it, and hand-back via `transferFile`.

   **Phase advance is reimplemented, not shared, and that is a drift risk worth
   naming.** `TimerEngine.advancePhase()` on the phone is the source of truth; the
   watch mirrors it because the phone engine reaches for UIKit haptics and an audio
   engine while the wrist uses `WKInterfaceDevice`. What *is* shared is
   `TimerConfig` — the numbers — so the two can only ever disagree about what
   happens at a block's end, never about how long the block is. If `advancePhase()`
   changes, `WatchWorkoutController.advance()` must change with it.

   The phone imports finished workouts through an **on-disk inbox**, not an
   in-memory queue: the system can deliver a transferred file by relaunching the app
   in the background, and an in-memory queue would lose the workout if the process
   were killed before the UI ran. Import is idempotent on the payload id, because
   transfers can be redelivered.
5. **Polish** — complications, Live Activity handoff, always-on refinement.

## Risks

- **The migration is the real risk, not the watch app.** LiftKit's `.pbxproj` is
  hand-maintained and currently produces a working signed build with widgets, an App
  Group and a Live Activity. A generated project must reproduce all of it. This is
  why step 1 stands alone and gets its own validation build.
- **A third provisioning profile** is needed: `com.ferrixguild.liftkit.watchkitapp`.
  Codemagic fetches per bundle id (see `codemagic.yaml`), so that step needs a new
  entry, and the App ID needs creating in the developer portal.
- **No Mac available.** Everything is validated through CI, so each phase should be
  small enough to diagnose from a build log alone.
- **`TimerEngine` may not build for watchOS** unchanged. If it resists, the fallback
  is a shared pure-logic core (phase advance, round math) with the platform bits —
  notifications, audio — left per-target.
