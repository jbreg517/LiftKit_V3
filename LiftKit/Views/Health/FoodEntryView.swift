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
                    NutritionQuickAddSheet(mealName: mealType.label) { p, c, f, a in
                        logManual(p: p, c: c, f: f, a: a)
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
                Button { showManual = true } label: {
                    Label("Enter macros manually", systemImage: "square.and.pencil")
                        .foregroundColor(LKColor.accent)
                }
                .listRowBackground(LKColor.surface)

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

    private func logManual(p: Double, c: Double, f: Double, a: Double) {
        let macros = Macros(proteinG: p, carbG: c, fatG: f, alcoholG: a)
        guard macros.calories > 0 else { return }
        NutritionLog.addEntry(macros: macros, mealType: mealType, food: nil,
                              quantity: 1, enteredAsGrams: false, on: date, context: context)
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

    private var previewMacros: Macros {
        let servings = asGrams
            ? (result.servingGrams > 0 ? amountValue / result.servingGrams : 0)
            : amountValue
        return result.macrosPerServing.scaled(by: servings)
    }

    var body: some View {
        Form {
            Section {
                Text(result.name).font(LKFont.bodyBold).foregroundColor(LKColor.textPrimary)
                if let brand = result.brand, !brand.isEmpty {
                    Text(brand).font(LKFont.caption).foregroundColor(LKColor.textMuted)
                }
                Text(result.servingDescription).font(LKFont.caption).foregroundColor(LKColor.textMuted)
            }

            Section {
                if result.servingGrams > 0 {
                    Picker("Measure", selection: $asGrams) {
                        Text("Servings").tag(false)
                        Text("Grams").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text(asGrams ? "Grams" : "Servings")
                    Spacer()
                    TextField(asGrams ? "0" : "1", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            } footer: {
                Text("≈ \(Int(previewMacros.calories.rounded())) kcal · P\(Int(previewMacros.proteinG.rounded())) C\(Int(previewMacros.carbG.rounded())) F\(Int(previewMacros.fatG.rounded()))")
            }
        }
        .scrollContentBackground(.hidden)
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
}
