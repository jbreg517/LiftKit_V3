import SwiftUI

struct WorkoutTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: WorkoutViewModel

    private let columns = [
        GridItem(.flexible(), spacing: LKSpacing.sm),
        GridItem(.flexible(), spacing: LKSpacing.sm)
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let rowCount: CGFloat = 3
                let vSpacing = LKSpacing.sm
                let padding  = LKSpacing.md
                // Height available for cards = total height minus top/bottom padding and inter-row gaps
                let cardHeight = (geo.size.height - padding * 2 - vSpacing * (rowCount - 1)) / rowCount

                LazyVGrid(columns: columns, spacing: vSpacing) {
                    ForEach(TimerType.allCases) { type in
                        WorkoutTypeCard(type: type, height: cardHeight) {
                            vm.resetSetup()
                            vm.selectedTimerType = type
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                vm.showTypePicker = false
                            }
                        }
                    }
                }
                .padding(padding)
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
    let height: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: LKSpacing.sm) {
                Spacer(minLength: 0)
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 30, weight: .semibold))
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .padding(.horizontal, LKSpacing.sm)
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
