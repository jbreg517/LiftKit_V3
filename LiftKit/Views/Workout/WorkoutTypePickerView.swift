import SwiftUI

struct WorkoutTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: WorkoutViewModel

    let columns = [GridItem(.flexible(), spacing: LKSpacing.sm), GridItem(.flexible(), spacing: LKSpacing.sm)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: LKSpacing.sm) {
                    ForEach(TimerType.allCases) { type in
                        WorkoutTypeCard(type: type) {
                            vm.resetSetup()
                            vm.selectedTimerType = type
                            dismiss()
                            // Signal to parent to show setup
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                vm.showTypePicker = false
                            }
                        }
                    }
                }
                .padding(LKSpacing.md)
            }
            .navigationTitle("Choose Workout Type")
            .navigationBarTitleDisplayMode(.inline)
            .background(LKColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LKColor.textSecondary)
                }
            }
        }
    }
}

// MARK: - Type Card
struct WorkoutTypeCard: View {
    let type: TimerType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: LKSpacing.sm) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(LKColor.accent)

                Text(type.rawValue)
                    .font(LKFont.bodyBold)
                    .foregroundColor(LKColor.textPrimary)
                    .lineLimit(1)

                Text(type.subtitle)
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: LKRadius.large)
                    .strokeBorder(LKColor.surfaceElevated, lineWidth: 1)
            )
            .cornerRadius(LKRadius.large)
        }
        .buttonStyle(.plain)
    }
}
