import XCTest
@testable import LiftKit

/// Decode + normalization + orchestration tests for the lookup layer
/// (REQUIREMENTS Layer 2, UAT Suites B/C). No network: the pure decode seams are
/// exercised with captured JSON fixtures, and the fallback chain with stubs.
final class FoodLookupTests: XCTestCase {

    // MARK: - USDA decode / normalize

    func testUSDADecodeAndNormalize() throws {
        let json = """
        { "foods": [
          { "fdcId": 2001, "description": "Yogurt, Greek, plain, nonfat",
            "brandName": "Fage", "gtinUpc": "00012345678905",
            "servingSize": 170, "servingSizeUnit": "g",
            "householdServingFullText": "1 container",
            "foodNutrients": [
              {"nutrientId":1003,"value":10.0},
              {"nutrientId":1004,"value":0.0},
              {"nutrientId":1005,"value":3.6},
              {"nutrientId":1008,"value":59},
              {"nutrientId":1018,"value":0.0}
            ] }
        ] }
        """.data(using: .utf8)!
        let results = try USDAFoodDataClient.decodeSearch(json)
        XCTAssertEqual(results.count, 1)
        let r = try XCTUnwrap(results.first)
        XCTAssertEqual(r.name, "Yogurt, Greek, plain, nonfat")
        XCTAssertEqual(r.brand, "Fage")
        XCTAssertEqual(r.barcode, "00012345678905")
        XCTAssertEqual(r.source, .usda)
        XCTAssertEqual(r.servingGrams, 170, accuracy: 0.001)
        XCTAssertEqual(r.servingDescription, "1 container")
        // per-100 g protein 10 scaled to a 170 g serving = 17
        XCTAssertEqual(r.macrosPerServing.proteinG, 17, accuracy: 0.0001)
        XCTAssertEqual(r.macrosPerServing.carbG, 6.12, accuracy: 0.0001)
        XCTAssertEqual(r.macrosPerServing.fatG, 0, accuracy: 0.0001)
    }

    func testUSDANoServingDefaultsTo100g() throws {
        let json = """
        { "foods": [
          { "fdcId": 7, "description": "Broccoli, raw",
            "foodNutrients": [ {"nutrientId":1003,"value":2.8}, {"nutrientId":1005,"value":6.6} ] }
        ] }
        """.data(using: .utf8)!
        let r = try XCTUnwrap(try USDAFoodDataClient.decodeSearch(json).first)
        XCTAssertEqual(r.servingGrams, 100, accuracy: 0.001)
        XCTAssertEqual(r.servingDescription, "100 g")
        XCTAssertEqual(r.macrosPerServing.proteinG, 2.8, accuracy: 0.0001)
    }

    func testUSDANonGramServingDefaultsTo100g() throws {
        let json = """
        { "foods": [
          { "fdcId": 8, "description": "Milk", "servingSize": 1, "servingSizeUnit": "cup",
            "foodNutrients": [ {"nutrientId":1003,"value":3.4} ] }
        ] }
        """.data(using: .utf8)!
        let r = try XCTUnwrap(try USDAFoodDataClient.decodeSearch(json).first)
        XCTAssertEqual(r.servingGrams, 100, accuracy: 0.001)   // non-gram unit → 100 g basis
    }

    func testUSDAEmptyFoods() throws {
        let json = "{ \"foods\": [] }".data(using: .utf8)!
        XCTAssertTrue(try USDAFoodDataClient.decodeSearch(json).isEmpty)
    }

    func testUSDASearchURL() throws {
        let url = try USDAFoodDataClient.searchURL(query: "egg", apiKey: "ABC", brandedOnly: true)
        let s = url.absoluteString
        XCTAssertTrue(s.contains("api_key=ABC"))
        XCTAssertTrue(s.contains("query=egg"))
        XCTAssertTrue(s.contains("dataType=Branded"))
    }

    // MARK: - OFF decode / normalize

    func testOFFDecodeAndNormalize() throws {
        let json = """
        { "status": 1, "code": "3017620422003",
          "product": {
            "product_name": "Nutella",
            "brands": "Ferrero, Nutella",
            "serving_size": "15 g",
            "serving_quantity": 15,
            "nutriments": {
              "energy-kcal_100g": 539,
              "proteins_100g": 6.3,
              "carbohydrates_100g": 57.5,
              "fat_100g": 30.9,
              "alcohol_100g": 0
            } } }
        """.data(using: .utf8)!
        let r = try XCTUnwrap(try OpenFoodFactsClient.decodeProduct(json, barcode: "3017620422003"))
        XCTAssertEqual(r.name, "Nutella")
        XCTAssertEqual(r.brand, "Ferrero")          // first brand only
        XCTAssertEqual(r.barcode, "3017620422003")
        XCTAssertEqual(r.source, .off)
        XCTAssertEqual(r.servingGrams, 15, accuracy: 0.001)
        XCTAssertEqual(r.servingDescription, "15 g")
        XCTAssertEqual(r.macrosPerServing.carbG, 57.5 * 0.15, accuracy: 0.0001)
        XCTAssertEqual(r.macrosPerServing.fatG, 30.9 * 0.15, accuracy: 0.0001)
    }

