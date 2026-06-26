import SwiftUI
import SwiftData

/// Searchable exercise library picker (Option C): pick a canonical Exercise by
/// identity, with Favorites + Recent sections and a "create custom" escape hatch.
/// Selecting returns the Exercise so the caller can bind its stable id.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    let onSelect: (Exercise) -> Void

    @State private var search = ""
    @State private var customMuscle: MuscleGroup = .other
    @State private var customSecondary: Set<MuscleGroup> = []

    private var trimmed: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [Exercise] {
        guard !trimmed.isEmpty else { return allExercises }
        return allExercises.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var favorites: [Exercise] { filtered.filter(\.isFavorite) }

    /// Exercises that have logged sets, most recently used first.
    private var recents: [Exercise] {
        filtered
            .compactMap { ex -> (Exercise, Date)? in
                guard let last = ex.entries.flatMap({ $0.sets }).map(\.completedAt).max() else { return nil }
                return (ex, last)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    private var exactMatchExists: Bool {
        let lower = trimmed.lowercased()
        return allExercises.contains { $0.name.lowercased() == lower }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty && !exactMatchExists {
                    Section {
                        Button { createAndSelect() } label: {
                            Label("Add \u{201C}\(trimmed)\u{201D}", systemImage: "plus.circle.fill")
                                .foregroundColor(LKColor.accent)
                        }
                        .listRowBackground(LKColor.surface)
                        Picker("Primary muscle", selection: $customMuscle) {
                            ForEach(MuscleGroup.allCases) { m in Text(m.label).tag(m) }
                        }
                        .listRowBackground(LKColor.surface)
                        Menu {
                            ForEach(MuscleGroup.allCases) { m in
                                if m != customMuscle {
                                    Button {
                                        if customSecondary.contains(m) { customSecondary.remove(m) }
                                        else { customSecondary.insert(m) }
                                    } label: {
                                        if customSecondary.contains(m) {
                                            Label(m.label, systemImage: "checkmark")
                                        } else {
                                            Text(m.label)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Also targets").foregroundColor(LKColor.textPrimary)
                                Spacer()
                                Text(customSecondary.isEmpty ? "None"
                                     : customSecondary.map { $0.label }.sorted().joined(separator: ", "))
                                    .foregroundColor(LKColor.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(LKColor.surface)
                    }
                }

                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { row($0) }
                    }
                }

                if trimmed.isEmpty && !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { row($0) }
                    }
                }

                Section(trimmed.isEmpty ? "All Exercises" : "Results") {
                    ForEach(filtered) { row($0) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LKColor.background.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search or add an exercise")
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LKColor.textSecondary)
                }
            }
        }
    }

    private func row(_ ex: Exercise) -> some View {
        Button {
            onSelect(ex)
            HapticManager.shared.buttonTap()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name)
                        .font(LKFont.body)
                        .foregroundColor(LKColor.textPrimary)
                    let muscleText = ex.allMuscles.map { $0.label }.joined(separator: ", ")
                    let subtitle = [ex.equipmentEnum.flatMap { $0 == .none ? nil : $0.rawValue },
                                    muscleText.isEmpty ? nil : muscleText].compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(LKFont.caption)
                            .foregroundColor(LKColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    ex.isFavorite.toggle()
                    try? context.save()
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: ex.isFavorite ? "star.fill" : "star")
                        .foregroundColor(ex.isFavorite ? LKColor.accent : LKColor.textMuted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(ex.isFavorite ? "Unfavorite" : "Favorite")
            }
        }
        .listRowBackground(LKColor.surface)
    }

    private func createAndSelect() {
        let name = trimmed
        guard !name.isEmpty else { return }
        if let existing = allExercises.first(where: { $0.name.lowercased() == name.lowercased() }) {
            onSelect(existing); dismiss(); return
        }
        let ex = Exercise(name: name, isCustom: true)
        ex.primaryMuscle = ExerciseLibrary.defaultMuscle(forName: name) ?? customMuscle
        let libSecondaries = ExerciseLibrary.defaultSecondaries(forName: name)
        ex.secondaryMuscles = libSecondaries.isEmpty
            ? customSecondary.filter { $0 != ex.primaryMuscle }.sorted { $0.rawValue < $1.rawValue }
            : libSecondaries
        context.insert(ex)
        try? context.save()
        onSelect(ex)
        dismiss()
    }
}
