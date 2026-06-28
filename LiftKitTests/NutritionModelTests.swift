import XCTest
import SwiftData
@testable import LiftKit

/// Covers the nutrition data model + migration (REQUIREMENTS §5, UAT Suite J).
final class NutritionModelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([NutritionDay.self, FoodItem.self, FoodEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NutritionModelTests.\(UUID().uuidString)")!
    }

    // MARK: - Atwater / Macros

    func testCaloriesDerivedFromMacros() {
        let m = Macros(proteinG: 10, carbG: 20, fatG: 5, alcoholG: 0)
        XCTAssertEqual(m.calories, 10*4 + 20*4 + 5*9, accuracy: 0.0001)
    }

    func testCaloriesIncludeAlcohol() {
        let m = Macros(alcoholG: 14)
        XCTAssertEqual(m.calories, 14 * 7, accuracy: 0.0001)
    }

    func testMacrosScale() {
        let m = Macros(proteinG: 10, carbG: 20, fatG: 5, alcoholG: 1).scaled(by: 1.5)
        XCTAssertEqual(m.proteinG, 15, accuracy: 0.0001)
        XCTAssertEqual(m.carbG, 30, accuracy: 0.0001)
        XCTAssertEqual(m.fatG, 7.5, accuracy: 0.0001)
        XCTAssertEqual(m.alcoholG, 1.5, accuracy: 0.0001)
    }

    func testMacrosSum() {
        let total = Macros(proteinG: 10, carbG: 5) + Macros(proteinG: 20, fatG: 8)
        XCTAssertEqual(total.proteinG, 30, accuracy: 0.0001)
        XCTAssertEqual(total.carbG, 5, accuracy: 0.0001)
        XCTAssertEqual(total.fatG, 8, accuracy: 0.0001)
    }

    // MARK: - FoodItem serving / gram math (UAT-D1..D3)

    func testFoodItemServingMacros() {
        let item = FoodItem(name: "Greek Yogurt", source: .usda,
                            servingDescription: "1 container (170 g)", servingGrams: 170,
                            proteinGPerServing: 17, carbGPerServing: 6, fatGPerServing: 0)
        let m = item.macros(servings: 2)
        XCTAssertEqual(m.proteinG, 34, accuracy: 0.0001)
        XCTAssertEqual(m.carbG, 12, accuracy: 0.0001)
        XCTAssertEqual(item.source, .usda)
    }

    func testFoodItemGramMacros() {
        let item = FoodItem(name: "Greek Yogurt", servingGrams: 170,
                            proteinGPerServing: 17, carbGPerServing: 6)
        // 85 g = half a serving
        let m = item.macros(grams: 85)
        XCTAssertEqual(m.proteinG, 8.5, accuracy: 0.0001)
        XCTAssertEqual(m.carbG, 3, accuracy: 0.0001)
    }

    func testFoodItemGramMacrosUnknownServingGrams() {
        let item = FoodItem(name: "Mystery", servingGrams: 0, proteinGPerServing: 10)
        XCTAssertEqual(item.macros(grams: 100), Macros())   // empty when grams unknown
    }

    // MARK: - FoodEntry helpers

    func testFoodEntryHealthKitUUIDRoundTrip() {
        let entry = FoodEntry(macros: Macros(proteinG: 1))
        let ids = [UUID(), UUID()]
        entry.healthKitSampleUUIDs = ids
        XCTAssertEqual(entry.healthKitSampleUUIDs, ids)
        XCTAssertFalse(entry.healthKitSampleIDs.isEmpty)
    }

    func testMealTypeSuggestion() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
        }
        XCTAssertEqual(MealType.suggested(for: at(8), calendar: cal), .breakfast)
        XCTAssertEqual(MealType.suggested(for: at(13), calendar: cal), .lunch)
        XCTAssertEqual(MealType.suggested(for: at(19), calendar: cal), .dinner)
        XCTAssertEqual(MealType.suggested(for: at(23), calendar: cal), .snack)
    }

    // MARK: - Day rollup (UAT-E4, F4)

    func testAddEntryRecomputesDayTotal() throws {
        let date = Date()
        _ = NutritionLog.addEntry(macros: Macros(proteinG: 10, carbG: 20, fatG: 5),
                                  mealType: .breakfast, food: nil, quantity: 1,
                                  enteredAsGrams: false, on: date, context: context)
        _ = NutritionLog.addEntry(macros: Macros(proteinG: 30, fatG: 10),
                                  mealType: .lunch, food: nil, quantity: 1,
                                  enteredAsGrams: false, on: date, context: context)

        let days = try context.fetch(FetchDescriptor<NutritionDay>())
        XCTAssertEqual(days.count, 1, "Both entries should attach to the same day")
        let day = try XCTUnwrap(days.first)
        XCTAssertEqual(day.proteinG, 40, accuracy: 0.0001)
        XCTAssertEqual(day.carbG, 20, accuracy: 0.0001)
        XCTAssertEqual(day.fatG, 15, accuracy: 0.0001)
        XCTAssertEqual(day.calories,
                       Macros(proteinG: 40, carbG: 20, fatG: 15).calories, accuracy: 0.0001)
        XCTAssertEqual(day.sortedEntries.count, 2)
    }

    func testRemoveEntryRecomputesDayTotal() throws {
        let date = Date()
        let e1 = NutritionLog.addEntry(macros: Macros(proteinG: 10), mealType: .breakfast,
                                       food: nil, quantity: 1, enteredAsGrams: false,
                                       on: date, context: context)
        _ = NutritionLog.addEntry(macros: Macros(proteinG: 30), mealType: .lunch,
                                   food: nil, quantity: 1, enteredAsGrams: false,
                                   on: date, context: context)
        let day = try XCTUnwrap(e1.nutritionDay)
        XCTAssertEqual(day.proteinG, 40, accuracy: 0.0001)

        NutritionLog.remove(e1, context: context)
        XCTAssertEqual(day.proteinG, 30, accuracy: 0.0001)
        XCTAssertEqual(day.sortedEntries.count, 1)
    }

    func testFoodEntryUpdatesLastUsed() throws {
        let item = FoodItem(name: "Oats", proteinGPerServing: 5)
        let old = Date(timeIntervalSince1970: 0)
        item.lastUsedAt = old
        context.insert(item)
        _ = NutritionLog.addEntry(macros: item.macros(servings: 1), mealType: .breakfast,
                                  food: item, quantity: 1, enteredAsGrams: false,
                                  on: Date(), context: context)
        XCTAssertGreaterThan(item.lastUsedAt, old)
    }

    // MARK: - Migration (FR-MIG, UAT Suite J)

    func testMigrationConvertsAggregateDayToSingleEntry() throws {
        let day = NutritionDay(date: Date())
        day.proteinG = 100; day.carbG = 200; day.fatG = 50
        context.insert(day)
        try context.save()

        let migrated = NutritionLog.backfillEntries(context: context)
        XCTAssertEqual(migrated, 1)
        XCTAssertEqual(day.sortedEntries.count, 1)
        let entry = try XCTUnwrap(day.sortedEntries.first)
        XCTAssertNil(entry.foodItem)
        XCTAssertEqual(entry.mealType, .snack)
        XCTAssertEqual(entry.proteinG, 100, accuracy: 0.0001)
        XCTAssertEqual(entry.carbG, 200, accuracy: 0.0001)
        XCTAssertEqual(entry.fatG, 50, accuracy: 0.0001)
    }

    func testMigrationPreservesTotalsNoDoubleCount() throws {
        let day = NutritionDay(date: Date())
        day.proteinG = 100; day.carbG = 200; day.fatG = 50
        context.insert(day)
        try context.save()
        let before = day.calories

        _ = NutritionLog.backfillEntries(context: context)
        day.recalcTotals()   // totals now derived from entries
        XCTAssertEqual(day.calories, before, accuracy: 0.0001)
        XCTAssertEqual(day.proteinG, 100, accuracy: 0.0001)
        XCTAssertEqual(day.carbG, 200, accuracy: 0.0001)
        XCTAssertEqual(day.fatG, 50, accuracy: 0.0001)
    }

    func testMigrationIdempotent() throws {
        let day = NutritionDay(date: Date())
        day.proteinG = 100
        context.insert(day)
        try context.save()

        let first = NutritionLog.backfillEntries(context: context)
        let second = NutritionLog.backfillEntries(context: context)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0, "A day that already has entries must be skipped")
        XCTAssertEqual(day.sortedEntries.count, 1)
    }

    func testMigrationSkipsEmptyDays() throws {
        let day = NutritionDay(date: Date())   // all zero
        context.insert(day)
        try context.save()
        let migrated = NutritionLog.backfillEntries(context: context)
        XCTAssertEqual(migrated, 0)
        XCTAssertTrue(day.sortedEntries.isEmpty)
    }

    func testMigrationRunOnceFlag() throws {
        let defaults = freshDefaults()
        let day = NutritionDay(date: Date())
        day.proteinG = 50
        context.insert(day)
        try context.save()

        let first = NutritionLog.backfillEntriesIfNeeded(context: context, defaults: defaults)
        let second = NutritionLog.backfillEntriesIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0, "The run-once flag must prevent a second pass")
    }

    func testMigratedDayPlusNewEntry() throws {
        let day = NutritionDay(date: Date())
        day.proteinG = 100
        context.insert(day)
        try context.save()
        _ = NutritionLog.backfillEntries(context: context)

        _ = NutritionLog.addEntry(macros: Macros(proteinG: 25), mealType: .dinner,
                                  food: nil, quantity: 1, enteredAsGrams: false,
                                  on: Date(), context: context)
        XCTAssertEqual(day.proteinG, 125, accuracy: 0.0001)
        XCTAssertEqual(day.sortedEntries.count, 2)
    }

    // MARK: - Food cache dedupe

    func testFindOrCreateDedupesByBarcode() throws {
        let r = FoodResult(id: "off:1", name: "Soda", brand: "X", barcode: "111",
                           source: .off, servingDescription: "330 ml", servingGrams: 330,
                           macrosPerServing: Macros(carbG: 35))
        let a = NutritionLog.findOrCreateFoodItem(from: r, context: context)
        let b = NutritionLog.findOrCreateFoodItem(from: r, context: context)
        XCTAssertTrue(a === b)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FoodItem>()).count, 1)
    }

    func testFindOrCreateDedupesByNameAndSource() throws {
        let r = FoodResult(id: "usda:1", name: "Banana", brand: nil, barcode: nil,
                           source: .usda, servingDescription: "1 medium", servingGrams: 118,
                           macrosPerServing: Macros(carbG: 27))
        let a = NutritionLog.findOrCreateFoodItem(from: r, context: context)
        let b = NutritionLog.findOrCreateFoodItem(from: r, context: context)
        XCTAssertTrue(a === b)
    }
}
