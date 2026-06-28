import SwiftUI
import SwiftData

/// Add-food flow: search USDA → pick a result → choose serving/quantity → log to
/// the chosen meal, or fall back to manual macro entry. Presented from the Food
/// Log section (the top "Add Food" button or a meal's "+").
struct FoodEntryView: View {
    let date: Date
    @State private var mealType: MealType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var query = ""
    @State private var results: [FoodResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var selected: FoodResult?
    @State private var showManual = false

    init(initialMeal: MealType, date: Date) {
        self.date = date
        _mealType = State(initialValue: initialMeal)
    }

    var body: some View {
        NavigationStack {
            searchList
                .background(LKColor.background.ignoresSafeArea())
                .navigationTitle("Add Food")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $selected) { result in
                    ServingDetail(result: result, mealType: mealType) { quantity, asGrams in
                        log(result, quantity: quantity, asGrams: asGrams)
                    }
                    .navigationTitle("Serving")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.foregroundColor(LKColor.textSecondary)
                    }
                }
                .sheet(isPresented: $showManual) {
                    NutritionQuickAddSheet(mealName: mealType.label) { name, p, c, f, a in
                        logManual(name: name, p: p, c: c, f: f, a: a)
                    }
                }
        }
    }

    private var searchList: some View {
        VStack(spacing: 0) {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(LKSpacing.md)

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(LKColor.textMuted)
                TextField("Search foods", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                if !query.isEmpty {
                    Button {
                        query = ""; results = []; hasSearched = false; searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(LKColor.textMuted)
                    }
                }
            }
            .padding(LKSpacing.sm)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)

            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let searchError {
                    Text(searchError)
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                        .listRowBackground(Color.clear)
                } else if hasSearched && results.isEmpty {
                    Text("No results — try a different search, or enter macros manually.")
                        .font(LKFont.caption).foregroundColor(LKColor.textMuted)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(results) { result in
                        Button { selected = result } label: { resultRow(result) }
                            .listRowBackground(LKColor.surface)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()
            Button { showManual = true } label: {
                Label("Enter manually", systemImage: "square.and.pencil")
                    .font(LKFont.bodyBold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LKSecondaryButtonStyle())
            .padding(LKSpacing.md)
        }
    }

    private func resultRow(_ r: FoodResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.name).font(LKFont.body).foregroundColor(LKColor.textPrimary).lineLimit(2)
            HStack(spacing: 6) {
                if let brand = r.brand, !brand.isEmpty {
                    Text(brand).font(.system(size: 11)).foregroundColor(LKColor.textMuted).lineLimit(1)
                    Text("·").foregroundColor(LKColor.textMuted)
                }
                Text("\(Int(r.macrosPerServing.calories.rounded())) kcal · \(r.servingDescription)")
                    .font(.system(size: 11)).foregroundColor(LKColor.textMuted).lineLimit(1)
            }
        }
    }

    // MARK: - Actions

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; hasSearched = false; return }
        isSearching = true
        searchError = nil
        Task {
            do {
                let found = try await FoodLookupService.live().search(q)
                await MainActor.run {
                    results = found
                    isSearching = false
                    hasSearched = true
                }
            } catch {
                await MainActor.run {
                    searchError = "Couldn’t search. Check your connection and try again."
                    results = []
                    isSearching = false
                    hasSearched = true
                }
            }
        }
    }

    private func log(_ result: FoodResult, quantity: Double, asGrams: Bool) {
        let item = NutritionLog.findOrCreateFoodItem(from: result, context: context)
        let servings = asGrams
            ? (item.servingGrams > 0 ? quantity / item.servingGrams : quantity)
            : quantity
        let macros = item.macros(servings: servings)
        NutritionLog.addEntry(macros: macros, mealType: mealType, food: item,
                              quantity: servings, enteredAsGrams: asGrams,
                              on: date, context: context)
        HapticManager.shared.buttonTap()
        dismiss()
    }

    private func logManual(name: String, p: Double, c: Double, f: Double, a: Double) {
        let macros = Macros(proteinG: p, carbG: c, fatG: f, alcoholG: a)
        guard macros.calories > 0 else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        NutritionLog.addEntry(macros: macros, mealType: mealType, food: nil,
                              quantity: 1, enteredAsGrams: false,
                              name: trimmed.isEmpty ? nil : trimmed,
                              on: date, context: context)
        dismiss()
    }
}

// MARK: - Serving / quantity step

private struct ServingDetail: View {
    let result: FoodResult
    let mealType: MealType
    let onAdd: (_ quantity: Double, _ asGrams: Bool) -> Void

    @State private var asGrams = false
    @State private var amount = "1"

    private var amountValue: Double { Double(amount.trimmingCharacters(in: .whitespaces)) ?? 0 }

