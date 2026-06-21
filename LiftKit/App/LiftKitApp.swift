import SwiftUI
import SwiftData
import UserNotifications

@main
struct LiftKitApp: App {
    @State private var vm = WorkoutViewModel()

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
                .preferredColorScheme(.dark)
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
    }
}

import AVFoundation
