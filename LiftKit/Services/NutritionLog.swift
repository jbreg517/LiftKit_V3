import Foundation
import SwiftData

/// Data layer for nutrition logging on top of `NutritionDay` / `FoodEntry`,
/// plus the one-time migration that turns legacy aggregate days into entries.
/// Pure SwiftData — no networking, no HealthKit (those land in later phases).
enum NutritionLog {

    // MARK: - Migration (FR-MIG)

    private static let backfillKey = "nutritionEntriesBackfilled.v1"

    /// One-time migration guard: represent each pre-existing aggregate
    /// `NutritionDay` as a single manual `FoodEntry` so day totals become the
    /// sum of entries. Runs at most once per install. Returns days migrated.
    @discardableResult
    static func backfillEntriesIfNeeded(context: ModelContext,
                                        defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: backfillKey) else { return 0 }
        let migrated = backfillEntries(context: context)
        defaults.set(true, forKey: backfillKey)
        return migrated
    }

    /// The backfill pass itself (no run-once flag) — also the unit-test seam.
    /// Idempotent: days that already have entries are skipped, so totals are
    /// never double-counted.
    @discardableResult
    static func backfillEntries(context: ModelContext) -> Int {
        let days = (try? context.fetch(FetchDescriptor<NutritionDay>())) ?? []
        var migrated = 0
        for day in days where (day.entries ?? []).isEmpty && !day.isEmpty {
            let entry = FoodEntry(
                loggedAt: day.date,
                mealType: .snack,
                quantity: 1,
                enteredAsGrams: false,
                macros: Macros(proteinG: day.proteinG, carbG: day.carbG,
                               fatG: day.fatG, alcoholG: day.alcoholG),
                foodItem: nil
            )
            entry.nutritionDay = day
            context.insert(entry)
            migrated += 1
        }
        if migrated > 0 { try? context.save() }
        return migrated
    }

    // MARK: - Logging

    /// Add a logged serving to the given day and refresh the day's cached totals.
    @discardableResult
    static func addEntry(macros: Macros,
                         mealType: MealType,
                         food: FoodItem?,
                         quantity: Double,
                         enteredAsGrams: Bool,
                         on date: Date,
                         context: ModelContext) -> FoodEntry {
        let day = nutritionDay(for: date, context: context)
        let entry = FoodEntry(loggedAt: Date(),
                              mealType: mealType,
                              quantity: quantity,
                              enteredAsGrams: enteredAsGrams,
                              macros: macros,
                              foodItem: food)
        entry.nutritionDay = day
        context.insert(entry)
        food?.lastUsedAt = Date()
        try? context.save()          // persist + establish the inverse
        day.recalcTotals()
        try? context.save()
        return entry
    }

    /// Remove a logged serving and refresh the day's cached totals.
    static func remove(_ entry: FoodEntry, context: ModelContext) {
        let day = entry.nutritionDay
        context.delete(entry)
        try? context.save()
        day?.recalcTotals()
        try? context.save()
    }

    // MARK: - Food cache

    /// Find an existing cached `FoodItem` matching the lookup result (by barcode,
    /// else name + source), or create + insert one. Refreshes `lastUsedAt`.
    static func findOrCreateFoodItem(from result: FoodResult, context: ModelContext) -> FoodItem {
        let all = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        let match = all.first { item in
            if let bc = result.barcode, !bc.isEmpty { return item.barcode == bc }
            return item.name == result.name && item.sourceRaw == result.source.rawValue
        }
        if let match {
            match.lastUsedAt = Date()
            return match
        }
        let item = FoodItem(result)
        context.insert(item)
        return item
    }

    // MARK: - Lookup

    /// The `NutritionDay` for the given calendar day, creating one if needed.
    static func nutritionDay(for date: Date, context: ModelContext) -> NutritionDay {
        let start = Calendar.current.startOfDay(for: date)
        let all = (try? context.fetch(FetchDescriptor<NutritionDay>())) ?? []
        if let existing = all.first(where: { Calendar.current.isDate($0.date, inSameDayAs: start) }) {
            return existing
        }
        let day = NutritionDay(date: start)
        context.insert(day)
        return day
    }
}
