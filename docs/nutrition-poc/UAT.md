# LiftKit — Nutrition POC: User Acceptance Tests

Companion to `REQUIREMENTS.md`. These are **manual acceptance tests** run on-device (the POC touches camera + HealthKit, which don't work in the Simulator for full coverage). Run the suites top-to-bottom; later suites assume the app is installed and Premium.

## How to run
- Build to a **physical iPhone** (camera + HealthKit require a real device + signed build with the HealthKit entitlement).
- Use a **Premium** account (Health tab is premium-gated).
- Have the **USDA API key** present in the build config.
- For burn-source tests, an **Apple Watch** (or pre-seeded Health energy data) is ideal; tests note the no-Watch fallback path too.

## Environment matrix
| Variable | Values to cover |
|---|---|
| Network | online · offline (airplane mode) |
| HealthKit | sharing ON (authorized) · OFF/denied · partially authorized |
| Energy data | Apple Watch present · no Watch (LiftKit estimate fallback) |
| Account | Premium · non-Premium |
| Data state | fresh install · upgrade over existing manual nutrition logs |

## Legend
Each case: **ID · Requirement · Preconditions · Steps · Expected**. Mark Pass/Fail/Blocked + notes.

---

## Suite A — Setup, permissions & gating

**UAT-A1 · D6/FR-034 · Premium gate**
Pre: non-Premium account. Steps: open Health tab. Expected: existing locked view shown; no food-logging UI exposed.

**UAT-A2 · FR-034/D10 · Opt-in card at top, default OFF**
Pre: fresh Premium install. Steps: open Health tab; do **not** enable Health sharing. Expected: an opt-in card sits at the **top of the Health tab**; Food Log section is visible and usable below it; no HealthKit permission prompt has appeared yet.

**UAT-A3 · §6.2/D10 · Enable Health sharing (card → confirm → relocate)**
Steps: tap the top-of-Health opt-in card. Expected: a confirmation explains what's shared and that it can be **turned off anytime in Settings**; on confirm, the system HealthKit sheet requests read (active/basal energy) + write (dietary energy, protein, carb, fat); after granting, the **card disappears from the Health tab** and an "Apple Health" toggle now appears in **Settings**.

**UAT-A4 · §6.2 · Deny Health, logging still works**
Pre: on the permission sheet, deny write. Steps: log a food. Expected: entry saves locally; a soft, dismissible "Turn on Apple Health sharing" hint appears; no crash; `healthKitSampleIDs` empty for that entry.

**UAT-A5 · §6.2 · Read-denial treated as no-data**
Pre: read access denied. Steps: view balance readout. Expected: no error; balance uses the LiftKit BMR + MET fallback (labeled "estimate").

**UAT-A6 · FR-040 · Camera permission**
Steps: tap Scan for the first time. Expected: camera permission prompt with the configured usage string; on grant, scanner opens; on deny, a clear message + path to search/manual.

**UAT-A7 · D10 · Disable from Settings**
Pre: Health sharing ON. Steps: Settings → toggle Apple Health OFF. Expected: a confirmation notes that data already written to Apple Health **remains** and can be removed in the Health app; further logging stops mirroring; the opt-in card **reappears** at the top of the Health tab.

**UAT-A8 · D9/FR-035 · Expenditure source default & switch**
Pre: Health ON, Watch energy present. Steps: open the "Expenditure source" control. Expected: default is **LiftKit**; switching to **Apple Health** recomputes the balance from HK basal+active; the two sources are never summed.

---

## Suite B — Food search (USDA)

**UAT-B1 · FR-001 · Basic search**
Steps: search "greek yogurt". Expected: ranked results with name/brand/serving within ~2 s; list scrollable.

**UAT-B2 · FR-001 · Debounce**
Steps: type quickly then pause. Expected: search fires after typing settles, not on every keystroke; no flicker/duplicate requests.

**UAT-B3 · FR-001 · No results**
Steps: search "asdfqwer". Expected: clear "No results" state with option to enter manually; no spinner stuck.

**UAT-B4 · NFR-2 · Timeout / slow network**
Pre: throttled network. Steps: search. Expected: graceful timeout (~10 s) with a retry affordance; no crash, no infinite spinner.

**UAT-B5 · FR-002 · Open detail**
Steps: tap a result. Expected: Food Detail sheet opens with listed serving, quantity = 1, live macro/kcal preview.

---

## Suite C — Barcode scan (Open Food Facts + fallback)

**UAT-C1 · FR-003 · Scan known product**
Steps: scan a common packaged item's UPC. Expected: OFF resolves it; Food Detail opens prefilled with brand/serving/macros.

**UAT-C2 · FR-003 · USDA fallback**
Pre: a UPC absent from OFF but present in USDA branded. Steps: scan. Expected: after the OFF miss, USDA branded resolves it; detail opens.

**UAT-C3 · FR-004 · Barcode not found**
Pre: an unknown/garbage barcode. Steps: scan. Expected: "No match — search or enter manually" with working buttons; never a dead end.

**UAT-C4 · FR-003 · Offline scan**
Pre: airplane mode. Steps: scan. Expected: clean "can't look up offline" message + manual/search path; no crash.

**UAT-C5 · FR-003 · Cancel scan**
Steps: open scanner, cancel. Expected: returns to Food Log unchanged.

---

## Suite D — Serving / quantity entry

**UAT-D1 · FR-002/D7 · Listed serving**
Steps: in detail, keep "1 container (170 g)", Add. Expected: logged macros = the per-serving values.

**UAT-D2 · D7 · Multiplier**
Steps: set quantity 1.5×. Expected: preview and logged macros scale exactly 1.5×.

**UAT-D3 · D7 · Switch to grams**
Steps: switch to grams, enter 100 g. Expected: macros recomputed from per-100g (= per-serving ÷ servingGrams × 100); preview matches.

**UAT-D4 · A6 · Calories derived from macros**
Steps: observe kcal in preview. Expected: kcal = 4·protein + 4·carb + 9·fat + 7·alcohol (Atwater), not necessarily the label number (OQ-1).

**UAT-D5 · A3/FR-005 · Alcohol manual entry**
Steps: manual entry, enter alcohol grams. Expected: alcohol grams saved locally; its calories included in the entry's kcal.

---

## Suite E — Meal logging & structure

**UAT-E1 · FR-010 · Sections present**
Expected: Breakfast / Lunch / Dinner / Snack sections render in the Food Log.

**UAT-E2 · FR-011 · Time-of-day auto-suggest**
Pre: device clock ~8am. Steps: start a new entry. Expected: meal type defaults to Breakfast; user can override before Add.

**UAT-E3 · FR-010 · Multiple snacks**
Steps: add two foods to Snack. Expected: both appear under Snack; totals reflect both.

**UAT-E4 · FR-013 · Totals update**
Steps: add a food. Expected: today's kcal + macro pills and the calorie bar update immediately to include it.

**UAT-E5 · FR-006 · Recent foods**
Steps: re-open search/recents after logging. Expected: the just-logged food appears in Recents for one-tap re-log.

---

## Suite F — Day navigation & prior-day editing

**UAT-F1 · FR-012 · Step back a day**
Steps: tap "‹". Expected: shows the previous day's entries and totals; header date updates.

**UAT-F2 · FR-012 · No future days**
Steps: try to step past today. Expected: cannot navigate beyond today.

**UAT-F3 · FR-012/013 · Edit a prior entry**
Pre: a prior day has an entry. Steps: tap it, change quantity, save. Expected: entry + that day's totals recompute; HealthKit samples updated (Suite H).

**UAT-F4 · FR-013 · Delete an entry**
Steps: delete an entry. Expected: removed from list; day totals recompute; HK samples deleted (Suite H).

**UAT-F5 · FR-012 · Return to today**
Expected: stepping forward returns to today with today's data intact.

---

## Suite G — Energy balance & targets

**UAT-G1 · FR-020 · Goal line intact**
Expected: existing DAILY ENERGY tiles (BMR/Maintain/Target) still compute and match pre-POC values for the same profile.

**UAT-G2 · FR-021/D9 · Balance with Apple Health source**
Pre: Health ON, Watch active/basal present, **Expenditure source = Apple Health**. Steps: log intake. Expected: balance = intake − (HK basal + HK active); source labeled "Apple Health"; LiftKit's own estimate is **not** added.

**UAT-G3 · §6.3/D9 · Balance with LiftKit source (default)**
Pre: **Expenditure source = LiftKit** (default), even with Watch data present. Expected: balance = intake − (BMR + per-day MET estimate); source labeled "LiftKit estimate"; HK energy is **ignored** (no double-count).

**UAT-G4 · FR-021 · Goal framing**
Steps: set goal = lose. Expected: balance presented in loss/gain/maintain terms (e.g., deficit shown favorably for a loss goal).

**UAT-G5 · FR-022 · Protein target uses goal weight**
Pre: goal weight set, different from current. Steps: view protein target. Expected: target = proteinPerLb × **goal** weight.

**UAT-G6 · FR-022 · Protein fallback to current**
Pre: no goal weight set. Expected: target = proteinPerLb × **current** weight; no error.

**UAT-G7 · FR-023 · Macro pills vs targets**
Steps: log foods. Expected: protein/carb/fat pills fill toward `macroTargets`; alcohol pill shows grams (no target).

**UAT-G8 · §6.3 · Source-missing fallback**
Pre: Expenditure source = Apple Health but **no** HK active/basal data. Expected: balance falls back to the LiftKit BMR + MET estimate rather than showing zero; labeled accordingly.

---

## Suite H — HealthKit mirroring

**UAT-H1 · FR-030 · Write on add**
Pre: Health ON. Steps: log a food; open Apple Health. Expected: matching Dietary Energy + Protein/Carbs/Fat entries appear, attributed to LiftKit, timestamped at log time.

**UAT-H2 · A3 · No alcohol type, calories still counted**
Steps: log a food/drink with alcohol grams. Expected: no "alcohol" sample in Health (none exists); Dietary Energy includes the alcohol calories.

**UAT-H3 · FR-031/§6.4 · Edit propagates**
Steps: edit a logged entry's quantity. Expected: in Health, the old samples are replaced by new ones reflecting the change (no duplicates).

**UAT-H4 · FR-031/§6.4 · Delete propagates**
Steps: delete an entry. Expected: its Health samples are removed.

**UAT-H5 · FR-033 · Workout write**
Steps: complete a LiftKit workout with Health ON. Expected: an HKWorkout with energy appears in Health attributed to LiftKit.

**UAT-H6 · §6.2 · Grant after prior local-only logs**
Pre: logged some foods with Health OFF, then enable Health. Expected: new entries mirror to Health; pre-existing local-only entries are not retroactively required to sync (documented behavior — confirm no crash/dupes).

**UAT-H7 · NFR-6 · HealthKit failure non-blocking**
Pre: simulate a write failure. Steps: log a food. Expected: local entry still saved; failure handled silently/soft-hinted; no crash.

---

## Suite I — Offline behavior

**UAT-I1 · NFR-1 · Manual entry offline**
Pre: airplane mode. Steps: log via manual entry. Expected: works fully.

**UAT-I2 · NFR-1 · Recents offline**
Pre: airplane mode, recents exist. Steps: re-log from Recents. Expected: works from local cache.

**UAT-I3 · NFR-1 · Day review offline**
Expected: prior-day data + totals + balance (fallback) all render offline.

**UAT-I4 · NFR-1 · Search/scan offline**
Expected: only fresh search/scan is blocked, with clean messaging; rest of the feature unaffected.

---

## Suite J — Migration (existing users)

**UAT-J1 · FR-MIG · Aggregate days preserved**
Pre: install over a build that has existing manual `NutritionDay` rows with macro totals. Steps: launch new build, open Health → prior days. Expected: each prior non-empty day shows its totals unchanged, represented as a single migrated manual entry; calorie/weight trends look identical to pre-upgrade.

**UAT-J2 · FR-MIG · No double-count**
Steps: compare a migrated day's total to its pre-upgrade value. Expected: identical (not doubled).

**UAT-J3 · FR-MIG · Mixed day**
Steps: on a migrated day, add a new food entry. Expected: day total = migrated manual entry + new entry; both visible.

**UAT-J4 · FR-MIG · Clear Health Data still works**
Steps: use existing "Delete Health Data". Expected: removes nutrition days/entries + profile + body metrics; workouts unaffected; no orphaned entries.

---

## Suite K — Privacy, theming & regression

**UAT-K1 · NFR-4 · Theming**
Expected: Food Log section, sheets, and balance readout use LiftKit colors/fonts/spacing; visually consistent with existing Health sections in light and dark.

**UAT-K2 · NFR-5 · Accessibility**
Steps: VoiceOver through Food Log, Add, Scan, day stepper. Expected: all controls have meaningful labels.

**UAT-K3 · FR-042 · Privacy copy**
Expected: onboarding/Health copy honestly reflects opt-in Health sharing + network lookups; no remaining absolute "nothing ever leaves your device" claim that contradicts lookups.

**UAT-K4 · NFR-3 · No off-device leakage to first-party**
Steps: monitor network during use. Expected: traffic only to USDA + Open Food Facts; no first-party analytics/telemetry of food or Health data.

**UAT-K5 · Regression · Existing Health features**
Expected: weight logging, BMR/TDEE tiles, weight/calorie trends, workout-burn section, body measurements all behave as before.

**UAT-K6 · NFR-8 · Version bump**
Expected: `AppVersion` incremented per convention for the build under test; visible in Settings.

---

## Exit criteria (POC accepted when)
- All Suite A, B, C, E, F, G, H happy-path cases Pass on a physical device.
- Migration suite (J) Passes with no data loss or double-count.
- Offline suite (I) Passes — the app never hard-depends on network or HealthKit.
- No P1 defects (crash, data loss, double-count, blocked logging) open.
- Open questions OQ-1..OQ-4 have a recorded decision (even if "accept for POC").
