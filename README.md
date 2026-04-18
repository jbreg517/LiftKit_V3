# LiftKit — iOS Workout Timer & Tracker

> **No accounts. No ads. No B.S.**

Fast, no-frills workout timer and tracker. Six timer modes, PR detection, workout templates, fully offline.

**Version:** 1.1.0 · **Target:** iOS 17+ · **Language:** Swift 5.9 / SwiftUI

---

## Project Structure

```
LiftKit/
├── LiftKit/                        ← Main app target
│   ├── App/
│   │   └── LiftKitApp.swift        ← @main entry point, tab bar
│   ├── Theme/
│   │   └── Theme.swift             ← Colours, fonts, spacing, button styles
│   ├── Enums/
│   │   ├── TimerType.swift         ← AMRAP / EMOM / For Time / Intervals / Reps / Manual
│   │   ├── TimerPhase.swift        ← idle / work / rest / complete
│   │   ├── Equipment.swift         ← Barbell, Dumbbell, etc.
│   │   ├── ExerciseCategory.swift  ← Push, Pull, Legs, Core, Cardio, Olympic, Custom
│   │   ├── WeightUnit.swift        ← lb / kg with conversion
│   │   └── PRType.swift            ← maxWeight / maxReps / maxVolume
│   ├── Models/                     ← SwiftData @Model classes
│   │   ├── Exercise.swift
│   │   ├── WorkoutSession.swift
│   │   ├── WorkoutEntry.swift
│   │   ├── SetRecord.swift
│   │   ├── PersonalRecord.swift
│   │   ├── WorkoutTemplate.swift   ← includes TemplateExercise
│   │   ├── UserProfile.swift
│   │   └── WorkoutSchedule.swift
│   ├── Services/
│   │   ├── TimerEngine.swift       ← Wall-clock timer, all 6 modes, background notifications
│   │   ├── ExerciseLibrary.swift   ← 60+ built-in exercises, seeds on first launch
│   │   ├── WeightCache.swift       ← Auto-populates last weight from history
│   │   ├── PRDetectionService.swift← Detects new personal records after each set
│   │   ├── HapticManager.swift     ← buttonTap / setLogged / personalRecord
│   │   └── ScreenSleepManager.swift← Reference-counted idle timer disable
│   ├── ViewModels/
│   │   └── WorkoutViewModel.swift  ← Central @Observable state, workout lifecycle
│   └── Views/
│       ├── Workout/
│       │   ├── WorkoutHomeView.swift       ← Tab 1: hero button, calendar, plans
│       │   ├── WorkoutTypePickerView.swift ← 2-column type grid sheet
│       │   ├── WorkoutSetupView.swift      ← Type-specific setup + session/exercise cards
│       │   ├── ActiveWorkoutView.swift     ← Full-screen active workout (all 6 types)
│       │   └── CreateWorkoutView.swift     ← Quick workout creation form
│       ├── History/
│       │   └── HistoryView.swift           ← Session list + WorkoutDetailView
│       ├── Progress/
│       │   └── ProgressView.swift          ← Stats, PR board, charts
│       ├── Settings/
│       │   └── SettingsView.swift          ← Prefs, privacy policy, disclaimer
│       ├── Auth/
│       │   └── LoginView.swift             ← Apple Sign In + local premium activation
│       ├── Calendar/
│       │   ├── WorkoutCalendarView.swift   ← Monthly calendar widget (premium)
│       │   └── ScheduleEditView.swift      ← Create/edit scheduled workouts
│       └── Shared/
│           └── NumberEntrySheet.swift      ← Numeric entry sheet (used everywhere)
├── LiftKitTests/
│   ├── TimerEngineTests.swift              ← 19 unit tests for TimerEngine
│   └── FeatureGapTests.swift               ← 24 unit tests for data/features
└── LiftKitUITests/
    ├── LiftKitUITests.swift                ← 18 core UI tests
    ├── HomePageUITests.swift               ← 16 home page UI tests
    └── WorkoutTimerUITests.swift           ← 36 timer/setup UI tests
```

---

## Setting Up in Xcode

> You must have macOS with Xcode 15.2+ installed. All source files are in this repo — you only need to create the Xcode project wrapper.

### Step 1 — Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Fill in:
   - **Product Name:** `LiftKit`
   - **Bundle Identifier:** `com.yourname.liftkit`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** SwiftData ✅
4. **Save to:** the `LiftKit/` folder that already exists in this repo (the project will merge with the existing files)

### Step 2 — Add source files

1. In Xcode's Project Navigator, right-click the `LiftKit` group → **Add Files to "LiftKit"**
2. Add each folder: `App/`, `Theme/`, `Enums/`, `Models/`, `Services/`, `ViewModels/`, `Views/`
3. Make sure **"Copy items if needed"** is **unchecked** (files are already in place) and **"Create groups"** is selected

### Step 3 — Add frameworks

The app uses only Apple frameworks. In **Build Phases → Link Binary With Libraries**, confirm these are present (Xcode adds them automatically for SwiftUI projects):
- `SwiftData.framework`
- `Charts.framework`
- `UserNotifications.framework`
- `AuthenticationServices.framework`
- `AVFoundation.framework`

### Step 4 — Info.plist entries

Add these keys to `Info.plist`:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>LiftKit uses notifications to alert you when timer phases change while the app is in the background.</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Step 5 — Signing

1. Select the project root → **Signing & Capabilities**
2. Set your **Team** to your Apple Developer account
3. **Bundle Identifier** must match Step 1
4. Enable **Sign in with Apple** capability