    /// Macros for the amount the user is about to log.
    private var previewMacros: Macros {
        let servings = asGrams
            ? (result.servingGrams > 0 ? amountValue / result.servingGrams : 0)
            : amountValue
        return result.macrosPerServing.scaled(by: servings)
    }
    /// Reference macros per 100 g (nil when the serving weight is unknown).
    private var per100: Macros? {
        result.servingGrams > 0 ? result.macrosPerServing.scaled(by: 100 / result.servingGrams) : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LKSpacing.lg) {
                headerCard
                amountCard
                primaryCard
                nutritionCard
            }
            .padding(.vertical, LKSpacing.md)
        }
        .background(LKColor.background.ignoresSafeArea())
        .onChange(of: asGrams) { _, grams in
            amount = grams ? (result.servingGrams > 0 ? "\(Int(result.servingGrams))" : "0") : "1"
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { onAdd(amountValue, asGrams) }
                    .bold()
                    .disabled(previewMacros.calories <= 0)
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let brand = result.brand, !brand.isEmpty {
                        Text(brand).font(LKFont.caption).foregroundColor(LKColor.textMuted)
                    }
                    Text(result.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(LKColor.textPrimary)
                }
                Spacer()
                sourceBadge
            }
            Text("Serving: \(result.servingDescription)")
                .font(LKFont.caption).foregroundColor(LKColor.textMuted)
        }
        .card()
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            if result.servingGrams > 0 {
                Picker("Measure", selection: $asGrams) {
                    Text("Servings").tag(false)
                    Text("Grams").tag(true)
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text(asGrams ? "Amount (g)" : "Servings")
                    .foregroundColor(LKColor.textSecondary)
                Spacer()
                TextField(asGrams ? "0" : "1", text: $amount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .foregroundColor(LKColor.textPrimary)
            }
        }
        .card()
    }

    /// "This entry" — the chosen amount, in the same pill + circle format as the log.
    private var primaryCard: some View {
        VStack(alignment: .leading, spacing: LKSpacing.sm) {
            Text("THIS ENTRY")
                .font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
            HStack {
                pill("\(Int(previewMacros.calories.rounded())) kcal")
                Spacer()
            }
            HStack(spacing: LKSpacing.lg) {
                circle(previewMacros.proteinG, LKColor.rest, "P")
                circle(previewMacros.carbG, LKColor.work, "C")
                circle(previewMacros.fatG, LKColor.accent, "F")
                circle(previewMacros.alcoholG, LKColor.danger, "A")
                Spacer()
            }
        }
        .card()
    }

    /// Nutrition-label style: per serving and per 100 g.
    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text("NUTRITION")
                .font(LKFont.caption).foregroundColor(LKColor.textMuted).tracking(2)
                .padding(.bottom, 2)
            nutrHeader
            Divider()
            nutrRow("Calories", fmt(result.macrosPerServing.calories, "kcal"), per100.map { fmt($0.calories, "kcal") })
            nutrRow("Protein",  fmt(result.macrosPerServing.proteinG, "g"),    per100.map { fmt($0.proteinG, "g") })
            nutrRow("Carbs",    fmt(result.macrosPerServing.carbG, "g"),       per100.map { fmt($0.carbG, "g") })
            nutrRow("Fat",      fmt(result.macrosPerServing.fatG, "g"),        per100.map { fmt($0.fatG, "g") })
            nutrRow("Alcohol",  fmt(result.macrosPerServing.alcoholG, "g"),    per100.map { fmt($0.alcoholG, "g") })
        }
        .card()
    }

    // MARK: - Row bits

    private var nutrHeader: some View {
        HStack {
            Text(" ")
            Spacer()
            Text("Per serving").font(.system(size: 11)).foregroundColor(LKColor.textMuted)
                .frame(width: 92, alignment: .trailing)
            Text("Per 100 g").font(.system(size: 11)).foregroundColor(LKColor.textMuted)
                .frame(width: 78, alignment: .trailing)
        }
    }

    private func nutrRow(_ name: String, _ serving: String, _ per100Value: String?) -> some View {
        HStack {
            Text(name).font(LKFont.body).foregroundColor(LKColor.textPrimary)
            Spacer()
            Text(serving).font(LKFont.body).foregroundColor(LKColor.textSecondary)
                .frame(width: 92, alignment: .trailing)
            Text(per100Value ?? "—").font(LKFont.body).foregroundColor(LKColor.textSecondary)
                .frame(width: 78, alignment: .trailing)
        }
    }

    private func fmt(_ v: Double, _ unit: String) -> String { "\(Int(v.rounded())) \(unit)" }

    private var sourceBadge: some View {
        Text(result.source.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(LKColor.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(LKColor.surfaceElevated))
    }
    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(LKColor.accent))
    }
    private func circle(_ grams: Double, _ color: Color, _ label: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(color).frame(width: 30, height: 30)
                Text("\(Int(grams.rounded()))")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(LKColor.textMuted)
        }
    }
}

private extension View {
    /// Standard Health-tab card chrome (surface, rounded, inset).
    func card() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
            .padding(.horizontal, LKSpacing.md)
    }
}
