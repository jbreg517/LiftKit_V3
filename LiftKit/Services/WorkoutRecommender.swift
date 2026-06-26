import Foundation

/// Orders the recommended-workout catalog for a user based on recent training,
/// recovery load, and their weight goal. Entirely on-device, no external calls.
///
/// Signals:
/// - Overworked (≥5 sessions in the last 7 days) → surface mobility/recovery.
/// - Weight-loss goal (HealthProfile) → surface weight-loss workouts.
/// - Under-trained muscles (well below the 14-day average) → surface workouts
///   that hit them.
/// - Variety → gently demote the same workout style as the last session.
enum WorkoutRecommender {
    struct Pick: Identifiable {
        let workout: RecommendedWorkout
        let reason: String?
        var id: String { workout.id }
    }

    static func top(_ n: Int, sessions: [WorkoutSession], health: HealthProfile?,
                    available: Set<Equipment>? = nil) -> [Pick] {
        Array(recommendations(sessions: sessions, health: health, available: available).prefix(n))
    }

    static func recommendations(sessions: [WorkoutSession],
                                health: HealthProfile?,
                                available: Set<Equipment>? = nil,
                                catalog: [RecommendedWorkout] = RecommendedWorkouts.all) -> [Pick] {
        // Hide workouts that need gear the user doesn't have (bodyweight always ok).
        let usable = available.map { avail in catalog.filter { $0.isDoable(with: avail) } } ?? catalog
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) ?? now

        let completed = sessions.filter { !$0.isActive }
        let sessionsThisWeek = completed.filter { $0.startedAt >= weekAgo }.count
        let overworked = sessionsThisWeek >= 5
        let weightLoss = health?.goalType == .lose

        // Set credit per muscle over the last 14 days (primary full, secondary half).
        var setsByMuscle: [MuscleGroup: Double] = [:]
        for s in completed where s.startedAt >= twoWeeksAgo {
            for e in s.entries {
                guard let ex = e.exercise else { continue }
                let setCount = Double(e.sets.count)
                for c in ex.muscleContributions {
                    setsByMuscle[c.muscle, default: 0] += setCount * c.weight
                }
            }
        }

        // Under-trained = clearly below the average across trackable muscles.
        let trackable: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps,
                                        .quads, .hamstrings, .glutes, .calves, .core]
        let trainedTotal = trackable.reduce(0.0) { $0 + (setsByMuscle[$1] ?? 0) }
        let avg = trainedTotal / Double(trackable.count)
        let undertrained: Set<MuscleGroup> = trainedTotal == 0 ? [] :
            Set(trackable.filter { (setsByMuscle[$0] ?? 0) < avg * 0.5 })

        let lastType = completed.max(by: { $0.startedAt < $1.startedAt })?.timerType

        func evaluate(_ w: RecommendedWorkout) -> (score: Double, reason: String?) {
            var score = 0.0
            var reason: String?
            let isMobility = w.purposes.contains(.mobility)

            if overworked {
                if isMobility { score += 6; reason = "Recovery — you’ve trained hard this week" }
                else { score -= 2 }
            } else if w.purposes.count == 1 && isMobility {
                // When fresh, don't push pure-mobility sessions to the top.
                score -= 1
            }

            if weightLoss && w.purposes.contains(.weightLoss) {
                score += 4
                if reason == nil { reason = "Supports your weight-loss goal" }
            }

            let hits = undertrained.intersection(w.muscles)
            if !hits.isEmpty {
                score += Double(min(hits.count, 3)) * 2
                if reason == nil, let m = hits.min(by: { $0.rawValue < $1.rawValue }) {
                    reason = "Rounds out your week with \(m.label.lowercased())"
                }
            }

            if let lastType, w.type == lastType { score -= 1 }   // encourage variety

            return (score, reason)
        }

        // Stable sort: score desc, catalog order as tie-breaker.
        return usable.enumerated()
            .map { (offset, w) -> (Int, Double, Pick) in
                let r = evaluate(w)
                return (offset, r.score, Pick(workout: w, reason: r.reason))
            }
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0 < b.0 }
            .map { $0.2 }
    }
}
