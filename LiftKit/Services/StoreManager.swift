import Foundation
import StoreKit

/// StoreKit 2 wrapper for the single "LiftKit Pro" one-time unlock.
///
/// Anonymous by design — no account, no server. `isPro` is derived from the
/// App Store entitlement, so a purchase restores automatically across the
/// user's devices and after a reinstall. Everything the app gates keys off
/// `StoreManager.shared.isPro`.
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    /// Non-consumable product ID. Must match the product created in
    /// App Store Connect (In-App Purchases → Non-Consumable).
    static let proProductID = "com.liftkit.app.pro"

    /// The loaded product (nil until fetched, or if the store is unreachable).
    @Published private(set) var product: Product?
    /// True when the user owns Pro. Source of truth for every gated feature.
    @Published private(set) var isPro = false
    /// A purchase / restore is in flight.
    @Published private(set) var isWorking = false
    /// User-facing error from the last purchase or restore, if any.
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Keep listening for transactions made outside a direct purchase call
        // (Ask to Buy approvals, purchases on another device, refunds).
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    /// Localized price such as "$4.99", or a dash until the product loads.
    var priceText: String { product?.displayPrice ?? "—" }

    /// Load the product and re-evaluate entitlement. Safe to call repeatedly.
    @MainActor func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    @MainActor private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.proProductID]).first
        } catch {
            product = nil
        }
    }

    /// Recompute `isPro` from the App Store's current entitlements.
    @MainActor func updateEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    /// Buy the Pro unlock. No-op if the product hasn't loaded yet.
    @MainActor func purchase() async {
        guard let product else {
            lastError = "The store is unavailable right now. Please try again."
            return
        }
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await finish(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restore a prior purchase — the App Store account is the source of truth.
    @MainActor func restore() async {
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await updateEntitlement()
    }

    @MainActor private func finish(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await updateEntitlement()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.finish(update)
            }
        }
    }
}

/// Build-time feature flags. The tip jar UI is fully built but stays hidden
/// until its consumable products ship, so the 1.0 build carries no "coming
/// soon" placeholder (App Review guideline 2.1). Flip to `true` once the tip
/// products exist in App Store Connect.
enum AppFeatures {
    static let tipJarEnabled = false
}

/// The features LiftKit Pro unlocks. Drives both the paywall and each lock
/// state, so the list stays in one place.
enum PremiumFeature: String, CaseIterable, Identifiable {
    case scheduling, plans, health

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scheduling: return "calendar"
        case .plans:      return "square.stack.3d.up.fill"
        case .health:     return "heart.text.square.fill"
        }
    }

    var title: String {
        switch self {
        case .scheduling: return "Workout calendar & scheduling"
        case .plans:      return "Unlimited workout plans"
        case .health:     return "Health & nutrition tab"
        }
    }

    var blurb: String {
        switch self {
        case .scheduling: return "Plan sessions ahead and see them on a calendar."
        case .plans:      return "Save more than \(UserProfile.maxFreeTemplates) workout plans."
        case .health:     return "Bodyweight, BMR/TDEE, macros and goals — all on-device."
        }
    }
}
