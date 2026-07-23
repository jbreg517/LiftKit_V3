import SwiftUI
import StoreKit

/// LiftKit Pro paywall. Shown from Settings, or automatically when someone
/// taps a locked feature — in which case `highlight` names what they were
/// reaching for so the reason is obvious.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreManager.shared

    /// The feature the user just tried to use, if the paywall was triggered by
    /// a locked action. Emphasized in the list and called out up top.
    var highlight: PremiumFeature? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LKSpacing.lg) {
                    header
                    if let highlight { contextBanner(highlight) }
                    featureList
                    purchaseSection
                    tipJarNote
                    footerNote
                }
                .padding(LKSpacing.lg)
                .readableWidth()
            }
            .background(LKColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundColor(LKColor.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onChange(of: store.isPro) { _, nowPro in
                if nowPro { dismiss() }   // purchase or restore succeeded
            }
            .task { await store.refresh() }
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: LKSpacing.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 52))
                .foregroundColor(LKColor.accent)
            Text("LiftKit Pro")
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(LKColor.textPrimary)
            Text("A one-time purchase. Unlocks everything below, forever, on all your devices — no account required.")
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, LKSpacing.sm)
    }

    // MARK: - Context banner (why the paywall appeared)
    private func contextBanner(_ feature: PremiumFeature) -> some View {
        HStack(spacing: LKSpacing.sm) {
            Image(systemName: feature.icon)
                .foregroundColor(LKColor.accent)
                .frame(width: 26)
            Text("\(feature.title) is a Pro feature.")
                .font(LKFont.bodyBold)
                .foregroundColor(LKColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(LKSpacing.md)
        .background(LKColor.accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: LKRadius.medium)
                .strokeBorder(LKColor.accent.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(LKRadius.medium)
    }

    // MARK: - What Pro unlocks
    private var featureList: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("WHAT'S INCLUDED")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
                .tracking(2)
            ForEach(PremiumFeature.allCases) { feature in
                featureRow(feature, emphasized: feature == highlight)
            }
        }
    }

    private func featureRow(_ feature: PremiumFeature, emphasized: Bool) -> some View {
        HStack(alignment: .top, spacing: LKSpacing.md) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundColor(LKColor.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Text(feature.blurb)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: LKRadius.large)
                .strokeBorder(emphasized ? LKColor.accent : LKColor.surfaceElevated,
                              lineWidth: emphasized ? 1.5 : 1)
        )
        .cornerRadius(LKRadius.large)
    }

    // MARK: - Purchase + restore
    private var purchaseSection: some View {
        VStack(spacing: LKSpacing.sm) {
            Button {
                Task { await store.purchase() }
            } label: {
                HStack(spacing: LKSpacing.sm) {
                    if store.isWorking {
                        SwiftUI.ProgressView().tint(LKColor.background)
                    }
                    Text(buyLabel)
                }
            }
            .buttonStyle(LKPrimaryButtonStyle())
            .disabled(store.isWorking || store.product == nil)

            if store.product == nil {
                Text("The store is unavailable right now. Check your connection and try again.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .multilineTextAlignment(.center)
            }

            Button("Restore Purchase") {
                Task { await store.restore() }
            }
            .font(LKFont.bodyBold)
            .foregroundColor(LKColor.accent)
            .disabled(store.isWorking)

            if let error = store.lastError {
                Text(error)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, LKSpacing.xs)
    }

    private var buyLabel: String {
        guard store.product != nil else { return "Unlock Pro" }
        return "Unlock Pro · \(store.priceText)"
    }

    // MARK: - Tip jar (not yet functional)
    private var tipJarNote: some View {
        HStack(spacing: LKSpacing.md) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundColor(LKColor.textMuted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: LKSpacing.xs) {
                    Text("Tip jar")
                        .font(LKFont.bodyBold)
                        .foregroundColor(LKColor.textPrimary)
                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(LKColor.textMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LKColor.surfaceElevated)
                        .clipShape(Capsule())
                }
                Text("A way to say thanks beyond Pro, if you're enjoying LiftKit.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(LKSpacing.md)
        .background(LKColor.surface.opacity(0.5))
        .cornerRadius(LKRadius.large)
    }

    // MARK: - Footer
    private var footerNote: some View {
        Text("One-time purchase · Restores on all your devices · Everything stays on your device.")
            .font(LKFont.caption)
            .foregroundColor(LKColor.textMuted)
            .multilineTextAlignment(.center)
            .padding(.top, LKSpacing.xs)
    }
}
