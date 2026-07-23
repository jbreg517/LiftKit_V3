# Workout history import — spec & template

Lets a user bring their training history from another app into LiftKit. Runs
entirely on-device (no upload to any server), consistent with LiftKit's
privacy model. Post-launch feature.

## Two ways in

1. **Import a native export** from another app — LiftKit detects the format
   from the header row and maps it automatically.
2. **Fill in the generic template** ([`liftkit-import-template.csv`](liftkit-import-template.csv)) —
   for apps we don't recognize, or for hand-entered history. The app offers a
   "Download template" button that writes this same file to share/Files.

## Generic template columns

| Column | Required | Notes |
|---|---|---|
| `Date` | ✅ | `YYYY-MM-DD`. Groups sets into sessions with `Workout Name`. |
| `Workout Name` | — | Optional label; sets sharing a date + name form one session. |
| `Exercise` | ✅ | Free text; reconciled against the library (see below). |
| `Equipment` | — | Barbell / Dumbbell / Kettlebell / Machine / Cable / Bodyweight / Band / Other. Improves matching and the create-flow default. |
| `Set` | — | Set order within the exercise; defaults to file order. |
| `Weight` | — | Number; blank for bodyweight. |
| `Unit` | — | `kg` or `lb`; defaults to the app's unit setting. |
| `Reps` | — | Blank for timed holds. |
| `Duration (sec)` | — | For planks / timed work; leave `Reps` blank. |
| `RPE` | — | Optional. |
| `Notes` | — | Optional. |

## Source formats detected automatically

Detection is by header signature (delimiter is sniffed — comma or semicolon).
Column data confirmed from each app's current export (July 2026):

- **Strong** — `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE`. Equipment is embedded in the exercise name, e.g. `Bench Press (Barbell)`.
- **Hevy** — `title, start_time, end_time, description, exercise_title, superset_id, exercise_notes, set_index, set_type, weight_kg, reps, distance_km, duration_seconds, rpe` (may also carry `weight_lbs`). `set_type` distinguishes `warmup`/`normal`/`drop`/`failure`; `superset_id` groups supersets.
- **FitNotes** — `Date, Exercise, Category, Weight (kg), Weight (lbs), Reps, Distance, Distance Unit, Time, Notes, Kind`. `Category` maps well to muscle group / equipment hints.
- **Jefit** — exports CSV but with a looser, less consistent schema; treat as best-effort / lower priority.
- **LiftKit** — our own export (`exportFile` in Settings) round-trips through the same importer for backup/restore.

Apple Health is a separate future source (XML, not CSV; workout-level only, no
set detail).

## Exercise-name reconciliation

For every distinct exercise in the file:

1. **Extract an equipment hint** from the name where present — e.g. Strong/Hevy
   encode it as `Bench Press (Barbell)` → name `Bench Press`, equipment `Barbell`.
2. **Match** against the exercise library, in order: exact → normalized
   (lowercased, punctuation/plurals stripped, parenthetical removed) → fuzzy
   (token overlap / edit-distance above a threshold).
3. **If nothing matches**, collect it as an *unknown*. Before any data is
   written, show a **reconciliation screen** listing each unknown
   exercise + equipment combo, and for each let the user:
   - **Create it** (equipment prefilled from the parsed hint, editable), or
   - **Map** it to an existing exercise, or
   - **Skip** those rows.
4. **Remember** the user's choices so re-imports don't re-ask.

## Import mechanics

- Sessions are written as completed history (`isActive = false`) with the
  parsed dates; `SetRecord`s carry weight (normalized to the store's unit),
  reps or duration, and set type.
- **De-dupe**: skip a session whose date + name already exist (same rule
  FitNotes uses), so re-importing is safe.
- **Recompute PRs** after import via `PRDetectionService`.
- Show a summary: sessions added, sets added, exercises created, rows skipped.

## Rough effort

Medium (M–L). The parsing/mapping and the interactive reconciliation UI are the
bulk; the write + PR-recompute reuse existing services.
