import SwiftUI
import SwiftData
import Charts

/// Bodyweight + measurement tracker. Pick a metric, see its trend and history,
/// and log new entries. All data is local to the device.
struct BodyTrackingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetric.date) private var metrics: [BodyMetric]

    @State private var selectedType: BodyMetricType = .bodyweight
    @State private var showAdd = false

    private var entries: [BodyMetric] {
        metrics.filter { $0.type == selectedType }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.lg) {
                typeMenu
                latestCard
                chartSection
                historySection
            }
            .padding(.vertical, LKSpacing.md)
        }
        .background(LKColor.background.ignoresSafeArea())
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAdd = true
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(LKColor.accent)
                }
                .accessibilityLabel("Add measurement")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddBodyMetricSheet(defaultType: selectedType)
        }
    }

    // MARK: - Type picker
    private var typeMenu: some View {
        Menu {
            ForEach(BodyMetricType.allCases) { t in
                Button { selectedType = t } label: {
                    Label(t.label, systemImage: t.icon)
                }
            }
        } label: {
            HStack {
                Image(systemName: selectedType.icon)
                Text(selectedType.label)
                    .font(LKFont.bodyBold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                Spacer()
            }
            .foregroundColor(LKColor.accent)
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
        }
        .padding(.horizontal, LKSpacing.md)
    }

    // MARK: - Latest value + change
    private var latestCard: some View {
        let latest = entries.last
        let first = entries.first
        let delta: Double? = (latest != nil && first != nil && latest!.id != first!.id)
            ? latest!.value - first!.value : nil
        return VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text("Current")
                .font(LKFont.caption)
                .foregroundColor(LKColor.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: LKSpacing.sm) {
                Text(latest.map { fmt($0.value) } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(LKColor.textPrimary)
                Text(selectedType.unit)
                    .font(LKFont.body)
                    .foregroundColor(LKColor.textMuted)
                Spacer()
                if let delta {
                    deltaBadge(delta)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LKSpacing.md)
        .background(LKColor.surface)
        .cornerRadius(LKRadius.large)
        .padding(.horizontal, LKSpacing.md)
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let improving = delta < 0 ? selectedType.lowerIsBetter : !selectedType.lowerIsBetter
        let color = delta == 0 ? LKColor.textMuted : (improving ? LKColor.accent : LKColor.danger)
        let arrow = delta > 0 ? "arrow.up" : (delta < 0 ? "arrow.down" : "minus")
        return HStack(spacing: 2) {
            Image(systemName: arrow).font(.caption2)
            Text("\(fmt(abs(delta))) \(selectedType.unit)")
                .font(LKFont.caption)
        }
        .foregroundColor(color)
    }

    // MARK: - Chart
    private var chartSection: some View {
        Group {
            if entries.count < 2 {
                ContentUnavailableView(
                    "Not Enough Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Log at least two entries to see your trend.")
                )
                .frame(height: 140)
            } else {
                Chart {
                    ForEach(entries) { m in
                        LineMark(
                            x: .value("Date", m.date),
                            y: .value(selectedType.label, m.value)
                        )
                        .foregroundStyle(LKColor.accent)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Date", m.date),
                            y: .value(selectedType.label, m.value)
                        )
                        .foregroundStyle(LKColor.accent)
                    }
                }
                .chartYAxisLabel("\(selectedType.label) (\(selectedType.unit))")
                .frame(height: 220)
                .padding(.horizontal, LKSpacing.md)
            }
        }
    }

    // MARK: - History
    private var historySection: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("History")
                .font(LKFont.heading)
                .foregroundColor(LKColor.textPrimary)
                .padding(.horizontal, LKSpacing.md)

            if entries.isEmpty {
                Text("No entries yet. Tap + to log one.")
                    .font(LKFont.caption)
                    .foregroundColor(LKColor.textMuted)
                    .padding(.horizontal, LKSpacing.md)
            } else {
                ForEach(entries.reversed()) { m in
                    HStack {
                        Text(m.date.formatted(date: .abbreviated, time: .omitted))
                            .font(LKFont.body)
                            .foregroundColor(LKColor.textSecondary)
                        Spacer()
                        Text("\(fmt(m.value)) \(selectedType.unit)")
                            .font(LKFont.bodyBold)
                            .foregroundColor(LKColor.textPrimary)
                    }
                    .padding(LKSpacing.md)
                    .background(LKColor.surface)
                    .cornerRadius(LKRadius.medium)
                    .padding(.horizontal, LKSpacing.md)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(m)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Add entry sheet
struct AddBodyMetricSheet: View {
    let defaultType: BodyMetricType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var type: BodyMetricType
    @State private var date = Date()
    @State private var valueText = ""

    init(defaultType: BodyMetricType) {
        self.defaultType = defaultType
        _type = State(initialValue: defaultType)
    }

    private var value: Double? { Double(valueText.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Metric", selection: $type) {
                        ForEach(BodyMetricType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .tint(LKColor.accent)
                    HStack {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                        Text(type.unit)
                            .foregroundColor(LKColor.textMuted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .navigationTitle("Log \(type.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LKColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(value == nil || (value ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let value, value > 0 else { return }
        let metric = BodyMetric(date: date, type: type, value: value)
        context.insert(metric)
        try? context.save()
        HapticManager.shared.buttonTap()
        dismiss()
    }
}
