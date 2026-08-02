# Training load

How LiftKit measures how hard a week of training was, and what it publishes to the rest of
the suite.

Implementation: [`LiftKit/Services/TrainingLoad.swift`](../LiftKit/Services/TrainingLoad.swift).
Arithmetic verification: `node tools/training-load-check.js`.

---

## Why not tonnage

Total weight lifted (weight × reps, summed) is the obvious strength metric and it is the
wrong headline.

Volume load is **dominated by exercise selection**. A squat moves several times the
absolute load of a curl for comparable stimulus, so a light upper-body week followed by a
heavy lower-body week produces a large swing that says nothing about how hard the training
was — it measures which body part was trained. Charted as a trend line across a mixed
block, it is close to meaningless, and it will read as "progress" to anyone who happens to
have shifted toward compound lower-body work.

Correcting it properly needs bar-path displacement, which no phone can measure.

Tonnage stays available as `WorkoutSession.totalVolume` and is still shown on the Progress
tab as a secondary figure. It is never the primary signal.

---

## Session RPE (sRPE)

**`load = RPE (1–10) × active minutes`**, in arbitrary units (AU).

Foster's session-RPE method. A 45-minute session at RPE 7 is 315 AU. The absolute number
means nothing on its own — the point is comparison against the same lifter's own weeks.

Three properties make it the right first metric:

1. **It never touches the bar weight**, so the exercise-selection distortion cannot reach
   it. A hard curl session and a hard squat session are both hard.
2. **It's validated across modalities**, including resistance training. One number spans a
   lift and a run, which is precisely what the suite needs — FuelKit can't chart two
   incompatible strength and cardio scales against each other.
3. **It's nearly free.** LiftKit already records `activeSeconds` (excluding the start
   countdown and any paused time), so the only missing input was the rating.

### Where the rating comes from

| Source | Meaning |
|---|---|
| `.entered` | The lifter rated the session as a whole. Always wins. |
| `.derived` | Averaged from the working sets they rated, because no session rating exists. |
| `.none` | Nothing to go on — the load is **nil**, never 0. |

The derived fallback is a genuinely different construct and is labelled as such wherever it
appears. Foster asks for one global rating of the session; the mean of individual set
ratings tends to run higher, because people rate the sets they thought were worth rating.
It's a usable stand-in, not an equivalent.

**Nil is not zero.** An unrated session was still training. Folding it in as 0 AU would make
a hard week look light, so every aggregate carries `ratedSessions` alongside `sessions` and
the UI says outright when the bars are an undercount.

### When it's asked for

On the workout-complete overlay, as an optional row of 1–10 chips, and editable afterwards
on any session in History.

Foster's protocol wants the rating about 30 minutes after finishing — ratings taken straight
off the last set skew high. The completion screen is earlier than that and is where the
lifter is actually looking, so LiftKit asks there and lets History replace a hasty answer
with a considered one.

Skipping is a first-class outcome. Forcing an answer buys a number at the cost of it
meaning anything.

---

## Derived figures

All of these return plain numbers. Nothing in this file decides whether a number is good.

### Weekly load

`weeklyLoads(_:weeks:)` — the last N weeks including the current one, oldest first.

Weeks with no training **are** included as zero. That's the opposite of the per-day rule
below, and the difference is deliberate: a bounded window has a known denominator, so a
zero week inside it is a fact about that week. A bare list of days has no denominator, so a
missing day means only "nothing was recorded".

### Acute:chronic workload ratio

Last 7 days against the average of the last 28. 1.0 means this week matches the recent
norm; 1.5 means half again as much.

Nil until 28 days of history exist. A ratio computed from two weeks of data is arithmetic
dressed up as information.

**The published "sweet spot" bands around this metric are contested** — it shares data
between numerator and denominator and is sensitive to how the windows are defined. LiftKit
shows the number with no band, no colour coding, and no interpretation.

### Monotony and strain

Foster monotony: mean daily load ÷ its standard deviation over 7 days, counting untrained
days as zero. Strain: weekly load × monotony.

**The direction reads backwards until you look at the formula.** High monotony means
*sameness*, not intensity. Identical training every day gives a tiny standard deviation and
therefore a large ratio; one big session in an otherwise empty week gives a large deviation
and a small ratio. Foster's interest was in high monotony combined with high load — a week
with no easy days and no rest — which is what strain expresses.

