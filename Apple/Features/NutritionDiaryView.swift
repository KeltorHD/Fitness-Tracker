import FitnessTrackerCore
import SwiftUI
import UIKit

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

private enum NutritionSheet: Identifiable {
  case food(FoodEntry)
  case water
  case copy(MealKind?)
  var id: String {
    switch self {
    case .food(let entry): "food_\(entry.id)"
    case .water: "water"
    case .copy(let meal): "copy_\(meal?.rawValue ?? "all")"
    }
  }
}

struct NutritionDiaryView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @Bindable var model: NutritionDiaryModel
  @Binding var date: Date
  var isSelected: Bool
  @State private var sheet: NutritionSheet?
  @State private var pendingDelete: FoodEntry?

  var body: some View {
    List {
      if let error = model.error {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
          Button(L10n.text("Повторить", locale: locale)) { model.reload() }
        }.cardListRow()
      }
      if let notice = model.notice {
        HStack {
          Label(L10n.text(notice, locale: locale), systemImage: "checkmark.circle")
          Spacer()
          Button(L10n.text("Закрыть", locale: locale), systemImage: "xmark") { model.notice = nil }
            .labelStyle(.iconOnly)
        }.font(.subheadline).cardListRow()
      }
      if model.loaded {
        NutritionDiaryInsightsView(day: model.day, date: date, goal: model.goal).cardListRow()
        HStack {
          NavigationLink {
            NutritionGoalEditor(model: model)
          } label: {
            Label(L10n.text("Цели питания", locale: locale), systemImage: "target")
          }
          .accessibilityIdentifier("nutritionGoals")
          Spacer(minLength: 8)
          NavigationLink {
            NutritionWeekView(model: model)
          } label: {
            Label(L10n.text("За 7 дней", locale: locale), systemImage: "chart.bar")
          }
          .accessibilityIdentifier("nutritionWeek")
        }.buttonStyle(.bordered).controlSize(.small).cardListRow()
        NutritionWaterCard(model: model, date: date) { sheet = .water }.cardListRow()
        ForEach(MealKind.allCases, id: \.self) { meal in
          Section {
            let entries = model.meals[meal] ?? []
            if entries.isEmpty {
              Text(L10n.text("Пока нет записей", locale: locale)).font(.subheadline)
                .foregroundStyle(.secondary).cardListRow()
            }
            ForEach(entries) { entry in
              VStack(alignment: .leading, spacing: 5) {
                Button {
                  sheet = .food(entry)
                } label: {
                  FoodEntryRow(entry: entry)
                }
                .buttonStyle(.plain).accessibilityIdentifier("foodEntry_\(entry.id)")
                ForEach(entry.portions.filter { $0.product.id.hasPrefix("perek:") }) { portion in
                  FoodProductSource(product: portion.product)
                }
              }.fitCard().cardListRow()
                .contextMenu {
                  Button(L10n.text("Изменить", locale: locale)) { sheet = .food(entry) }
                  Button(L10n.text("Повторить на другую дату", locale: locale)) {
                    sheet = .food(
                      entry.repeated(
                        on: NutritionCalendar.date(on: date, timeOf: entry.date, calendar: calendar)
                      ))
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
            Button(L10n.text("Добавить еду", locale: locale), systemImage: "plus.circle.fill") {
              sheet = .food(
                FoodEntry(
                  date: NutritionCalendar.date(on: date, timeOf: .now, calendar: calendar),
                  meal: meal))
            }.accessibilityIdentifier("addFood_\(meal.rawValue)").cardListRow()
          } header: {
            HStack {
              Text(L10n.text(meal.title, locale: locale)).font(.headline)
              Spacer()
              if let entries = model.meals[meal], !entries.isEmpty,
                entries.allSatisfy(\.needsNutrition)
              {
                Text("—")
              } else {
                Text(
                  L10n.format(
                    "%@ ккал",
                    (model.meals[meal] ?? []).reduce(0) { $0 + $1.nutrients.calories }
                      .formatted(.number.precision(.fractionLength(0))), locale: locale))
              }
              Menu {
                Button(
                  L10n.text("Скопировать приём пищи", locale: locale), systemImage: "doc.on.doc"
                ) { sheet = .copy(meal) }
                .disabled((model.meals[meal] ?? []).isEmpty)
              } label: {
                Image(systemName: "ellipsis")
              }
              .accessibilityLabel(L10n.text("Скопировать приём пищи", locale: locale))
            }.textCase(nil)
          }
        }
        Button(
          L10n.text("Скопировать питание за день", locale: locale), systemImage: "doc.on.doc"
        ) { sheet = .copy(nil) }
        .disabled(model.day.entries.isEmpty).accessibilityIdentifier("copyNutritionDay")
        .cardListRow()
        if !model.savedMeals.isEmpty {
          DisclosureGroup(L10n.text("Сохранённые блюда", locale: locale)) {
            ForEach(model.savedMeals) { entry in
              VStack(alignment: .leading, spacing: 5) {
                Button {
                  sheet = .food(
                    entry.repeated(
                      on: NutritionCalendar.date(on: date, timeOf: .now, calendar: calendar)))
                } label: {
                  FoodEntryRow(entry: entry)
                }.buttonStyle(.plain)
                ForEach(entry.portions.filter { $0.product.id.hasPrefix("perek:") }) { portion in
                  FoodProductSource(product: portion.product)
                }
              }
            }
          }.cardListRow()
        }
        Section { FoodDatabaseAttribution() }
      }
    }
    .listStyle(.plain).scrollContentBackground(.hidden).background(FitTheme.paper)
    .scrollDismissesKeyboard(.interactively)
    .refreshable { model.reload() }
    .onAppear {
      model.selectDay(date, calendar: calendar)
      model.reload()
    }
    .onDisappear { if sheet == nil { model.isPresenting = false } }
    .onChange(of: date) { model.selectDay(date, calendar: calendar) }
    .onChange(of: calendar) { model.selectDay(date, calendar: calendar) }
    .onChange(of: phase) { if phase == .active && isSelected { model.reload() } }
    .onChange(of: sheet?.id) { model.isPresenting = sheet != nil }
    .sheet(item: $sheet, onDismiss: { model.isPresenting = false }) { value in
      switch value {
      case .food(let entry): FoodEntryEditor(diary: model, entry: entry)
      case .water: NavigationStack { NutritionWaterEditor(model: model, date: date) }
      case .copy(let meal):
        NavigationStack {
          NutritionCopyView(model: model, date: date, meal: meal, calendar: calendar)
        }
      }
    }
    .confirmationDialog(
      L10n.text("Удалить запись питания?", locale: locale),
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
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

/// Attribution travels with the saved product, including offline diary entries.
struct FoodProductSource: View {
  @Environment(\.locale) private var locale
  let product: FoodProduct
  var body: some View {
    if product.id.hasPrefix("perek:"), let url = product.sourceURL,
      url.scheme == "https", url.host == "perek.us"
    {
      Link(L10n.text("Данные: perek.us", locale: locale), destination: url).font(.caption)
    }
  }
}
