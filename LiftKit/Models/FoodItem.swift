import Foundation
import SwiftData

/// A looked-up or manually-entered food, cached locally so it can be re-logged
/// offline and surfaced in "recent foods". Macros are stored per listed serving;
/// arbitrary gram amounts derive from `servingGrams`. Calories are always derived
/// from macros (Atwater) — never stored. CloudKit-compatible: every attribute has
/// a default.
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?
    /// Provenance: `usda`, `off` (Open Food Facts) or `manual`.
    var sourceRaw: String = FoodSource.manual.rawValue
    /// Human label for the listed serving, e.g. "1 container (170 g)".
    var servingDescription: String = ""
    /// Grams in one listed serving; 0 when unknown (gram entry then unavailable).
    var servingGrams: Double = 0
    var proteinGPerServing: Double = 0
    var carbGPerServing: Double = 0
    var fatGPerServing: Double = 0
    var alcoholGPerServing: Double = 0
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()

    init(name: String = "",
         brand: String? = nil,
         barcode: String? = nil,
         source: FoodSource = .manual,
         servingDescription: String = "",
         servingGrams: Double = 0,
         proteinGPerServing: Double = 0,
         carbGPerServing: Double = 0,
         fatGPerServing: Double = 0,
         alcoholGPerServing: Double = 0) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.sourceRaw = source.rawValue
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.proteinGPerServing = proteinGPerServing
        self.carbGPerServing = carbGPerServing
        self.fatGPerServing = fatGPerServing
        self.alcoholGPerServing = alcoholGPerServing
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Macros for one listed serving.
    var perServing: Macros {
        Macros(proteinG: proteinGPerServing, carbG: carbGPerServing,
               fatG: fatGPerServing, alcoholG: alcoholGPerServing)
    }

    var caloriesPerServing: Double { perServing.calories }

    /// Macros for `servings` listed servings (e.g. 1.5×).
    func macros(servings: Double) -> Macros { perServing.scaled(by: servings) }

    /// Macros for an arbitrary gram amount; empty when `servingGrams` is unknown.
    func macros(grams: Double) -> Macros {
        guard servingGrams > 0 else { return Macros() }
        return perServing.scaled(by: grams / servingGrams)
    }
}

/// Where a `FoodItem` came from.
enum FoodSource: String, Codable, CaseIterable {
    case usda, off, manual
    var label: String {
        switch self {
        case .usda:   return "USDA"
        case .off:    return "Open Food Facts"
        case .manual: return "Manual"
        }
    }
}

/// Atwater energy factors (kcal per gram) — the single source of truth for the
/// calories-from-macros derivation used across nutrition logging.
enum Atwater {
    static let protein = 4.0
    static let carb = 4.0
    static let fat = 9.0
    static let alcohol = 7.0

    static func calories(proteinG: Double, carbG: Double, fatG: Double, alcoholG: Double) -> Double {
        proteinG * protein + carbG * carb + fatG * fat + alcoholG * alcohol
    }
}

/// A lightweight macro tuple (grams). Calories are derived, never stored.
struct Macros: Equatable, Hashable {
    var proteinG: Double = 0
    var carbG: Double = 0
    var fatG: Double = 0
    var alcoholG: Double = 0

    var calories: Double {
        Atwater.calories(proteinG: proteinG, carbG: carbG, fatG: fatG, alcoholG: alcoholG)
    }

    func scaled(by factor: Double) -> Macros {
        Macros(proteinG: proteinG * factor, carbG: carbG * factor,
               fatG: fatG * factor, alcoholG: alcoholG * factor)
    }

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(proteinG: lhs.proteinG + rhs.proteinG,
               carbG: lhs.carbG + rhs.carbG,
               fatG: lhs.fatG + rhs.fatG,
               alcoholG: lhs.alcoholG + rhs.alcoholG)
    }
}