This was wrong in the first draft of both the code comment and the test, and is now pinned
by an explicit assertion in `training-load-check.js`, because getting it backwards in the UI
would invert the meaning of the number.

Monotony is nil when the week holds no load, and also in the degenerate case where all seven
days are identical — it's unbounded there, and nil is more honest than a number that only
looks finite because of floating point.

---

## Hard sets, and the muscle-balance fix

The hypertrophy literature's dose metric is **weekly hard sets per muscle group**, and it is
*inherently* per-muscle — which is exactly the distortion tonnage suffers from.

LiftKit already had the pieces: `SetType.warmup`, and `Exercise.primaryMuscle` /
`secondaryMuscles` with a half-credit rule in `muscleContributions`.

What it didn't have was the filter. The Muscle Balance chart counted **every logged set**,
warm-ups included, despite a comment claiming otherwise. That inflated the totals for anyone
who logs their warm-ups and made two lifters' charts incomparable depending on whether they
bothered. Now fixed.

`isHardSet(_:)` — a set counts unless it is a warm-up, **or** the lifter rated it below 5.

The literature strictly means sets taken near failure, which would count only rated sets.
Nobody rates every set, so the rule is *exclude what the lifter told us was easy*. An
**unrated** set counts: absence of a rating isn't evidence a set was easy, and dropping
unrated sets would collapse the count for the majority who never touch the RPE field.

The chart draws a dashed reference line at **10 sets per muscle per week** — a figure often
cited in the literature, shown on the 7-day range only (drawing it over a 30-day total would
compare a month's work against a weekly figure). It is labelled as a reference, not a
target.

---

## What gets published to the suite

Two fields added to `SuiteDailyLoad` (see [SUITE-HEALTH-SYNC.md](SUITE-HEALTH-SYNC.md)):

| Field | Contents |
|---|---|
| `activeMinutes` | Total active minutes that day. Absolute. |
| `sessionLoad` | The day's sessions, each `RPE × minutes`, **summed**. 0 when nothing was rated. |

Plus `perceivedEffort`, which LiftKit previously hard-coded to 0 and now populates with the
hardest single session of the day.

### Why `sessionLoad` is carried rather than recomputed

Because merging is only associative in that form. A reader combining two apps' days takes
the **max** of `perceivedEffort` (effort doesn't add) and the **sum** of `activeMinutes` —
so multiplying the merged values gives the wrong answer:

| | RPE | minutes | sRPE |
|---|---|---|---|
| Lift | 8 | 60 | 480 |
| Run | 5 | 40 | 200 |
| **Merged** | **8** (max) | **100** (sum) | **680** (sum) |

`8 × 100 = 800`, not 680. Summing the per-session products is correct; recomputing from
merged inputs is not. Pinned by an assertion in `training-load-check.js`.

`activeMinutes` is published even though HealthKit records workout duration, because reading
it from Health requires `HKObjectType.workoutType()` — a permission scope an app shouldn't
have to request just to draw a "minutes trained" row.

### `load` is deliberately unchanged

`SuiteDailyLoad.load` (the 0–1 producer-normalised figure) still comes from duration alone.
Two reasons:

1. Folding RPE into it would silently change what `load` means for readers already consuming
   it — RunKit's recovery awareness is built on today's semantics.
2. Worse, it would **mix units inside one percentile pool**: rated sessions measured in
   RPE×minutes against unrated ones measured in minutes. A lifter who rates some sessions
   and not others would see their own norm jump for no reason they could observe.

sRPE travels in its own field, where absence is visible as 0 rather than disguised as a low
number.

---

## Deliberately not built

- **A readiness score, a colour-coded ACWR band, or any verdict.** The ratio's bands are
  contested and LiftKit is not a coach.
- **Estimated 1RM per key lift** — Tier 2 in the FuelKit plan. LiftKit already knows the
  working weight per lift through Stronglifts progression, so this is a display and
  publishing job, not a data-model one. Next after this.
- **Switching `load` to sRPE.** See above.
- **Requiring a rating.** An optional field with honest gaps beats a mandatory one with
  garbage in it.
