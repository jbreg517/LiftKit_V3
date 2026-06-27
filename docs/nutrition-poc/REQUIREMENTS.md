# LiftKit — Nutrition / Food-Logging POC

**Requirements Document**
Status: Draft v0.2 (Proof of Concept)
Date: 2026-06-27
Owner: Jordan Bregger
Target: built **inside the existing LiftKit app**, Health tab, reusing the current SwiftData + SwiftUI + Theme stack.

---

## 1. Objective

Prove that LiftKit can let a user **look up foods (whole foods + UPC barcode), log them by meal, and see intake measured against an energy/macro target** — with **Apple HealthKit** as the cross-app interchange so the same calorie/macro/burn data can later be shared with a separate nutrition app, an Apple Watch, or the Health app.

The POC validates three risky things end-to-end:
1. The **food-lookup pipeline** (USDA FoodData Central + Open Food Facts) normalizing into one model.
2. The **HealthKit read/write plumbing** (write dietary energy + macros, read back active + basal energy) with graceful fallback.
3. The **logging + review UX** living naturally inside the existing premium Health tab without disrupting current behavior.

---

## 2. Scope

### 2.1 In scope (maps to user stories R1–R4)
- **R1** — Record meals; look up nutrition (macro-level) for whole foods and UPC-barcoded items; estimate calories, protein, fat, carbohydrate, **alcohol**.
- **R2** — Compare actual intake to estimated expenditure (BMR + exercise burn) against loss/gain/maintenance goals.
- **R3** — Track protein intake against a target tied to **goal** bodyweight.
- **R4** — Enter food per meal (Breakfast/Lunch/Dinner/Snack) per day, and review/edit prior days.

### 2.2 Out of scope (deferred — see §11)
- **R5** — Weekly-varying (cycling) calorie targets.
- **R6** — Recipes (saved reusable food groups).
- **R7** — Repeating multi-day meal plans / schedules.
- A standalone nutrition app (the POC lives inside LiftKit; HealthKit is wired so a separate app can join later).

### 2.3 Assumptions (locked unless revised)
- **A1** — Each app's own SwiftData store remains the **source of truth**; HealthKit is the **interchange**, not the primary store.
- **A2** — Food logging stays behind the **existing premium gate** (`UserProfile.isPremium`), inside the Health tab.
- **A3** — **Alcohol** is tracked **locally only** (no HealthKit dietary-alcohol type exists). Its calories ARE counted in dietary energy; only the gram breakdown stays local. A **manual override** for alcohol grams is available.
- **A4** — **Macro-only** for the POC: calories, protein, carbs, fat, alcohol. No micronutrients (sodium, fiber, sugar) displayed; fiber/sugar may be stored opportunistically but are not surfaced.
- **A5** — Text search → **USDA FoodData Central**; barcode → **Open Food Facts**, falling back to USDA branded on a miss.
- **A6** — **Calories are derived from macros** (Atwater 4/4/9/7), consistent with the existing `NutritionDay.calories`. Where a source lists a label calorie that differs from the Atwater sum, the derived value wins (see Open Question OQ-1).
- **A7** — Units follow the existing `unitSystem` (`imperial`/`metric`) setting.

---

## 3. Decision log (from requirements review)

