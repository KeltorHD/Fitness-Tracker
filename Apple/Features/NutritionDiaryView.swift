import FitnessTrackerCore
import SwiftUI
import UIKit

struct NutritionDiaryCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  let model: NutritionDiaryModel
  let date: Date
  var body: some View {
    NavigationLink {
      NutritionDiaryView(model: model, date: date).id(model.workspaceID)
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(L10n.text("Питание", locale: locale), systemImage: "fork.knife").font(
            .title2.bold())
          Spacer()
          Image(systemName: "chevron.right").font(.subheadline)
        }
        Text(date, format: .dateTime.day().month(.wide)).font(.subheadline).foregroundStyle(
          .secondary)
        if model.loaded {
          NutritionSummary(
            day: NutritionDay(entries: model.entries, date: date, calendar: calendar),
            goal: model.goal)
        } else {
          Text(
            L10n.text("Не удалось прочитать дневник питания. Повторите загрузку.", locale: locale))
        }
        Text(L10n.text("Записать еду или фото перекуса", locale: locale)).font(.subheadline)
      }.foregroundStyle(.primary).fitCard()
    }.buttonStyle(.plain).accessibilityIdentifier("nutritionDiary")
  }
}

struct NutritionSummary: View {
  @Environment(\.locale) private var locale
  let day: NutritionDay
  let goal: NutritionGoal?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        L10n.format(
          "%@ ккал", day.total.calories.formatted(.number.precision(.fractionLength(0))),
          locale: locale)
      )
      .font(.title.bold()).monospacedDigit()
      if let goal {
        ProgressView(value: min(day.total.calories / goal.calories, 1))
          .accessibilityLabel(L10n.text("Дневная цель калорий", locale: locale))
        Text(L10n.format("Цель: %@ ккал", goal.calories.formatted(), locale: locale)).font(
          .subheadline)
        Text(
          L10n.format(
            day.total.calories > goal.calories ? "Сверх цели: %@ ккал" : "Осталось: %@ ккал",
            abs(goal.calories - day.total.calories).formatted(
              .number.precision(.fractionLength(0))), locale: locale)
        )
        .font(.subheadline).foregroundStyle(.secondary)
      }
      NutrientValues(value: day.total, goal: goal)
      if day.incompleteCount > 0 {
        Label(
          L10n.text("Есть фото без КБЖУ — итог неполный", locale: locale),
          systemImage: "info.circle"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct NutrientValues: View {
  @Environment(\.locale) private var locale
  let value: Nutrients
  var goal: NutritionGoal? = nil
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 14) { values }
      VStack(alignment: .leading, spacing: 6) { values }
    }.font(.subheadline).monospacedDigit()
  }
  @ViewBuilder private var values: some View {
    metric("Белки", value.protein, goal?.protein)
    metric("Жиры", value.fat, goal?.fat)
    metric("Углеводы", value.carbohydrates, goal?.carbohydrates)
  }
  private func metric(_ title: String, _ amount: Double, _ target: Double?) -> some View {
    let number = amount.formatted(.number.precision(.fractionLength(0...1)))
    let text = target.map { number + " / " + $0.formatted() } ?? number
    return Text(L10n.text(title, locale: locale) + ": " + L10n.format("%@ г", text, locale: locale))
      .fixedSize(horizontal: false, vertical: true)
  }
}