### Step 6 — Test targets

1. The `LiftKitTests/` and `LiftKitUITests/` folders contain the test files
2. Add them to the respective test targets Xcode created
3. In the test target's **Build Settings**, set `@testable import LiftKit`

### Step 7 — Build & Run

Press **⌘R** to build and run on the simulator or a connected device.

---

## Building for AltStore / Sideloading

```bash
# On your Mac (via SSH or remote desktop):

# 1. Archive
xcodebuild archive \
  -scheme LiftKit \
  -archivePath ./build/LiftKit.xcarchive \
  -destination "generic/platform=iOS"

# 2. Export unsigned IPA for AltStore
xcodebuild -exportArchive \
  -archivePath ./build/LiftKit.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions_AltStore.plist
```

**ExportOptions_AltStore.plist** (create this file):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

---

## Codemagic CI/CD

Push to `main` on GitHub account **jbreg517** and Codemagic will build automatically.

Sample `codemagic.yaml`:
```yaml
workflows:
  ios-workflow:
    name: LiftKit iOS Build
    max_build_duration: 60
    environment:
      xcode: latest
      cocoapods: default
    scripts:
      - name: Build
        script: |
          xcodebuild \
            -scheme LiftKit \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath DerivedData \
            build
      - name: Test
        script: |
          xcodebuild test \
            -scheme LiftKit \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -derivedDataPath DerivedData
    artifacts:
      - DerivedData/Build/**/*.ipa
```

---

## Requirements Coverage

| Req | Feature | Status |
|-----|---------|--------|
| R-01 | Six timer types | ✅ |
| R-02 | Type-specific setup screens | ✅ |
| R-03 | Visually distinct active screens | ✅ |
| R-04 | AMRAP rounds counter with +/- | ✅ |
| R-05 | EMOM cycles per minute | ✅ |
| R-06 | For Time elapsed + time cap + Mark Complete | ✅ |
| R-07 | Intervals Work/Rest phase labels + round counter | ✅ |
| R-08 | Reps set circles, tap to complete | ✅ |
| R-09 | Rest timer auto-starts after set | ✅ |
| R-10 | Manual count-up timer | ✅ |
| R-11 | Weight +5/−5 adjustments | ✅ |
| R-12 | Completed set reps adjustable | ✅ |
| R-13 | Weight auto-populates from last session | ✅ |
| R-14 | Tap-to-type number entry sheet | ✅ |
| R-15 | Save as template from active screen | ✅ |
| R-16 | Templates sorted by most recently used | ✅ |
| R-17 | Tapping template loads setup | ✅ |
| R-18 | Notes field on setup screen | ✅ |
| R-19 | Notes displayed during workout | ✅ |
| R-20 | History sorted newest first | ✅ |
| R-21 | History row: name, badge, date, duration, count | ✅ |
| R-22 | Workout detail: actual vs planned weight/reps | ✅ |
| R-23 | "Do Again" repeats past workout | ✅ |
| R-24 | PR tracking per exercise | ✅ |
| R-25 | PR banner on new record | ✅ |
| R-26 | Progress tab: stats, PR board, chart, weekly volume | ✅ |
| R-27 | Exercise chart filterable by date range | ✅ |
| R-28 | Settings: rest, sound, haptics | ✅ |
| R-29 | 55 sarcastic completion messages (exact list) | ✅ |
| R-30 | Haptic feedback at key events | ✅ |
| R-31 | Sound toggle on active toolbar | ✅ |
| R-32 | Timer immune to screen sleep | ✅ |
| R-33 | Screen stays awake during timer | ✅ |
| R-34 | Timer continues in background | ✅ |
| R-35 | Local notifications at phase boundaries | ✅ |
| R-36/37 | Free 5 templates / Premium 10 | ✅ |
| R-38 | Login sheet from home header | ✅ |
| R-39 | Calendar: gold history dots, green schedule dots | ✅ |
| R-40 | Calendar → session detail | ✅ |
| R-41 | Calendar → schedule editor | ✅ |
| R-42 | Scheduled workout CRUD | ✅ |
| R-43 | Lbs/Kg per exercise | ✅ |
| R-44 | Apple Sign In | ✅ |
| R-45 | No credential storage (identifier only) | ✅ |
| R-46 | Pre-built exercise library | ✅ (60+ exercises) |
| R-47 | Auto-populate last weight/reps | ✅ |
| R-48 | Premium workout tracking over time | ✅ |
| R-49 | All Saved Plans view (premium > 10) | ✅ |
| R-50 | Swift / Codemagic ready | ✅ |
| R-51 | GitHub: jbreg517 | ✅ (push repo) |
| R-52 | AltStore sideload | ✅ (see above) |
| R-53 | All iPhone/iPad layouts | ✅ (SwiftUI adaptive) |

---

## Design System Quick Reference

| Token | Value |
|-------|-------|
| Background | `#000000` (true black) |
| Surface | `#1C1C1E` |
| Accent (gold) | `#D4A843` |
| Work (green) | `#22C55E` |
| Rest (blue) | `#3B82F6` |
| Danger (red) | `#EF4444` |
| Timer font | 112pt Black Monospaced |

---

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Data:** SwiftData (iOS 17+)
- **Charts:** Swift Charts
- **Auth:** AuthenticationServices (Sign in with Apple)
- **Notifications:** UserNotifications
- **Haptics:** UIImpactFeedbackGenerator
- **Audio:** AudioToolbox system sounds
- **Zero third-party dependencies**