| # | Decision | Rationale |
|---|---|---|
| D1 | POC = **core loop (R1–R4)** only | Smallest provable slice; recipes/cycling/planning deferred. |
| D2 | Energy model = **TDEE goal line + dynamic balance readout** (`intake − (basal + active)`) | Honors R2's "BMR + exercise burn" intent without double-counting the existing TDEE multiplier. |
| D3 | Protein target uses **goal weight when set, else current** | Matches R3 without breaking users who haven't set a goal weight. |
| D4 | UI = **collapsible "Food Log" section inside `HealthView`** + date stepper | Reuses the existing Health tab; no new top-level navigation. |
| D5 | HealthKit = **write macros/energy + workout active energy; read active+basal with fallback** to LiftKit's BMR + MET estimate | Best real-world coverage (works with or without an Apple Watch). |
| D6 | HealthKit is **opt-in and never blocks logging**; soft hint on denial | Preserves the app's privacy-first posture and offline-first feel. |
| D7 | Quantity = **listed serving OR grams, with a multiplier** | Friendly for packaged items and flexible for whole foods. |
| D8 | Meals = **fixed B/L/D/Snack; Snack holds multiple entries; time-of-day auto-suggest, overridable** | Matches R4; minimal UI. |
| D9 | Balance **expenditure source is user-selectable** (LiftKit estimate vs. Apple Health), **default LiftKit**; never sums both | Avoids active-energy double-count (OQ-2) while letting Watch users prefer Health. |
| D10 | Health **opt-in card at the top of the Health tab pre-opt-in; relocates to Settings after**, with explicit confirmation + a "can be turned off" notice | Discoverable consent, then out of the way (OQ-3). |
| D11 | USDA API key via **CI secret env var injected into a gitignored xcconfig** (template committed) | Keeps the key out of source control (OQ-4). |

---

## 4. Architecture summary

```
LiftKit (this app)                         Apple HealthKit
─────────────────                          ──────────────────────────────
SwiftData store (truth)                    on-device · encrypted · per-type
  • FoodItem / FoodEntry  ── writes ──▶     consent · iCloud E2E sync
  • NutritionDay rollup        dietary energy + protein/carb/fat
  • alcohol (LOCAL ONLY)                    + workout active energy
                          ◀── reads ───
                              active + basal energy (for balance readout)
Networking (NEW, greenfield)
  • USDAFoodDataClient (text search; API key)
  • OpenFoodFactsClient (barcode; no key, UA header)
  • Normalizer → FoodItem
Camera (NEW): VisionKit DataScannerViewController → UPC string
```

**Layers touched:** data model, networking (new), barcode scanning (new), HealthKit bridge (new), Health-tab UI, Info.plist/entitlements/privacy manifest.

---

## 5. Data model

> All new `@Model` types MUST be added to the schema in `LiftKit/App/LiftKitApp.swift` (`LiftKitStore`), every attribute MUST have a default, and relationships MUST be optional (CloudKit compatibility — see NFR-7). New `.swift` files MUST be placed in the correct Xcode group path.

### 5.1 New: `FoodItem` (a looked-up / cached canonical food)
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | default `UUID()` |
| `name` | String | "Greek Yogurt, plain" |
| `brand` | String? | nil for whole foods |
| `barcode` | String? | UPC/EAN when known |
| `sourceRaw` | String | `usda` / `off` / `manual` |
| `servingDescription` | String | e.g. "1 container (170 g)" |
| `servingGrams` | Double | grams per listed serving (for grams↔serving math) |
| `proteinGPerServing` | Double | |
| `carbGPerServing` | Double | |
| `fatGPerServing` | Double | |
| `alcoholGPerServing` | Double | usually 0; manual override supported |
| `createdAt` / `lastUsedAt` | Date | powers "recent foods" + offline cache |

