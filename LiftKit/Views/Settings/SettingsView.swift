import SwiftUI
import SwiftData
import UIKit

/// App version, bumped on every commit/push so the running build is
/// identifiable in Settings. Increment by 0.01 each push.
enum AppVersion {
    static let current = "0.26"
}

struct SettingsView: View {
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds: Double = 90
    @AppStorage("weightIncrement")    private var weightIncrement: Double = 5
    @AppStorage("soundEnabled")       private var soundEnabled: Bool = true
    @AppStorage("hapticsEnabled")     private var hapticsEnabled: Bool = true
    @AppStorage("iCloudSyncEnabled")  private var iCloudSyncEnabled: Bool = false
    @AppStorage("appearance")         private var appearance: String = "system"
    @AppStorage("workoutRemindersEnabled") private var remindersEnabled: Bool = true
    @AppStorage("reminderHour")       private var reminderHour: Int = 8

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var nutritionDays: [NutritionDay]
    @Query private var schedules: [WorkoutSchedule]

    private var currentProfile: UserProfile? { profiles.first }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// Re-applies (or clears) reminders for all future schedules when the toggle
    /// or reminder time changes, so the change takes effect immediately.
    private func refreshReminders() {
        if remindersEnabled {
            WorkoutReminders.reschedule(schedules.filter { !$0.isCompleted })
        } else {
            WorkoutReminders.cancelAll()
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents(); comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: date)
    }

    @State private var showPrivacyPolicy = false
    @State private var showDisclaimer    = false
    @State private var showTour          = false
    @State private var exportFile: ExportFile?

