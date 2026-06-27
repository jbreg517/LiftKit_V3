import Foundation

/// USDA FoodData Central client: free-text search + branded-UPC lookup. FDC
/// nutrient values are per 100 g; we scale to the listed serving when one is
/// given, otherwise treat a serving as 100 g.
struct USDAFoodDataClient: FoodTextSearch, FoodBarcodeLookup {
    var apiKey: String = NutritionAPIConfig.usdaAPIKey
    var session: URLSession = .nutrition

    private static let base = "https://api.nal.usda.gov/fdc/v1/foods/search"

    func search(query: String) async throws -> [FoodResult] {
        let url = try Self.searchURL(query: query, apiKey: apiKey, brandedOnly: false)
        let data = try await NutritionHTTP.data(for: URLRequest(url: url), session: session)
        return try Self.decodeSearch(data)
    }

    func lookup(barcode: String) async throws -> FoodResult? {
        let url = try Self.searchURL(query: barcode, apiKey: apiKey, brandedOnly: true)
        let data = try await NutritionHTTP.data(for: URLRequest(url: url), session: session)
        let results = try Self.decodeSearch(data)
        return results.first { $0.barcode == barcode } ?? results.first
    }

    // MARK: Pure seams (unit-tested with fixtures)

    static func searchURL(query: String, apiKey: String, brandedOnly: Bool) throws -> URL {
        guard var comps = URLComponents(string: base) else { throw NutritionAPIError.invalidURL }
        var items = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "25")
        ]
        if brandedOnly { items.append(URLQueryItem(name: "dataType", value: "Branded")) }
        comps.queryItems = items
        guard let url = comps.url else { throw NutritionAPIError.invalidURL }
        return url
    }

    static func decodeSearch(_ data: Data) throws -> [FoodResult] {
        let resp = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return (resp.foods ?? []).compactMap(normalize)
    }

    static func normalize(_ food: USDAFood) -> FoodResult? {
        guard let name = food.description, !name.isEmpty else { return nil }
        func per100(_ id: Int) -> Double {
            food.foodNutrients?.first { $0.nutrientId == id }?.value ?? 0
        }
        // FDC nutrient IDs: 1003 protein, 1004 fat, 1005 carbs, 1018 alcohol.
        let per100 = Macros(proteinG: per100(1003), carbG: per100(1005),
                            fatG: per100(1004), alcoholG: per100(1018))
        let unit = (food.servingSizeUnit ?? "").lowercased()
        let gramUnits: Set<String> = ["g", "grm", "gram", "grams"]
        let servingGrams: Double = (gramUnits.contains(unit) && (food.servingSize ?? 0) > 0)
            ? food.servingSize! : 100
        let perServing = per100.scaled(by: servingGrams / 100)
        let desc = (food.householdServingFullText?.isEmpty == false)
            ? food.householdServingFullText!
            : "\(Int(servingGrams)) g"
        let id = food.fdcId.map { "usda:\($0)" } ?? "usda:\(name)"
        return FoodResult(id: id,
                          name: name,
                          brand: food.brandName ?? food.brandOwner,
                          barcode: food.gtinUpc,
                          source: .usda,
                          servingDescription: desc,
                          servingGrams: servingGrams,
                          macrosPerServing: perServing)
    }
}

// MARK: - USDA DTOs

struct USDASearchResponse: Decodable {
    let foods: [USDAFood]?
}

struct USDAFood: Decodable {
    let fdcId: Int?
    let description: String?
    let brandName: String?
    let brandOwner: String?
    let gtinUpc: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodNutrients: [USDANutrient]?
}

struct USDANutrient: Decodable {
    let nutrientId: Int?
    let value: Double?
}
