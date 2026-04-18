import SwiftUI
import SwiftData
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: WorkoutViewModel

    @State private var displayName: String = ""
    @State private var isActivating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: LKSpacing.xl) {
                Spacer()

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 60))
                    .foregroundColor(LKColor.accent)

                Text("LiftKit")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(LKColor.textPrimary)

                Text("Activate premium to unlock the calendar, more workout plans, and more.")
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LKSpacing.lg)

                TextField("Your name (optional)", text: $displayName)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textPrimary)
                    .padding(LKSpacing.md)
                    .background(LKColor.surface)
                    .cornerRadius(LKRadius.medium)
                    .padding(.horizontal, LKSpacing.md)

                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(LKRadius.medium)
                .padding(.horizontal, LKSpacing.md)

                // Activate Premium (local)
                Button {
                    activatePremium(provider: "local")
                } label: {
                    Label("Activate Premium", systemImage: "crown.fill")
                }
                .buttonStyle(LKPrimaryButtonStyle())
                .padding(.horizontal, LKSpacing.md)

                Button("Continue without signing in") {
                    dismiss()
                }
                .font(LKFont.body)
                .foregroundColor(LKColor.textMuted)

                Spacer()
            }
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(LKColor.textSecondary)
                    }
                }
            }
        }
    }

    private func activatePremium(provider: String, name: String? = nil, email: String? = nil) {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? context.fetch(descriptor).first {
            existing.isPremium = true
            existing.authProvider = provider
            if let n = name ?? (displayName.isEmpty ? nil : displayName) { existing.displayName = n }
            if let e = email { existing.email = e }
            vm.userProfile = existing
        } else {
            let profile = UserProfile(
                displayName: name ?? (displayName.isEmpty ? nil : displayName),
                email: email,
                authProvider: provider,
                isPremium: true
            )
            context.insert(profile)
            vm.userProfile = profile
        }
        try? context.save()
        dismiss()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let email = credential.email
            activatePremium(provider: "apple", name: name.isEmpty ? nil : name, email: email)
        case .failure:
            break
        }
    }
}
