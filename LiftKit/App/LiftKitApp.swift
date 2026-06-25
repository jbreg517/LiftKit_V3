import SwiftUI
import SwiftData
import UserNotifications

@main
struct LiftKitApp: App {
    @State private var vm = WorkoutViewModel()
    @AppStorage("appearance") private var appearance = "system"

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // follow system
        }
    }

    init() {
        requestNotificationPermission()
        configureAudioSession()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            WorkoutEntry.self,
            SetRecord.self,
            PersonalRecord.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            UserProfile.self,
            WorkoutSchedule.self,
            BodyMetric.self,
        ])

        // iCloud sync is opt-in (default OFF) and only works on a properly
        // signed build with the iCloud/CloudKit entitlement (i.e. App Store /
        // TestFlight). On the current unsigned/AltStore build the flag stays
        // off, so the store is local-only and nothing leaves the device.
        let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        func makeContainer(cloud: Bool) throws -> ModelContainer {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: cloud ? .automatic : .none
            )
            return try ModelContainer(for: schema, configurations: [config])
        }

        do {
            return try makeContainer(cloud: useICloud)
        } catch {
            // If CloudKit setup fails (e.g. missing entitlement), fall back to
            // a local-only store rather than crashing.
            if useICloud, let local = try? makeContainer(cloud: false) {
                return local
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView(vm: vm)
                .preferredColorScheme(preferredScheme)
        }
        .modelContainer(sharedModelContainer)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
    }
}

// MARK: - Root Tab View
struct RootTabView: View {
    @Bindable var vm: WorkoutViewModel
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        TabView {
            WorkoutHomeView(vm: vm)
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            HistoryView(vm: vm)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(LKColor.accent)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { _ in })) {
            OnboardingView { hasOnboarded = true }
        }
    }
}

// MARK: - First-run onboarding
struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LKColor.background.ignoresSafeArea()
            VStack(spacing: LKSpacing.lg) {
                Spacer()
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 60))
                    .foregroundColor(LKColor.accent)
                Text("Welcome to LiftKit")
                    .font(LKFont.title)
                    .foregroundColor(LKColor.textPrimary)

                VStack(alignment: .leading, spacing: LKSpacing.md) {
                    featureRow("timer", "Lift & WOD timers", "Reps, AMRAP, EMOM, intervals and more.")
                    featureRow("chart.line.uptrend.xyaxis", "Auto progression", "Weights step up when you hit all your reps.")
                    featureRow("lock.shield.fill", "Private by design", "Your data stays on your device.")
                }
                .padding(.horizontal, LKSpacing.lg)

                Spacer()
                Button { onDone() } label: { Text("Get Started") }
                    .buttonStyle(LKPrimaryButtonStyle())
                    .padding(.horizontal, LKSpacing.lg)
                Text("LiftKit is a tracking tool, not medical advice. Consult a professional before starting any exercise program.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LKSpacing.xl)
                Spacer().frame(height: LKSpacing.md)
            }
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: LKSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(LKColor.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Text(subtitle)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
            }
            Spacer()
        }
    }
}

import AVFoundation
