import Foundation

// MARK: - Normalized result

/// Provider-agnostic food returned by a lookup, normalized so USDA and Open Food
/// Facts produce the same shape. Calories are always derived from macros
/// (Atwater) downstream — never carried here. Persist by converting to a
/// `FoodItem` via `FoodItem.init(_:)`.
struct FoodResult: Equatable, Identifiable {
    var id: String              // e.g. "usda:2001" or "off:3017620422003"
    var name: String
    var brand: String?
    var barcode: String?
    var source: FoodSource
    var servingDescription: String
    var servingGrams: Double
    var macrosPerServing: Macros
}

extension FoodItem {
    /// Build a persistable `FoodItem` from a normalized lookup result.
    convenience init(_ result: FoodResult) {
        self.init(name: result.name,
                  brand: result.brand,
                  barcode: result.barcode,
                  source: result.source,
                  servingDescription: result.servingDescription,
                  servingGrams: result.servingGrams,
                  proteinGPerServing: result.macrosPerServing.proteinG,
                  carbGPerServing: result.macrosPerServing.carbG,
                  fatGPerServing: result.macrosPerServing.fatG,
                  alcoholGPerServing: result.macrosPerServing.alcoholG)
    }
}

// MARK: - Provider protocols

/// Free-text search over a food database (USDA FoodData Central).
protocol FoodTextSearch {
    func search(query: String) async throws -> [FoodResult]
}

/// Barcode / UPC resolution (Open Food Facts, USDA branded). Returns nil when the
/// barcode isn't found — distinct from a thrown transport/decoding error.
protocol FoodBarcodeLookup {
    func lookup(barcode: String) async throws -> FoodResult?
}

// MARK: - Errors

enum NutritionAPIError: Error, Equatable {
    case invalidURL
    case http(Int)
    case notFound
    case transport
}

// MARK: - Config

enum NutritionAPIConfig {
    /// USDA FoodData Central key, read from the `USDA_FDC_API_KEY` Info.plist
    /// entry (populated from Secrets.xcconfig / CI). Falls back to USDA's public,
    /// rate-limited `DEMO_KEY` so development and tests work with no setup.
    static var usdaAPIKey: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "USDA_FDC_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (raw.isEmpty || raw.hasPrefix("$(")) ? "DEMO_KEY" : raw
    }
}

// MARK: - Shared HTTP helpers

extension URLSession {
    /// Session tuned for nutrition lookups: short timeouts so the UI never hangs.
    static let nutrition: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}

/// Decodes lenient JSON numbers that may arrive as Double, Int or String
/// (Open Food Facts is inconsistent here).
struct LenientDouble: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
        else { value = 0 }
    }
}

enum NutritionHTTP {
    /// Perform the request, mapping non-2xx and transport failures to `NutritionAPIError`.
    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NutritionAPIError.transport
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 404 ? NutritionAPIError.notFound : NutritionAPIError.http(http.statusCode)
        }
        return data
    }
}
