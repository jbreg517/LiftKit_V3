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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
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
