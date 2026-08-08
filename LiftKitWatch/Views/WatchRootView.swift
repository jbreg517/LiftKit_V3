import SwiftUI

/// The menu: what's due today, then saved plans.
///
/// Phase 2 of docs/WATCH-APP.md — this lists what the watch *could* run and starts
/// nothing. Tapping a row shows its detail so the sync can be verified end to end
/// before an `HKWorkoutSession` is wired underneath it.
struct WatchRootView: View {
    let store: WatchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.menu.scheduledToday.isEmpty && store.menu.plans.isEmpty {
                    emptyState
                } else {
                    menuList
                }
            }
            .navigationTitle("LiftKit")
        }
    }

    private var menuList: some View {
        List {
            if !store.menu.scheduledToday.isEmpty {
                Section("Today") {
                    ForEach(store.menu.scheduledToday) { row($0) }
                }
            }
            if !store.menu.plans.isEmpty {
                Section("Plans") {
                    ForEach(store.menu.plans) { row($0) }
                }
            }
        }
    }

    private func row(_ item: WatchMenu.Item) -> some View {
        NavigationLink {
            WatchWorkoutDetailView(item: item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.type.sfSymbol)
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name.isEmpty ? item.type.displayName : item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(item.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Two genuinely different empty states. Telling someone to open their phone
    /// when they've simply saved nothing would be wrong.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: store.hasSynced ? "dumbbell" : "iphone.and.arrow.forward")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(store.hasSynced ? "Nothing scheduled" : "Open LiftKit on your phone")
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(store.hasSynced
                 ? "Save a plan or schedule a workout on your phone."
                 : "Your workouts will appear here once it syncs.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// What this workout is, read on the wrist. Starting it comes in phase 3.
struct WatchWorkoutDetailView: View {
    let item: WatchMenu.Item

    var body: some View {
        List {
            Section(item.summary) {
                ForEach(item.exercises) { ex in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.name).font(.system(size: 14, weight: .medium))
                        Text(detail(ex))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(item.name.isEmpty ? item.type.displayName : item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ ex: WatchMenu.Exercise) -> String {
        var parts: [String] = []
        if ex.distanceMeters > 0 {
            parts.append("\(Int(ex.distanceMeters)) m")
        } else if ex.durationSeconds > 0 {
            parts.append("\(ex.durationSeconds)s")
        } else if ex.reps > 0 {
            parts.append(ex.sets > 1 ? "\(ex.sets)×\(ex.reps)" : "\(ex.reps) reps")
        }
        if ex.weight > 0 {
            parts.append("\(Int(ex.weight)) \(ex.weightUnit.rawValue)")
        }
        return parts.joined(separator: " · ")
    }
}
