import FitLifeCore
import SwiftUI

struct BodyWeightEditor: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Environment(AppStore.self) private var store
  @State private var model: BodyWeightEditorModel
  private let workoutID: UUID?
  private let canClear: Bool
  private let isCompletedWorkout: Bool
  private let updatesCurrentWeight: Bool
  private let measurementWorkoutID: UUID?

  init(
    entry: BodyWeightEntry? = nil, workout: Workout? = nil, initialWeightKG: Double? = nil,
    updatesCurrentWeight: Bool = false, unit: WeightUnit
  ) {
    workoutID = workout?.id
    isCompletedWorkout = workout?.status == .completed
    canClear = workout?.status == .completed && workout?.bodyWeightKG != nil
    self.updatesCurrentWeight = updatesCurrentWeight
    measurementWorkoutID = entry?.workoutID
    _model = State(
      initialValue: BodyWeightEditorModel(
        weightKG: workout?.bodyWeightKG ?? entry?.weightKG ?? initialWeightKG,
        date: workout?.startedAt ?? entry?.measuredAt ?? Date(),
        id: entry?.id ?? UUID(), unit: unit, locale: L10n.numberLocale))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            TextField(L10n.text("Вес тела", locale: locale), text: $model.text)
              .keyboardType(.decimalPad).accessibilityIdentifier("bodyWeightInput")
            Text(L10n.text(model.unit.rawValue, locale: locale)).foregroundStyle(.secondary)
          }
          if workoutID == nil && !updatesCurrentWeight {
            DatePicker(
              L10n.text("Дата взвешивания", locale: locale), selection: $model.date,
              in: ...Date(), displayedComponents: [.date, .hourAndMinute])
          } else if workoutID != nil {
            LabeledContent(L10n.text("Тренировка", locale: locale)) {
              Text(model.date, format: .dateTime.day().month().year())
            }
          }
        } footer: {
          Text(
            L10n.text(
              footer,
              locale: locale))
        }
        if canClear {
          Section {
            Button(L10n.text("Убрать вес из тренировки", locale: locale), role: .destructive) {
              if let workoutID { finish(store.setBodyWeight(nil, for: workoutID)) }
            }
          }
        }
        if let error = model.error {
          Section { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
        }
      }
      .navigationTitle(L10n.text("Записать вес", locale: locale)).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Сохранить", locale: locale)) { save() }
            .accessibilityIdentifier("saveBodyWeight")
        }
      }
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    }
    .tint(colorTheme.accent)
    .onAppear { store.showingBodyWeightEditor = true }
    .onDisappear { store.showingBodyWeightEditor = false }
  }

  private var footer: String {
    if isCompletedWorkout {
      return "Вес относится к этой тренировке. После завершения он появится в общей истории веса."
    }
    if workoutID == nil && !updatesCurrentWeight {
      return "Запись хранится в истории веса. Вес прошедших тренировок не изменится."
    }
    return "Вес сохранится в настройках и истории веса. Вес прошедших тренировок не изменится."
  }

  private func save() {
    do {
      let value = try model.valueInKG()
      if updatesCurrentWeight {
        finish(store.setCurrentBodyWeight(value))
      } else if let workoutID {
        finish(store.setBodyWeight(value, for: workoutID))
      } else {
        let entry = BodyWeightEntry(
          id: model.id, measuredAt: model.date, weightKG: value, workoutID: measurementWorkoutID)
        finish(store.saveBodyWeight(entry))
      }
    } catch {
      model.error = error.localizedDescription
    }
  }
  private func finish(_ saved: Bool) {
    if saved {
      dismiss()
    } else {
      model.error = store.error ?? "Не удалось сохранить вес. Попробуйте ещё раз."
      store.error = nil
    }
  }
}

struct WorkoutBodyWeightRow: View {
  @Environment(\.locale) private var locale
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var editing = false
  let workout: Workout
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent(L10n.text("Вес тела", locale: locale)) {
        Text(
          workout.bodyWeightKG.map {
            "\(unit.display($0).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))) \(L10n.text(unit.rawValue, locale: locale))"
          } ?? "—"
        ).monospacedDigit()
      }
      Button(
        L10n.text(workout.bodyWeightKG == nil ? "Указать вес" : "Изменить вес", locale: locale)
      ) {
        editing = true
      }.accessibilityIdentifier("editWorkoutBodyWeight")
    }
    .sheet(isPresented: $editing) { BodyWeightEditor(workout: workout, unit: unit) }
  }
}