struct NutritionDiaryView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @Bindable var model: NutritionDiaryModel
  @State var date: Date
  @State private var editing: FoodEntry?
  @State private var pendingDelete: FoodEntry?
  var body: some View {
    let day = NutritionDay(entries: model.entries, date: date, calendar: calendar)
    List {
      DatePicker(L10n.text("Дата", locale: locale), selection: $date, displayedComponents: .date)
      if let error = model.error {
        Section {
          Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
          Button(L10n.text("Повторить", locale: locale)) { model.reload() }
        }
      }
      if model.loaded {
        NutritionSummary(day: day, goal: model.goal).cardListRow()
        NavigationLink(L10n.text("Цели питания", locale: locale)) {
          NutritionGoalEditor(model: model)
        }
        if day.entries.isEmpty {
          ContentUnavailableView(
            L10n.text("Пока нет записей питания", locale: locale), systemImage: "fork.knife",
            description: Text(
              L10n.text(
                "Добавьте продукты или сохраните фото, чтобы заполнить КБЖУ позже.", locale: locale)
            ))
        }
        ForEach(MealKind.allCases, id: \.self) { meal in
          Section {
            ForEach(day.entries.filter { $0.meal == meal }) { entry in
              Button {
                editing = entry
              } label: {
                FoodEntryRow(entry: entry)
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button(L10n.text("Изменить", locale: locale)) { editing = entry }
                Button(L10n.text("Повторить на другую дату", locale: locale)) {
                  editing = entry.repeated(on: date)
                }
                Button(
                  L10n.text(
                    entry.isSavedMeal ? "Убрать из сохранённых блюд" : "Сохранить блюдо",
                    locale: locale)
                ) {
                  var updated = entry
                  updated.isSavedMeal.toggle()
                  model.save(updated)
                }
                Button(L10n.text("Удалить", locale: locale)) { pendingDelete = entry }
              }
              .swipeActions(allowsFullSwipe: false) {
                Button(L10n.text("Удалить", locale: locale)) { pendingDelete = entry }.tint(.red)
              }
            }
            Button(L10n.text("Добавить еду", locale: locale), systemImage: "plus") {
              editing = FoodEntry(date: date, meal: meal)
            }.accessibilityIdentifier("addFood_\(meal.rawValue)")
          } header: {
            HStack {
              Text(L10n.text(meal.title, locale: locale))
              Spacer()
              let total = day.entries.filter { $0.meal == meal }.reduce(0) {
                $0 + $1.nutrients.calories
              }
              Text(
                L10n.format(
                  "%@ ккал", total.formatted(.number.precision(.fractionLength(0))), locale: locale)
              )
            }
          }
        }
        if !model.savedMeals.isEmpty {
          Section(L10n.text("Сохранённые блюда", locale: locale)) {
            ForEach(model.savedMeals) { entry in
              Button {
                editing = entry.repeated(on: date)
              } label: {
                FoodEntryRow(entry: entry)
              }
              .buttonStyle(.plain)
            }
          }
        }
        Section { FoodDatabaseAttribution() }
      }
    }.navigationTitle(L10n.text("Питание", locale: locale))
      .refreshable { model.reload() }
      .onAppear {
        model.isPresenting = true
        model.reload()
      }
      .onDisappear { if editing == nil { model.isPresenting = false } }
      .onChange(of: phase) { if phase == .active { model.reload() } }
      .sheet(item: $editing, onDismiss: { model.isPresenting = true }) { entry in
        FoodEntryEditor(diary: model, entry: entry)
      }
      .confirmationDialog(
        L10n.text("Удалить запись питания?", locale: locale),
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible
      ) {
        Button(L10n.text("Удалить", locale: locale), role: .destructive) {
          if let pendingDelete { model.delete(pendingDelete) }
          pendingDelete = nil
        }
        Button(L10n.text("Отмена", locale: locale), role: .cancel) { pendingDelete = nil }
      }
  }
}

struct FoodEntryRow: View {
  @Environment(\.locale) private var locale
  let entry: FoodEntry
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      if let data = entry.photo, let image = UIImage(data: data) {
        Image(uiImage: image).resizable().scaledToFill().frame(width: 60, height: 60).clipped()
          .clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(entry.title).font(.headline)
        if entry.needsNutrition {
          Text(L10n.text("КБЖУ не заполнены", locale: locale)).foregroundStyle(.secondary)
        } else {
          Text(
            L10n.format(
              "%@ ккал", entry.nutrients.calories.formatted(.number.precision(.fractionLength(0))),
              locale: locale))
          NutrientValues(value: entry.nutrients)
        }
        if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) }
      }
    }.foregroundStyle(.primary).accessibilityElement(children: .combine)
  }
}

struct FoodDatabaseAttribution: View {
  @Environment(\.locale) private var locale
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      link("Open Food Facts", "https://world.openfoodfacts.org")
      Text("© Open Food Facts contributors")
      link("Данные: ODbL 1.0", "https://opendatacommons.org/licenses/odbl/1-0/")
      link("Фото продуктов: CC BY-SA 3.0", "https://creativecommons.org/licenses/by-sa/3.0/")
      Text(
        L10n.text(
          "База заполняется сообществом. Проверяйте КБЖУ на упаковке; не все продукты имеют фото и полные данные.",
          locale: locale)
      )
      .foregroundStyle(.secondary)
    }.font(.caption)
  }
  @ViewBuilder private func link(_ title: String, _ address: String) -> some View {
    if let url = URL(string: address) { Link(L10n.text(title, locale: locale), destination: url) }
  }
}
