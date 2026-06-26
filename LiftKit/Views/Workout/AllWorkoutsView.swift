import SwiftUI

/// Full recommended-workout catalog, filterable by workout type. Reached from
/// the "Additional Workouts" button under the home recommendations.
struct AllWorkoutsView: View {
    @Bindable var vm: WorkoutViewModel

    @State private var typeFilter: TimerType?   // nil = All

    private var filtered: [RecommendedWorkout] {
        guard let t = typeFilter else { return RecommendedWorkouts.all }
        return RecommendedWorkouts.all.filter { $0.type == t }
    }

    /// Only the workout types that actually appear in the catalog.
    private var availableTypes: [TimerType] {
        TimerType.allCases.filter { type in RecommendedWorkouts.all.contains { $0.type == type } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.md) {
                filterBar
                ForEach(filtered) { rec in
                    WorkoutCatalogRow(rec: rec) {
                        HapticManager.shared.buttonTap()
                        vm.loadRecommended(rec)
                    }
                    .padding(.horizontal, LKSpacing.md)
                }
            }
            .padding(.vertical, LKSpacing.md)
        }
        .navigationTitle("All Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .background(LKColor.background.ignoresSafeArea())
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LKSpacing.sm) {
                filterChip(label: "All", active: typeFilter == nil) { typeFilter = nil }
                ForEach(availableTypes) { t in
                    filterChip(label: t.rawValue, active: typeFilter == t) { typeFilter = t }
                }
            }
            .padding(.horizontal, LKSpacing.md)
        }
    }

    private func filterChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticManager.shared.buttonTap()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? .black : LKColor.textSecondary)
                .padding(.horizontal, LKSpacing.md)
                .padding(.vertical, LKSpacing.sm)
                .background(active ? LKColor.accent : LKColor.surfaceElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog row (full-width, whole row tappable)
struct WorkoutCatalogRow: View {
    let rec: RecommendedWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: LKSpacing.sm) {
                HStack(spacing: LKSpacing.xs) {
                    Image(systemName: rec.type.sfSymbol)
                        .font(.system(size: 12))
                        .foregroundColor(LKColor.accent)
                    Text(rec.type.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LKColor.textMuted)
                    Spacer()
                }
                Text(rec.name)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                Text(rec.blurb)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textSecondary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    ForEach(rec.purposes) { p in
                        Text(p.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(LKColor.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(LKColor.surfaceElevated)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.large)
                    .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
            )
            .cornerRadius(LKRadius.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rec.name), \(rec.type.rawValue)")
    }
}