    var body: some View {
        NavigationStack {
            Form {
                Section("Timer Defaults") {
                    VStack(alignment: .leading, spacing: LKSpacing.sm) {
                        Text("Default Rest: \(Int(defaultRestSeconds))s")
                            .font(LKFont.body)
                        Slider(value: $defaultRestSeconds, in: 30...300, step: 15)
                            .tint(LKColor.accent)
                    }
                    .padding(.vertical, LKSpacing.xs)

                    Picker("Weight Increment", selection: $weightIncrement) {
                        ForEach([1.0, 2.5, 5.0, 10.0], id: \.self) { v in
                            Text(v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)).tag(v)
                        }
                    }
                    .tint(LKColor.accent)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Workout Reminders", isOn: $remindersEnabled)
                        .tint(LKColor.accent)
                        .onChange(of: remindersEnabled) { _, _ in refreshReminders() }
                    if remindersEnabled {
                        Picker("Reminder Time", selection: $reminderHour) {
                            ForEach(5...21, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .tint(LKColor.accent)
                        .onChange(of: reminderHour) { _, _ in refreshReminders() }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Get a local notification on days you have a workout scheduled. Reminders stay on your device.")
                }

                Section("Feedback") {
                    Toggle("Timer Sounds", isOn: $soundEnabled)
                        .tint(LKColor.accent)
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                        .tint(LKColor.accent)
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $iCloudSyncEnabled)
                        .tint(LKColor.accent)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Stores your workouts in your own private iCloud account so they sync across your devices. Nothing is shared with the developer or any third party. Requires an iCloud sign-in and an App Store build; relaunch the app after changing this.")
                }

                Section("Data") {
                    Button("Export Workout Data (CSV)") {
                        if let url = CSVExport.write(sessions: sessions) {
                            exportFile = ExportFile(url: url)
                        }
                    }
                    .foregroundColor(LKColor.accent)

                    if !nutritionDays.isEmpty {
                        Button("Export Nutrition Data (CSV)") {
                            if let url = CSVExport.writeNutrition(days: nutritionDays) {
                                exportFile = ExportFile(url: url)
                            }
                        }
                        .foregroundColor(LKColor.accent)
                    }
                }

                if let profile = currentProfile {
                    Section("Account") {
                        if let name = profile.displayName, !name.isEmpty {
                            HStack {
                                Text("Name")
                                Spacer()
                                Text(name)
                                    .foregroundColor(LKColor.textSecondary)
                            }
                        }
                        if let email = profile.email, !email.isEmpty {
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(email)
                                    .foregroundColor(LKColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(profile.isPremium ? "Premium ✓" : "Free")
                                .foregroundColor(profile.isPremium ? LKColor.accent : LKColor.textSecondary)
                        }
                        Button("Log Out", role: .destructive) {
                            for p in profiles { context.delete(p) }
                            try? context.save()
                        }
                        .foregroundColor(LKColor.danger)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("v\(AppVersion.current) (build \(buildString))")
                            .foregroundColor(LKColor.textSecondary)
                    }

                    Button("App Tour") {
                        showTour = true
                    }
                    .foregroundColor(LKColor.accent)

                    Button("Privacy Policy") {
                        showPrivacyPolicy = true
                    }
                    .foregroundColor(LKColor.accent)

                    Button("Workout Disclaimer") {
                        showDisclaimer = true
                    }
                    .foregroundColor(LKColor.accent)
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView() }
            .sheet(isPresented: $showDisclaimer)    { DisclaimerView() }
            .sheet(isPresented: $showTour)          { TourView(onDone: { showTour = false }) }
            .sheet(item: $exportFile) { ShareSheet(items: [$0.url]) }
        }
    }
}

// MARK: - CSV export

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

enum CSVExport {
    static func write(sessions: [WorkoutSession]) -> URL? {
        var rows = ["Date,Workout,Type,Exercise,Equipment,Set,Weight,Unit,Reps,Duration,RPE,SetType"]
        let df = ISO8601DateFormatter()
        for session in sessions.filter({ !$0.isActive }).sorted(by: { $0.startedAt < $1.startedAt }) {
            for entry in session.sortedEntries {
                let exName = entry.exercise?.name ?? ""
                let equip = entry.equipmentEnum?.rawValue ?? entry.exercise?.equipmentEnum?.rawValue ?? ""
                for set in entry.sortedSets {
                    // Build each column as an explicitly-typed String so the
                    // type-checker doesn't choke on one giant array literal.
                    let dateStr: String = df.string(from: set.completedAt)
                    let typeStr: String = session.workoutType ?? ""
                    let setNumStr: String = String(set.setNumber)
                    let weightStr: String = set.weight.map { String(Int($0)) } ?? ""
                    let repsStr: String = set.reps.map { String($0) } ?? ""
                    let durStr: String = set.duration.map { String(Int($0)) } ?? ""
                    var rpeStr = ""
                    if let r = set.rpe {
                        rpeStr = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
                    }
                    let setTypeStr: String = set.setType == .normal ? "" : set.setType.rawValue
                    let cols: [String] = [
                        dateStr, esc(session.name), typeStr, esc(exName), esc(equip),
                        setNumStr, weightStr, set.weightUnit, repsStr, durStr, rpeStr, setTypeStr,
                    ]
                    rows.append(cols.joined(separator: ","))
                }
            }
        }
        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiftKit_export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func writeNutrition(days: [NutritionDay]) -> URL? {
        var rows = ["Date,Protein(g),Carbs(g),Fat(g),Alcohol(g),Calories"]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for d in days.filter({ !$0.isEmpty }).sorted(by: { $0.date < $1.date }) {
            let cols: [String] = [
                df.string(from: d.date),
                num(d.proteinG), num(d.carbG), num(d.fatG), num(d.alcoholG),
                String(Int(d.calories.rounded())),
            ]
            rows.append(cols.joined(separator: ","))
        }
        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiftKit_nutrition.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func esc(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Privacy Policy
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LKSpacing.md) {
                    Text("Privacy Policy")
                        .font(LKFont.title)
                        .foregroundColor(LKColor.textPrimary)

                    Text("Last updated: April 2026")
                        .font(LKFont.caption)
                        .foregroundColor(LKColor.textMuted)

                    privacyText
                }
                .padding(LKSpacing.md)
            }
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LKColor.accent)
                }
            }
        }
    }

    private var privacyText: some View {
        VStack(alignment: .leading, spacing: LKSpacing.md) {
            Group {
                policySection("Data We Collect",
                    "LiftKit collects only the information you explicitly provide: workout names, exercise names, weights, reps, sets, and optional notes. This data is stored locally on your device and is never transmitted to our servers or any third party.")
                policySection("How We Use Your Data",
                    "Your workout data is used solely to display your history, track personal records, and power the progress features within the app. We do not use your data for advertising, analytics, or any commercial purpose.")
                policySection("Data Storage",
                    "All data is stored locally on your device using Apple's SwiftData framework. If you enable iCloud Backup, your data may be included in your personal iCloud backup, which is governed by Apple's privacy policy. We have no access to iCloud backups.")
                policySection("Authentication",
                    "If you choose to activate Premium using Sign in with Apple, we receive a stable unique identifier (used to recognise your account on re-login), and optionally your name and email address as you choose to share. All of this is stored on-device only to maintain your premium status. We do not store passwords.")
                policySection("Third-Party Services",
                    "LiftKit contains no third-party SDKs, analytics libraries, advertising frameworks, or crash-reporting services. Zero data is shared with third parties.")
                policySection("Your Rights",
                    "You may delete all your data at any time by uninstalling the app. Contact us with any privacy questions.")
                policySection("Contact",
                    "If you have any questions about this policy, please contact us through the App Store support link.")
            }
        }
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text(title)
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textPrimary)
            Text(body)
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
        }
    }
}

// MARK: - Disclaimer
struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LKSpacing.md) {
                    Text("Health & Fitness Disclaimer")
                        .font(LKFont.title)
                        .foregroundColor(LKColor.textPrimary)

                    Text("""
LiftKit is a workout timer and logging tool designed for informational and tracking purposes only. It is not intended to provide medical advice, diagnosis, or treatment.

**Consult a Physician**
Before beginning any new exercise program, we strongly recommend consulting with a qualified healthcare professional, especially if you have any pre-existing medical conditions, injuries, or concerns about your health.

**Exercise Risk**
Physical exercise carries inherent risks including, but not limited to, muscle strain, joint injury, cardiovascular events, and other health complications. Always listen to your body and stop exercising immediately if you experience pain, dizziness, shortness of breath, or any other unusual symptoms.

**Not a Medical Device**
LiftKit is not a medical device and is not intended to diagnose, treat, cure, or prevent any disease or health condition.

**Individual Results**
Fitness results vary by individual. LiftKit makes no guarantees regarding specific outcomes from following any workout tracked in the app.

**Use at Your Own Risk**
By using LiftKit, you acknowledge that you exercise at your own risk and that the developers of LiftKit are not liable for any injuries or health issues that may result from physical exercise.
""")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                }
                .padding(LKSpacing.md)
            }
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LKColor.accent)
                }
            }
        }
    }
}
