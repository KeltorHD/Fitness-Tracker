import FitLifeCore
import SwiftUI

struct WorkoutSupersetRequest: Identifiable {
  let id = UUID()
  let workoutID: UUID
  var initialRowID: UUID? = nil
}

struct WorkoutSupersetEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.dismiss) private var dismiss
  let workout: Workout
  let save: ([UUID]) -> String?
  @State private var selection: Set<UUID>
  @State private var error: String?

  init(workout: Workout, initialRowID: UUID?, save: @escaping ([UUID]) -> String?) {
    self.workout = workout
    self.save = save
    let initialRows = initialRowID.map { workout.supersetRows(for: $0) } ?? []
    _selection = State(initialValue: Set(initialRows.map(\.id)))
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            L10n.text(
              "Выберите минимум два упражнения. Выполняйте по одному подходу каждого упражнения; отдых начнётся после полного круга.",
              locale: locale)
          )
          .font(.subheadline).foregroundStyle(.secondary)
        }
        Section {
          ForEach(workout.exercises) { row in
            Button {
              let ids = Set(workout.supersetRows(for: row.id).map(\.id))
              if selection.contains(row.id) {
                selection.subtract(ids)
              } else {
                selection.formUnion(ids)
              }
              error = nil
            } label: {
              HStack(spacing: 12) {
                Image(systemName: selection.contains(row.id) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selection.contains(row.id) ? colorTheme.accent : FitTheme.muted)
                VStack(alignment: .leading, spacing: 4) {
                  Text(L10n.exerciseName(row.exercise, locale: locale)).foregroundStyle(.primary)
                  if row.supersetID != nil {
                    Text(L10n.text("Включается весь суперсет", locale: locale))
                      .font(.caption).foregroundStyle(.secondary)
                  }
                }
              }.frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(row.id) ? [.isSelected] : [])
            .accessibilityIdentifier("supersetCandidate_\(row.id)")
          }
        }
        if let error {
          Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red)
        }
      }
      .navigationTitle(L10n.text("Объединить в суперсет", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Объединить", locale: locale)) {
            let ids = workout.exercises.filter { selection.contains($0.id) }.map(\.id)
            if let message = save(ids) {
              error = message
            } else {
              dismiss()
            }
          }
          .disabled(selection.count < 2 || workout.status != .active)
          .accessibilityIdentifier("saveWorkoutSuperset")
        }
      }
      .accessibilityIdentifier("workoutSupersetEditor")
    }
  }
}
