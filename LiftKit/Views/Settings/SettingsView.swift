import SwiftUI
import SwiftData

/// App version, bumped on every commit/push so the running build is
/// identifiable in Settings. Increment by 0.01 each push.
enum AppVersion {
    static let current = "0.01"
}

struct SettingsView: View {
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds: Double = 90
    @AppStorage("soundEnabled")       private var soundEnabled: Bool = true
    @AppStorage("hapticsEnabled")     private var hapticsEnabled: Bool = true

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var currentProfile: UserProfile? { profiles.first }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    @State private var showPrivacyPolicy = false
    @State private var showDisclaimer    = false
    @State private var showExportComingSoon = false

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
                }

                Section("Feedback") {
                    Toggle("Timer Sounds", isOn: $soundEnabled)
                        .tint(LKColor.accent)
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                        .tint(LKColor.accent)
                }

                Section("Data") {
                    Button("Export Workout Data") {
                        showExportComingSoon = true
                    }
                    .foregroundColor(LKColor.accent)
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
            .alert("Coming Soon", isPresented: $showExportComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("CSV export will be available in a future update.")
            }
        }
    }
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
