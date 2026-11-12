import Charts
import FitLifeCore
import SwiftUI

struct NutritionWaterCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  let model: NutritionDiaryModel
  let date: Date
  let customAmount: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(L10n.text("Вода", locale: locale), systemImage: "drop.fill").font(.headline)
        Spacer()
        Text(
          L10n.format(
            "%@ мл", model.waterToday.reduce(0) { $0 + $1.milliliters }.formatted(), locale: locale)
        )
        .font(.title3.bold()).monospacedDigit().accessibilityIdentifier("waterTotal")
      }
      if let goal = model.goal?.waterMilliliters {
        ProgressView(value: min(model.waterToday.reduce(0) { $0 + $1.milliliters } / goal, 1))
        Text(L10n.format("Цель воды: %@ мл", goal.formatted(), locale: locale)).font(.caption)
          .foregroundStyle(.secondary)
      }
      ViewThatFits(in: .horizontal) {
        HStack { actions }
        VStack(alignment: .leading) { actions }
      }.buttonStyle(.bordered).controlSize(.small)
      if let last = model.waterToday.first {
        Button(
          L10n.text("Убрать последнюю запись воды", locale: locale),
          systemImage: "arrow.uturn.backward"
        ) {
          model.deleteWater(last)
        }.font(.caption).accessibilityIdentifier("undoWater")
      }
    }.fitCard()
  }
  @ViewBuilder private var actions: some View {
    ForEach([150, 250, 500], id: \.self) { amount in
      Button(L10n.format("+ %@ мл", String(amount), locale: locale)) {
        model.addWater(Double(amount), on: date, calendar: calendar)
      }.accessibilityIdentifier("addWater_\(amount)")
    }
    Button(L10n.text("Другой объём", locale: locale), action: customAmount)
  }
}

struct NutritionWaterEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.dismiss) private var dismiss
  let model: NutritionDiaryModel
  let date: Date
  @State private var amount = ""
  @State private var error: String?
  private let workspaceID: UUID
  init(model: NutritionDiaryModel, date: Date) {
    self.model = model
    self.date = date
    workspaceID = model.workspaceID
  }
  var body: some View {
    Form {
      TextField(L10n.text("Объём, мл", locale: locale), text: $amount).keyboardType(.decimalPad)
      Button(L10n.text("Сохранить", locale: locale)) {
        guard model.workspaceID == workspaceID else {
          dismiss()
          return
        }
        do {
          let value = try NutritionInput.number(amount)
          try WaterEntry(date: date, milliliters: value).validate()
          if model.addWater(value, on: date, calendar: calendar) {
            dismiss()
          } else {
            error = model.error
          }
        } catch { self.error = error.localizedDescription }
      }
      if let error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
    }.navigationTitle(L10n.text("Записать воду", locale: locale))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
      }
  }
}

struct NutritionCopyView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.dismiss) private var dismiss
  let model: NutritionDiaryModel
  let date: Date
  let meal: MealKind?
  private let workspaceID: UUID
  @State private var target: Date
  @State private var copied = false
  init(model: NutritionDiaryModel, date: Date, meal: MealKind?, calendar: Calendar) {
    self.model = model
    self.date = date
    self.meal = meal
    self.workspaceID = model.workspaceID
    _target = State(initialValue: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
  }
  var body: some View {
    Form {
      Text(date, format: .dateTime.day().month(.wide).year())
      Text(L10n.text(meal?.title ?? "Все приёмы пищи", locale: locale))
      DatePicker(
        L10n.text("Копировать на дату", locale: locale), selection: $target,
        displayedComponents: .date)
      Text(
        L10n.text(
          "Создадутся новые записи с теми же порциями, составом и заметками. Исходный день не изменится.",
          locale: locale)
      ).font(.footnote).foregroundStyle(.secondary)
      Button(L10n.text("Скопировать", locale: locale)) {
        guard !copied, model.workspaceID == workspaceID else { return }
        if model.copyMeals(from: date, meal: meal, to: target, calendar: calendar) {
          copied = true
          dismiss()
        }
      }.disabled(copied).accessibilityIdentifier("confirmCopyNutrition")
      if let error = model.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
    }.navigationTitle(L10n.text("Копировать питание", locale: locale))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
      }
  }
}

struct NutritionWeekView: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var theme
  let model: NutritionDiaryModel
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if let start = model.week.first?.date, let end = model.week.last?.date {
          Text(
            start.formatted(.dateTime.locale(locale).day().month()) + " – "
              + end.formatted(.dateTime.locale(locale).day().month())
          )
          .font(.subheadline).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 12) {
          Text(L10n.text("Калории по дням", locale: locale)).font(.headline)
          Chart(model.week.filter { $0.entryCount > $0.incompleteCount }) { day in
            BarMark(
              x: .value(L10n.text("Дата", locale: locale), day.date, unit: .day),
              y: .value(L10n.text("Калории, ккал", locale: locale), day.total.calories)
            )
            .foregroundStyle(theme.accent)
          }.frame(height: 180)
          Text(
            L10n.text(
              "Дни без записей не означают нулевое потребление. Фото без КБЖУ делают итог неполным.",
              locale: locale)
          ).font(.caption).foregroundStyle(.secondary)
        }.fitCard()
        ForEach(model.week) { day in
          VStack(alignment: .leading, spacing: 8) {
            Text(day.date, format: .dateTime.weekday(.wide).day().month()).font(.headline)
            if day.entryCount > day.incompleteCount {
              Text(
                L10n.format(
                  "%@ ккал", day.total.calories.formatted(.number.precision(.fractionLength(0))),
                  locale: locale))
              NutrientValues(value: day.total)
              if day.incompleteCount > 0 {
                Text(L10n.text("КБЖУ не заполнены", locale: locale)).font(.caption).foregroundStyle(
                  .secondary)
              }
            } else {
              Text(
                L10n.text(
                  day.entryCount > 0 ? "КБЖУ не заполнены" : "Нет записей питания", locale: locale)
              ).foregroundStyle(.secondary)
            }
            if day.waterMilliliters > 0 {
              Text(L10n.format("Вода: %@ мл", day.waterMilliliters.formatted(), locale: locale))
            }
          }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
        }
      }.padding(16)
    }.background(FitTheme.paper).navigationTitle(L10n.text("Питание за 7 дней", locale: locale))
  }
}