    func testOFFNotFoundReturnsNil() throws {
        let json = "{ \"status\": 0, \"code\": \"0000\" }".data(using: .utf8)!
        XCTAssertNil(try OpenFoodFactsClient.decodeProduct(json, barcode: "0000"))
    }

    func testOFFLenientStringNumbers() throws {
        let json = """
        { "status": 1, "product": {
            "product_name": "Stringy",
            "serving_quantity": "30",
            "nutriments": { "proteins_100g": "10", "carbohydrates_100g": "20", "fat_100g": "5" }
        } }
        """.data(using: .utf8)!
        let r = try XCTUnwrap(try OpenFoodFactsClient.decodeProduct(json, barcode: "1"))
        XCTAssertEqual(r.servingGrams, 30, accuracy: 0.001)
        XCTAssertEqual(r.macrosPerServing.proteinG, 10 * 0.30, accuracy: 0.0001)
    }

    func testOFFProductURLTrimsBarcode() throws {
        let url = try OpenFoodFactsClient.productURL(barcode: " 12345 ")
        XCTAssertEqual(url.absoluteString, "https://world.openfoodfacts.org/api/v0/product/12345.json")
    }

    // MARK: - Orchestrator fallback chain

    private struct StubText: FoodTextSearch {
        let results: [FoodResult]
        func search(query: String) async throws -> [FoodResult] { results }
    }
    private struct StubBarcode: FoodBarcodeLookup {
        var result: FoodResult?
        var error: Error?
        func lookup(barcode: String) async throws -> FoodResult? {
            if let error { throw error }
            return result
        }
    }
    private func sample(_ id: String) -> FoodResult {
        FoodResult(id: id, name: id, brand: nil, barcode: nil, source: .usda,
                   servingDescription: "100 g", servingGrams: 100, macrosPerServing: Macros())
    }

    func testFallbackUsesSecondWhenFirstMisses() async throws {
        let usda = sample("usda:1")
        let service = FoodLookupService(textSearch: StubText(results: []),
                                        barcodeProviders: [StubBarcode(result: nil),
                                                           StubBarcode(result: usda)])
        let r = try await service.lookup(barcode: "x")
        XCTAssertEqual(r, usda)
    }

    func testFallbackSkipsErroringProvider() async throws {
        let good = sample("off:1")
        let service = FoodLookupService(textSearch: StubText(results: []),
                                        barcodeProviders: [StubBarcode(error: NutritionAPIError.transport),
                                                           StubBarcode(result: good)])
        let r = try await service.lookup(barcode: "x")
        XCTAssertEqual(r, good)
    }

    func testLookupReturnsNilWhenAllMiss() async throws {
        let service = FoodLookupService(textSearch: StubText(results: []),
                                        barcodeProviders: [StubBarcode(result: nil),
                                                           StubBarcode(result: nil)])
        let r = try await service.lookup(barcode: "x")
        XCTAssertNil(r)
    }

    func testLookupThrowsWhenAllError() async {
        let service = FoodLookupService(textSearch: StubText(results: []),
                                        barcodeProviders: [StubBarcode(error: NutritionAPIError.transport)])
        do {
            _ = try await service.lookup(barcode: "x")
            XCTFail("Expected a thrown error when every provider fails")
        } catch {
            XCTAssertEqual(error as? NutritionAPIError, .transport)
        }
    }

    func testSearchTrimsAndShortCircuitsEmpty() async throws {
        let service = FoodLookupService(textSearch: StubText(results: [sample("usda:1")]),
                                        barcodeProviders: [])
        let empty = try await service.search("   ")
        XCTAssertTrue(empty.isEmpty)
        let nonEmpty = try await service.search(" egg ")
        XCTAssertEqual(nonEmpty.count, 1)
    }

    // MARK: - FoodItem bridge

    func testFoodItemFromResult() {
        let r = FoodResult(id: "usda:1", name: "Egg", brand: "Farm", barcode: "123",
                           source: .usda, servingDescription: "1 large (50 g)",
                           servingGrams: 50, macrosPerServing: Macros(proteinG: 6, carbG: 0.4, fatG: 5))
        let item = FoodItem(r)
        XCTAssertEqual(item.name, "Egg")
        XCTAssertEqual(item.brand, "Farm")
        XCTAssertEqual(item.barcode, "123")
        XCTAssertEqual(item.source, .usda)
        XCTAssertEqual(item.servingGrams, 50, accuracy: 0.001)
        XCTAssertEqual(item.proteinGPerServing, 6, accuracy: 0.0001)
        XCTAssertEqual(item.caloriesPerServing,
                       Macros(proteinG: 6, carbG: 0.4, fatG: 5).calories, accuracy: 0.0001)
    }
}
