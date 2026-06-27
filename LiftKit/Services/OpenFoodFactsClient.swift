import Foundation

/// Open Food Facts client: barcode → product. No API key; sends a descriptive
/// User-Agent per OFF guidelines. Nutriment values are per 100 g; we scale to
/// the product's serving when `serving_quantity` is given, else treat a serving
/// as 100 g.
struct OpenFoodFactsClient: FoodBarcodeLookup {
    var session: URLSession = .nutrition
    static let userAgent = "LiftKit/1.0 (iOS; +https://github.com/jbreg517/LiftKit_V3)"

    func lookup(barcode: String) async throws -> FoodResult? {
        let url = try Self.productURL(barcode: barcode)
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let data = try await NutritionHTTP.data(for: request, session: session)
            return try Self.decodeProduct(data, barcode: barcode)
        } catch NutritionAPIError.notFound {
            return nil
        }
    }

    // MARK: Pure seams (unit-tested with fixtures)

    static func productURL(barcode: String) throws -> URL {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(trimmed).json")
        else { throw NutritionAPIError.invalidURL }
        return url
    }

    static func decodeProduct(_ data: Data, barcode: String) throws -> FoodResult? {
        let resp = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard resp.status != 0, let p = resp.product else { return nil }
        let name = (p.productName?.isEmpty == false) ? p.productName! : "Unknown product"
        let n = p.nutriments
        let per100 = Macros(proteinG: n?.proteins100g?.value ?? 0,
                            carbG: n?.carbs100g?.value ?? 0,
                            fatG: n?.fat100g?.value ?? 0,
                            alcoholG: n?.alcohol100g?.value ?? 0)
        let servingGrams = (p.servingQuantity?.value ?? 0) > 0 ? p.servingQuantity!.value : 100
        let perServing = per100.scaled(by: servingGrams / 100)
        let desc = (p.servingSize?.isEmpty == false) ? p.servingSize! : "\(Int(servingGrams)) g"
        let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return FoodResult(id: "off:\(barcode)",
                          name: name,
                          brand: brand,
                          barcode: barcode,
                          source: .off,
                          servingDescription: desc,
                          servingGrams: servingGrams,
                          macrosPerServing: perServing)
    }
}

// MARK: - OFF DTOs

struct OFFResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: LenientDouble?
    let nutriments: OFFNutriments?
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
    }
}

struct OFFNutriments: Decodable {
    let proteins100g: LenientDouble?
    let carbs100g: LenientDouble?
    let fat100g: LenientDouble?
    let alcohol100g: LenientDouble?
    enum CodingKeys: String, CodingKey {
        case proteins100g = "proteins_100g"
        case carbs100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case alcohol100g = "alcohol_100g"
    }
}
