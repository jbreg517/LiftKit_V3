import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct LiftKitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            HealthProfile.self,
            NutritionDay.self,
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
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var quickActions = QuickActions.shared
    @Query private var templates: [WorkoutTemplate]
    @Query private var schedules: [WorkoutSchedule]

    var body: some View {
        TabView(selection: $vm.selectedTab) {
            WorkoutHomeView(vm: vm)
                .tag(0)
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            HistoryView(vm: vm)
                .tag(1)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ProgressView()
                .tag(2)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }

            HealthView(vm: vm)
                .tag(3)
                .tabItem {
                    Label("Health", systemImage: "heart.text.square.fill")
                }

            SettingsView()
                .tag(4)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(LKColor.accent)
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { _ in })) {
            OnboardingView { hasOnboarded = true }
        }
        .onAppear { handlePendingQuickAction() }            // cold launch
        .onChange(of: quickActions.pending) { _, _ in
            handlePendingQuickAction()                       // warm launch
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { refreshQuickActions() }
        }
    }

    // MARK: Quick actions (Home Screen long-press)

    /// Rebuild the icon's quick actions: today's scheduled workout + up to 3
    /// favorite templates. Refreshed whenever the app backgrounds.
    private func refreshQuickActions() {
        let cal = Calendar.current
        let todays = schedules.first {
            !$0.isCompleted && $0.template != nil && cal.isDateInToday($0.date)
        }
        let favorites = templates
            .filter { $0.isFavorite }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(3)
            .map { (id: $0.id, name: $0.name) }
        QuickActions.updateShortcuts(scheduledName: todays?.template?.name,
                                     favorites: Array(favorites))
    }

    private func handlePendingQuickAction() {
        guard let type = quickActions.pending else { return }
        quickActions.pending = nil
        vm.selectedTab = 0   // Workout tab hosts the setup sheet

        let cal = Calendar.current
        let template: WorkoutTemplate?
        if type == QuickActions.scheduledType {
            template = (schedules.first { !$0.isCompleted && $0.template != nil && cal.isDateInToday($0.date) }
                        ?? schedules.first { !$0.isCompleted && $0.template != nil })?.template
        } else if type.hasPrefix(QuickActions.favoritePrefix),
                  let id = UUID(uuidString: String(type.dropFirst(QuickActions.favoritePrefix.count))) {
            template = templates.first { $0.id == id }
        } else {
            template = nil
        }

        guard let template else { return }
        vm.loadFromTemplate(template, type: template.sortedExercises.first?.timerType ?? .reps)
        vm.markTemplateUsed(template, context: context)
        vm.showWorkoutSetup = true
    }
}

// MARK: - App / Scene delegates + Quick Actions
//
// SwiftUI's App lifecycle needs a small UIKit bridge to receive Home Screen
// quick-action taps. The AppDelegate installs a minimal scene delegate; SwiftUI
// still owns the window (this is Apple's supported pattern for side-channel
// scene events). `windowScene(_:performActionFor:)` handles warm launches and
// `scene(_:willConnectTo:)` handles cold launches.

/// Holds the pending quick-action identifier until SwiftUI can act on it.
final class QuickActions: ObservableObject {
    static let shared = QuickActions()
    @Published var pending: String?

    static let scheduledType  = "com.liftkit.quick.scheduled"
    static let favoritePrefix = "com.liftkit.quick.favorite."

    static func updateShortcuts(scheduledName: String?, favorites: [(id: UUID, name: String)]) {
        var items: [UIApplicationShortcutItem] = []
        if let name = scheduledName {
            items.append(UIApplicationShortcutItem(
                type: scheduledType,
                localizedTitle: "Today's Workout",
                localizedSubtitle: name,
                icon: UIApplicationShortcutIcon(systemImageName: "calendar"),
                userInfo: nil))
        }
        for fav in favorites.prefix(3) {
            items.append(UIApplicationShortcutItem(
                type: favoritePrefix + fav.id.uuidString,
                localizedTitle: fav.name,
                localizedSubtitle: "Favorite",
                icon: UIApplicationShortcutIcon(systemImageName: "star.fill"),
                userInfo: nil))
        }
        UIApplication.shared.shortcutItems = items
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.shared.pending = item.type
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActions.shared.pending = shortcutItem.type
        completionHandler(true)
    }
}

// MARK: - First-run onboarding
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var showTour = false

    var body: some View {
        if showTour {
            TourView(onDone: onDone)
        } else {
            welcome
        }
    }

    private var welcome: some View {
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
                VStack(spacing: LKSpacing.sm) {
                    Button {
                        HapticManager.shared.buttonTap()
                        showTour = true
                    } label: { Text("Take a Quick Tour") }
                        .buttonStyle(LKPrimaryButtonStyle())
                    Button("Skip for now") { onDone() }
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textSecondary)
                }
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

// MARK: - Guided tour
struct TourView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct TourPage {
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [TourPage] = [
        TourPage(icon: "timer",
                 title: "Workout Types",
                 body: "Pick the timer that fits your session: Reps for lifting, plus AMRAP, EMOM, For Time, Intervals (like Tabata), or a free Manual count-up."),
        TourPage(icon: "square.and.arrow.down",
                 title: "Save Templates",
                 body: "Build a workout once, tap Save as Template, and it’s ready to start again any time from your plans."),
        TourPage(icon: "calendar",
                 title: "Schedule Workouts",
                 body: "Schedule a plan on the days you train — or alternate several in a series. Today’s workout appears on your home screen, with a reminder so you don’t forget."),
        TourPage(icon: "chart.line.uptrend.xyaxis",
                 title: "Track & Grow",
                 body: "Timers log every set. Your lifts auto-progress when you hit all your reps, and your history, PRs and charts show how you’re improving over time."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LKColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        tourPage(pages[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(page == pages.count - 1 ? "Done" : "Next") {
                    HapticManager.shared.buttonTap()
                    if page == pages.count - 1 {
                        onDone()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(LKPrimaryButtonStyle())
                .padding(.horizontal, LKSpacing.lg)
                .padding(.bottom, LKSpacing.lg)
            }

            Button("Skip") { onDone() }
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textSecondary)
                .padding(LKSpacing.md)
        }
    }

    private func tourPage(_ p: TourPage) -> some View {
        VStack(spacing: LKSpacing.lg) {
            Spacer()
            Image(systemName: p.icon)
                .font(.system(size: 64))
                .foregroundColor(LKColor.accent)
            Text(p.title)
                .font(LKFont.title)
                .foregroundColor(LKColor.textPrimary)
            Text(p.body)
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LKSpacing.xl)
            Spacer()
            Spacer()
        }
    }
}

import AVFoundation
