import SwiftUI

struct NumberEntryItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let currentValue: Double
    let minValue: Double
    let maxValue: Double
    let onConfirm: (Double) -> Void
}

struct NumberEntrySheet: View {
    let item: NumberEntryItem
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: LKSpacing.lg) {
            Text(item.title)
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)

            Text(item.message)
                .font(LKFont.body)
                .foregroundColor(LKColor.textSecondary)

            TextField("", text: $text)
                .font(LKFont.timer(48))
                .foregroundColor(LKColor.accent)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .focused($isFocused)

            Button("Done") {
                confirm()
            }
            .buttonStyle(LKPrimaryButtonStyle())
            .padding(.horizontal, LKSpacing.md)
        }
        .padding(LKSpacing.xl)
        .frame(height: 280)
        .background(LKColor.surface)
        .onAppear {
            text = item.currentValue == 0 ? "" : String(Int(item.currentValue))
            isFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(LKColor.textSecondary)
            }
        }
    }

    private func confirm() {
        let parsed = Double(text) ?? item.currentValue
        let clamped = max(item.minValue, min(item.maxValue, parsed))
        item.onConfirm(clamped)
        dismiss()
    }
}
