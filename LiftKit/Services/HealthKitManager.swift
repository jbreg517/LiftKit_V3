import Foundation
import HealthKit

/// Opt-in bridge to Apple Health. OFF by default and entirely gated behind the
/// `healthKitEnabled` setting — when that's off, every method is a no-op so the
/// rest of the app behaves exactly as it did before HealthKit existed.
///
/// Two jobs, using Apple Health as the shared exchange with other apps:
///   • Read  — nutrition (energy + macros) that any app has logged.
///   • Write — completed workouts and their estimated calorie burn.
///
/// Nothing here leaves the device except into the user's own Health store.
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    /// Mirrors the user's setting so callers can early-out without importing
    /// `@AppStorage`. AppStorage writes to standard UserDefaults under this key.
    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: "healthKitEnabled") }

    /// Health data is unavailable on some devices (and the simulator's reads are
    /// limited). The Settings toggle is disabled when this is false.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
        ]
    }

    // MARK: - Authorization

    /// Presents the Health permission sheet. Returns false only when Health is
    /// unavailable or the request errors. Note: HealthKit deliberately hides the
    /// user's *read* choices, so a `true` result doesn't guarantee read access —
    /// reads simply come back empty if the user declined them.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Read nutrition

    /// One day's nutrition totals pulled from Apple Health.
    struct DailyMacros: Identifiable {
        var date: Date
        var energyKcal: Double
        var proteinG: Double
        var carbG: Double
        var fatG: Double

        var id: Date { date }

        /// Logged calories, falling back to Atwater from macros when energy
        /// itself wasn't logged (some apps log macros but not total energy).
        var displayCalories: Double {
            energyKcal > 0 ? energyKcal : proteinG * 4 + carbG * 4 + fatG * 9
        }

        var isEmpty: Bool { energyKcal == 0 && proteinG == 0 && carbG == 0 && fatG == 0 }
    }

    /// Totals for the given local day. nil when disabled or unavailable.
    func macros(on day: Date) async -> DailyMacros? {
        guard isEnabled, isAvailable else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? day
        return await macros(start: start, end: end, label: start)
    }

    /// One non-empty `DailyMacros` per logged day across the inclusive date
    /// range. Empty array when disabled or unavailable.
    func dailyMacros(from start: Date, to end: Date) async -> [DailyMacros] {
        guard isEnabled, isAvailable else { return [] }
        let cal = Calendar.current
        var result: [DailyMacros] = []
        var dayStart = cal.startOfDay(for: start)
        let lastStart = cal.startOfDay(for: end)
        while dayStart <= lastStart {
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            if let m = await macros(start: dayStart, end: dayEnd, label: dayStart), !m.isEmpty {
                result.append(m)
            }
            dayStart = dayEnd
        }
        return result
    }

    private func macros(start: Date, end: Date, label: Date) async -> DailyMacros? {
        async let energy = sum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)
        async let protein = sum(.dietaryProtein, unit: .gram(), start: start, end: end)
        async let carb = sum(.dietaryCarbohydrates, unit: .gram(), start: start, end: end)
        async let fat = sum(.dietaryFatTotal, unit: .gram(), start: start, end: end)
        return DailyMacros(date: label,
                           energyKcal: await energy,
                           proteinG: await protein,
                           carbG: await carb,
                           fatG: await fat)
    }

    /// Cumulative sum of a quantity type over [start, end). 0 on any failure.
    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum)
        do {
            let stats = try await descriptor.result(for: store)
            return stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Write workout

    /// Maps a LiftKit timer style to the closest Apple Health workout type.
    static func activityType(for timerType: TimerType?) -> HKWorkoutActivityType {
        switch timerType {
        case .reps:                   return .traditionalStrengthTraining
        case .amrap, .emom, .forTime: return .functionalStrengthTraining
        case .intervals:              return .highIntensityIntervalTraining
        case .manual, .none:          return .functionalStrengthTraining
        }
    }

    /// Saves a completed session to Apple Health as an `HKWorkout` carrying its
    /// estimated active-energy burn. No-op when disabled/unavailable, the burn is
    /// zero, or the interval is invalid. Failures are swallowed — writing to
    /// Health is best-effort and must never disrupt finishing a workout.
    func saveWorkout(timerType: TimerType?,
                     start: Date,
                     end: Date,
                     energyKcal: Double) async {
        guard isEnabled, isAvailable, energyKcal > 0, end > start else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: timerType)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            let energyType = HKQuantityType(.activeEnergyBurned)
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal)
            let sample = HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
            // HKWorkoutBuilder.add(_:) has no async overload (only a completion
            // handler), unlike beginCollection/endCollection/finishWorkout — so
            // bridge it with a continuation.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.add([sample]) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Best-effort: a denied write or unavailable store shouldn't surface.
        }
    }
}
