import Foundation

/// Orchestrates the lookup chain (REQUIREMENTS §2.3 A5):
/// text search → USDA; barcode → Open Food Facts, then USDA branded as fallback.
/// The app's own store stays the source of truth; this only fetches + normalizes.
struct FoodLookupService {
    var textSearch: any FoodTextSearch
    /// Barcode providers tried in order until one returns a non-nil result.
    var barcodeProviders: [any FoodBarcodeLookup]

    func search(_ query: String) async throws -> [FoodResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return try await textSearch.search(query: q)
    }

    /// Resolve a barcode through the provider chain. Returns nil only when no
    /// provider found a match. If every provider failed with an error and none
    /// found anything, the last error is rethrown.
    func lookup(barcode: String) async throws -> FoodResult? {
        var lastError: Error?
        for provider in barcodeProviders {
            do {
                if let result = try await provider.lookup(barcode: barcode) {
                    return result
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }
}

extension FoodLookupService {
    /// Production wiring: USDA for text + branded fallback; Open Food Facts first
    /// for barcodes, then USDA branded.
    static func live() -> FoodLookupService {
        let usda = USDAFoodDataClient()
        let off = OpenFoodFactsClient()
        return FoodLookupService(textSearch: usda, barcodeProviders: [off, usda])
    }
}