### 5.2 New: `FoodEntry` (a serving logged on a day)
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `loggedAt` | Date | timestamp of the entry |
| `mealTypeRaw` | String | `breakfast`/`lunch`/`dinner`/`snack` |
| `quantity` | Double | number of servings (or grams ÷ servingGrams) |
| `enteredAsGrams` | Bool | how the user entered it (display only) |
| `proteinG`,`carbG`,`fatG`,`alcoholG` | Double | **snapshotted at log time** (so later edits to `FoodItem` don't rewrite history) |
| `foodItem` | FoodItem? | optional link to canonical food |
| `healthKitSampleIDs` | String | comma-joined UUIDs of the HK samples this entry created (for edit/delete sync); empty if not mirrored |
| `nutritionDay` | NutritionDay? | parent day |

### 5.3 Changed: `NutritionDay`
- Gains a `entries: [FoodEntry]` relationship.
- The four macro totals become the **sum of the day's entries** (recomputed on add/edit/delete). Existing charts (`calorieSeries`, `adaptiveInsight`, trends) keep reading `NutritionDay` unchanged.

### 5.4 Migration (highest-risk item — FR-MIG)
- Existing users have `NutritionDay` rows holding **aggregate** grams and **no entries**.
- On first launch of the new build, for each non-empty `NutritionDay`, create **one synthetic `FoodEntry`** (`source = manual`, `mealType = snack`, macros = the existing aggregate, `foodItem = nil`).
- Thereafter `NutritionDay` totals = `sum(entries)`. No data is lost and no day is double-counted.
- The existing manual "Log Macros" quick-add becomes a `manual` `FoodEntry` (it no longer writes the aggregate fields directly).

---

## 6. HealthKit integration spec

### 6.1 Types
| Direction | HealthKit type | Source/use |
|---|---|---|
| **Write** | `dietaryEnergyConsumed` | per `FoodEntry`, kcal = Atwater(all macros incl. alcohol) |
| **Write** | `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal` | per `FoodEntry` |
| **Write** | `HKWorkout` w/ `totalEnergyBurned` | on LiftKit workout completion (seeds the shared pool) |
| **Read** | `activeEnergyBurned` | "active" component of the balance readout |
| **Read** | `basalEnergyBurned` | "basal" component of the balance readout |

- **No alcohol sample** (no type). Alcohol calories are still included in the `dietaryEnergyConsumed` value so the calorie picture is complete.
- Samples carry metadata: `HKMetadataKeyWasUserEntered = true`, food name, and meal type (custom key).

### 6.2 Permission & opt-in (D6, D10)
- Integration is **opt-in**. Default OFF.
- **Placement:** before opt-in, a prominent **opt-in card sits at the top of the Health tab**. After opt-in, that card disappears and the toggle lives in **Settings**.
- **Enable flow:** tapping the card shows a **confirmation** explaining what's shared (writes dietary energy + macros; reads active/basal energy) and that it can be **turned off anytime in Settings**; on confirm, request read+write authorization for the §6.1 types.
- **Disable:** turning the Settings toggle off stops further mirroring; a confirmation notes that data already written to Apple Health **stays there** and can be removed in the Health app.
- HealthKit **hides read-denial** — treat empty reads as "no data," never as an error.
- Food logging works **fully without HealthKit** (own store is truth). If write permission is denied/unavailable, log locally, set `healthKitSampleIDs = ""`, and show a soft, dismissible "Turn on Apple Health sharing" hint. Mirroring resumes for new entries once granted.

### 6.3 Balance readout & expenditure source (D5, D9)
The balance = `intake − (basal + active)`. The expenditure side comes from a **single user-selected source** (never summed across providers), set by an **"Expenditure source"** control, **default LiftKit**:
- **LiftKit (default):** basal = `HealthCalculations.bmr(...)`; active = LiftKit's per-day MET workout-burn (existing `burn(for:)` logic).
- **Apple Health:** basal = HealthKit `basalEnergyBurned` (else BMR formula if absent); active = HealthKit `activeEnergyBurned` (else MET estimate if absent).
- The readout labels the estimate as rough and shows the **active source** currently in use.
- LiftKit still **writes** its workout energy to Apple Health (FR-033) regardless of this selection; the selection only governs which numbers feed the balance, so a Watch user who keeps "LiftKit" won't double-count.

### 6.4 Edit / delete propagation
- **Edit** an entry → delete the old HK samples (by stored UUIDs), write new ones, update `healthKitSampleIDs`.
- **Delete** an entry → delete its HK samples.
- These run best-effort; a HealthKit failure must not block the local mutation.

---

## 7. Functional requirements

### Food lookup & entry
- **FR-001** (R1) Text search queries USDA FDC and returns a ranked list (name, brand, serving) within ~2 s typical; input is debounced.
- **FR-002** (R1) Tapping a result opens a **Food Detail** sheet: serving picker (listed servings ↔ grams), quantity multiplier, meal-type selector, live macro/kcal preview, **Add**.
- **FR-003** (R1) Barcode scan opens a full-screen camera (VisionKit `DataScannerViewController`); a detected UPC resolves via Open Food Facts, falling back to USDA branded; on success it opens Food Detail prefilled.
- **FR-004** (R1) Barcode **not found** → clear "No match — search or enter manually" path; never a dead end.
- **FR-005** (R1) Manual entry (current "Log Macros") remains available and is stored as a `manual` `FoodEntry`. Alcohol grams are editable here (A3).
- **FR-006** (R1) "Recent foods" surfaces previously logged `FoodItem`s for one-tap re-logging, available **offline** from the local cache.

### Meal structure & day review
- **FR-010** (R4) Day shows **Breakfast / Lunch / Dinner / Snack** sections; Snack holds multiple entries; each section lists its entries with per-entry macros/kcal.
- **FR-011** (R4) New entries auto-suggest a meal type by time of day; the user can override before adding.
- **FR-012** (R4) A **date stepper** navigates to prior days; prior-day entries can be viewed, edited, and deleted; "today" is the default.
- **FR-013** (R4) Edits/deletes recompute the day's `NutritionDay` totals and propagate to HealthKit (FR-031).

### Energy & targets
- **FR-020** (R2) Keep the existing TDEE-based **goal calorie** line as the target.
- **FR-021** (R2) Add a **balance readout** = `intake − (basal + active)` per §6.3, with source labeling and loss/gain/maintain framing.
- **FR-022** (R3) Compute the **protein target** from **goal bodyweight × g/lb** when a goal weight is set, else from current weight; show intake-vs-target.
- **FR-023** (R2/R3) Today's totals (kcal + macro pills) reflect the sum of logged entries and compare against `goalCalories`/`macroTargets`.

### HealthKit
- **FR-030** (R1) On add, mirror each `FoodEntry` to HealthKit (energy + 3 macros) and store the sample UUIDs.
- **FR-031** (R1) On edit/delete, propagate to HealthKit per §6.4.
- **FR-032** (R2) Compute the balance's expenditure from the **selected source** per §6.3 (default LiftKit), reading HealthKit active/basal only when "Apple Health" is selected; never sum providers.
- **FR-033** LiftKit writes completed workouts to HealthKit as `HKWorkout` with energy (seeds the pool for a future nutrition app), independent of the §6.3 source selection.
- **FR-034** (D6/D10) Opt-in **card at the top of the Health tab** pre-opt-in (with a confirmation + a "can be turned off in Settings" notice); it **relocates to a Settings toggle** after opt-in; disable confirmation, permission handling, and soft-hint behavior per §6.2.
- **FR-035** (D9) Provide an **"Expenditure source"** control (LiftKit estimate / Apple Health), default LiftKit, with the chosen source reflected in the balance readout.

### Platform / privacy
- **FR-040** Add `NSCameraUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, and the HealthKit capability/entitlement.
- **FR-041** USDA API key supplied via a **CI secret env var** (Codemagic), injected at build time into a **gitignored `Secrets.xcconfig`** (a committed `Secrets.xcconfig.template` documents the key name); never hardcoded or committed. Open Food Facts requests send a descriptive `User-Agent`. (Note: any client-embedded key is extractable from the binary — acceptable for this free, public-data, rate-limited key; see OQ-4.)
- **FR-042** Update `PrivacyInfo.xcprivacy` / App Store privacy answers for Health & Fitness usage; refine onboarding "data stays on your device" copy to reflect opt-in Health sharing and network lookups.

---

## 8. Non-functional requirements
- **NFR-1 (Offline-first)** Manual entry, recent/cached foods, day review, and balance (via fallback) all work with no network. Only fresh search/barcode lookup requires connectivity, with a clean offline state.
- **NFR-2 (Performance)** Search debounced; typical result < 2 s; lookups time out gracefully (~10 s) with a retry affordance.
- **NFR-3 (Privacy)** No third-party analytics; food data and Health data never sent to first-party servers; Health usage is opt-in and never used for ads/tracking.
- **NFR-4 (Theming)** Reuse `LKColor`/`LKFont`/`LKSpacing`/`LKRadius` and existing button styles; the Food Log section is visually indistinguishable in style from current Health sections.
- **NFR-5 (Accessibility)** VoiceOver labels on all new controls (scan, add, day stepper), matching existing patterns.
- **NFR-6 (Resilience)** Any HealthKit/network failure degrades gracefully and never blocks a local mutation or crashes.
- **NFR-7 (CloudKit compatibility)** All new model attributes defaulted; relationships optional; no unique constraints — preserving opt-in iCloud sync.
- **NFR-8 (Versioning)** Bump `AppVersion` (+0.01) per the project convention on each commit/push.

---

## 9. UI / layout spec

Inside `HealthView.premiumContent`, after the existing intake summary:

```
DAILY ENERGY      [BMR] [Maintain] [Target]
BALANCE           intake − (basal + active)   [src: Health | estimate]
▼ FOOD LOG                         ‹  Fri Jun 27  ›
   Breakfast                                   +
     • Greek yogurt 1 cup        180 kcal  18P
   Lunch                                       +
   Dinner                                      +
   Snack                                       +
   ── today: 1,650 / 2,100 kcal · P 120/150 ──
WEIGHT · TRENDS · BURN · MEASUREMENTS ...
```

- **New sheets/screens:** Food Search (search field + results), Barcode Scan (camera), Food Detail (serving/quantity/meal + Add), entry edit/delete (tap an entry).
- **Day stepper** at the Food Log header; default today, cannot exceed today.
- The existing manual "Log Macros" button remains as a fallback within the section.
- **Health opt-in card:** before opt-in, a prominent card at the **top of the Health tab** ("Connect Apple Health — share calories & macros; turn off anytime"). After opt-in it disappears.
- **Settings (post-opt-in):** an "Apple Health" toggle (with the disable confirmation) **plus** the **"Expenditure source"** control (LiftKit estimate / Apple Health, default LiftKit), each with a one-line explanation.

---

## 10. Traceability

| User story | Functional requirements |
|---|---|
| R1 (lookup + barcode + macros) | FR-001..006, FR-030, FR-040, FR-041 |
| R2 (intake vs expenditure) | FR-020, FR-021, FR-023, FR-032, FR-033 |
| R3 (protein vs goal-weight target) | FR-022, FR-023 |
| R4 (per-meal entry + prior-day review) | FR-010..013, FR-031 |

---

## 11. Deferred / future
- **R5** Weekly calorie cycling — `WeeklyCaloriePlan`, date-aware `goalCalories`.
- **R6** Recipes — `Recipe` (yield-based), one-tap re-log.
- **R7** Meal planning — `PlannedMeal` recurring schedules (mirror `WorkoutSchedule`'s dated-row pattern); planned→logged lifecycle.
- **Standalone nutrition app** sharing via the same HealthKit types; Premium entitlement relay across apps.

---

## 12. Resolved questions & risks
- **OQ-1 (RESOLVED)** Calories are **derived** from macros (Atwater); a package's printed kcal is not displayed when it differs. See A6.
- **OQ-2 (RESOLVED)** **No double-count:** the balance's expenditure comes from a **single user-selected source** (default **LiftKit**); see D9/§6.3. LiftKit still writes its workout energy to Health for the shared pool.
- **OQ-3 (RESOLVED)** Opt-in **card at the top of the Health tab**, relocating to **Settings** after opt-in, with a confirmation + a "can be turned off" notice. See D10/§6.2.
- **OQ-4 (RESOLVED)** USDA key via **CI secret env var → gitignored `Secrets.xcconfig`**; client-embedded keys remain extractable (acceptable for this key). See D11/FR-041.
- **R-1 (risk)** Migration (FR-MIG) is the highest-risk change; needs dedicated tests (see UAT §Migration).
- **R-2 (risk)** Open Food Facts data quality/coverage varies; barcode misses must route cleanly to search/manual.
