import FitLifeCore
import SwiftUI

struct NutritionGoalEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  let model: NutritionDiaryModel
  private let workspaceID: UUID
  @State private var calories: String
  @State private var protein: String
  @State private var fat: String
  @State private var carbs: String
  @State private var water: String
  @State private var error: String?
  init(model: NutritionDiaryModel) {
    self.model = model
    workspaceID = model.workspaceID
    _calories = State(initialValue: model.goal.map { String($0.calories) } ?? "")
    _protein = State(initialValue: model.goal?.protein.map(String.init(describing:)) ?? "")
    _fat = State(initialValue: model.goal?.fat.map(String.init(describing:)) ?? "")
    _carbs = State(initialValue: model.goal?.carbohydrates.map(String.init(describing:)) ?? "")
    _water = State(initialValue: model.goal?.waterMilliliters.map(String.init(describing:)) ?? "")
  }
  var body: some View {
    Form {
      Section {
        field("Калории, ккал", $calories)
        field("Белки, г", $protein)
        field("Жиры, г", $fat)
        field("Углеводы, г", $carbs)
        field("Цель воды, мл", $water)
      } footer: {
        Text(
          L10n.text(
            "Укажите собственную дневную цель. Цели БЖУ и воды необязательны. Калории тренировок не вычитаются из съеденного.",
            locale: locale))
      }
      Button(L10n.text("Сохранить", locale: locale)) { save() }
      if model.goal != nil {
        Button(L10n.text("Убрать цель", locale: locale), role: .destructive) {
          guard workspaceID == model.workspaceID else {
            dismiss()
            return
          }
          if model.saveGoal(nil) { dismiss() } else { error = model.error }
        }
      }
      if let error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
    }.navigationTitle(L10n.text("Цели питания", locale: locale))
      .onAppear { model.isPresenting = true }
      .onDisappear { model.isPresenting = false }
  }
  private func field(_ title: String, _ binding: Binding<String>) -> some View {
    HStack {
      Text(L10n.text(title, locale: locale))
      TextField(L10n.text(title, locale: locale), text: binding).keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
    }
  }
  private func save() {
    guard workspaceID == model.workspaceID else {
      dismiss()
      return
    }
    do {
      func optional(_ text: String) throws -> Double? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : try NutritionInput.number(text)
      }
      let goal = try NutritionGoal(
        calories: NutritionInput.number(calories), protein: optional(protein),
        fat: optional(fat), carbohydrates: optional(carbs), waterMilliliters: optional(water))
      try goal.validate()
      if model.saveGoal(goal) { dismiss() } else { error = model.error }
    } catch { self.error = error.localizedDescription }
  }
}
