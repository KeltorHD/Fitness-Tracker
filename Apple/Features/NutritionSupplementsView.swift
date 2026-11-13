import FitLifeCore
import SwiftUI

struct NutritionSupplementsSection: View {
  @Environment(\.locale) private var locale
  let entries: [SupplementEntry]
  let add: (SupplementKind) -> Void
  let edit: (SupplementEntry) -> Void
  let repeatEntry: (SupplementEntry) -> Void
  let delete: (SupplementEntry) -> Void

  var body: some View {
    Section {
      if entries.isEmpty {
        Text(L10n.text("Приём добавок пока не записан", locale: locale))
          .foregroundStyle(.secondary).cardListRow()
      }
      ForEach(entries) { entry in
        Button {
          edit(entry)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
              Text(entry.name.isEmpty ? L10n.text(entry.kind.title, locale: locale) : entry.name)
                .font(.headline)
              Spacer(minLength: 8)
              Text(entry.date, format: .dateTime.hour().minute()).font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(
              entry.amount.formatted(.number.locale(locale).precision(.significantDigits(1...12)))
                + " " + L10n.text(entry.unit.symbol, locale: locale))
            if !entry.name.isEmpty {
              Text(L10n.text(entry.kind.title, locale: locale)).font(.caption)
                .foregroundStyle(.secondary)
            }
            if let nutrients = entry.nutrients {
              Text(
                L10n.format(
                  "%@ ккал",
                  nutrients.calories.formatted(
                    .number.locale(locale).precision(.fractionLength(0...1))),
                  locale: locale))
              NutrientValues(value: nutrients)
            } else {
              Text(
                L10n.text(
                  entry.includesNutrition ? "КБЖУ не заполнены" : "Не учитывается в КБЖУ",
                  locale: locale)
              ).font(.caption).foregroundStyle(.secondary)
            }
            if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
          }.foregroundStyle(.primary).accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain).accessibilityIdentifier("supplementEntry_\(entry.id)")
        .fitCard().cardListRow()
        .contextMenu {
          Button(L10n.text("Изменить", locale: locale)) { edit(entry) }
          Button(L10n.text("Повторить приём", locale: locale)) { repeatEntry(entry) }
          Button(L10n.text("Удалить", locale: locale), role: .destructive) { delete(entry) }
        }
        .swipeActions(allowsFullSwipe: false) {
          Button(L10n.text("Удалить", locale: locale), role: .destructive) { delete(entry) }
        }
      }
      Menu {
        ForEach(SupplementKind.allCases, id: \.self) { kind in
          Button(L10n.text(kind.title, locale: locale)) { add(kind) }
            .accessibilityIdentifier("addSupplement_" + kind.rawValue)
        }
      } label: {
        Label(L10n.text("Записать приём добавки", locale: locale), systemImage: "plus.circle.fill")
      }.accessibilityIdentifier("addSupplement").cardListRow()
    } header: {
      Text(L10n.text("БАДы и спортивное питание", locale: locale))
    } footer: {
      Text(
        L10n.text(
          "Записывайте фактически принятое количество. КБЖУ учитываются только при включённом учёте и заполненном составе с упаковки.",
          locale: locale))
    }
  }
}

struct SupplementEntryEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Environment(\.fitnessColorTheme) private var colorTheme
  let diary: NutritionDiaryModel
  @State private var model: SupplementEntryEditorModel
  private let workspaceID: UUID
  private let isPlan: Bool
  @State private var schedule: SupplementPlan
  @State private var saving = false
  @State private var saveTask: Task<Void, Never>?

  init(diary: NutritionDiaryModel, entry: SupplementEntry, plan: SupplementPlan? = nil) {
    self.diary = diary
    isPlan = plan != nil
    _schedule = State(initialValue: plan ?? SupplementPlan(prototype: entry))
    workspaceID = diary.workspaceID
    _model = State(initialValue: SupplementEntryEditorModel(entry: entry))
  }

  var body: some View {
    @Bindable var model = self.model
    NavigationStack {
      Form {
        Section {
          Picker(
            L10n.text("Вид добавки", locale: locale),
            selection: Binding(
              get: { model.kind }, set: { model.changeKind($0) })
          ) {
            ForEach(SupplementKind.allCases, id: \.self) { kind in
              Text(L10n.text(kind.title, locale: locale)).tag(kind)
            }
          }.accessibilityIdentifier("supplementKind")
          TextField(L10n.text("Название или бренд добавки", locale: locale), text: $model.name)
            .accessibilityIdentifier("supplementName")
          if !isPlan {
            DatePicker(L10n.text("Дата и время", locale: locale), selection: $model.date)
          }
          TextField(L10n.text("Принятое количество", locale: locale), text: $model.amount)
            .keyboardType(.decimalPad).accessibilityIdentifier("supplementAmount")
          Picker(
            L10n.text("Единицы количества", locale: locale),
            selection: Binding(
              get: { model.unit }, set: { model.changeUnit($0) })
          ) {
            ForEach(SupplementUnit.allCases, id: \.self) { unit in
              Text(L10n.text(unit.symbol, locale: locale)).tag(unit)
            }
          }.accessibilityIdentifier("supplementUnit")
        } footer: {
          Text(L10n.text("Для другой добавки обязательно укажите название.", locale: locale))
        }
        if isPlan { scheduleFields }
        Section {
          Toggle(L10n.text("Учитывать в КБЖУ", locale: locale), isOn: $model.includesNutrition)
            .accessibilityIdentifier("supplementIncludesNutrition")
          if model.includesNutrition {
            Text(L10n.text(model.unit.nutritionTitle, locale: locale)).font(.headline)
            nutrientField("Калории, ккал", text: $model.calories, id: "supplementCalories")
            nutrientField("Белки, г", text: $model.protein, id: "supplementProtein")
            nutrientField("Жиры, г", text: $model.fat, id: "supplementFat")
            nutrientField("Углеводы, г", text: $model.carbohydrates, id: "supplementCarbohydrates")
          }
        } footer: {
          Text(
            L10n.text(
              "Введите состав с упаковки целиком или оставьте все поля пустыми. Неизвестный состав не заменяется нулями. При смене единиц КБЖУ нужно заполнить заново.",
              locale: locale))
        }
        Section {
          TextField(L10n.text("Заметка", locale: locale), text: $model.note, axis: .vertical)
            .accessibilityIdentifier("supplementNote")
        }
        if let error = model.error {
          Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(L10n.text(isPlan ? "Расписание добавки" : "Приём добавки", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Сохранить", locale: locale)) { save() }
            .accessibilityIdentifier("saveSupplementEntry").disabled(saving)
        }
      }
    }.tint(colorTheme.accent)
      .onDisappear { saveTask?.cancel() }
  }

  private var scheduleFields: some View {
    Section {
      Toggle(L10n.text("Расписание включено", locale: locale), isOn: $schedule.enabled)
      Picker(L10n.text("Периодичность", locale: locale), selection: $schedule.recurrence) {
        ForEach(SupplementRecurrence.allCases, id: \.self) { recurrence in
          Text(L10n.text(recurrence.title, locale: locale)).tag(recurrence)
        }
      }
      if schedule.recurrence == .intervalDays {
        Stepper(value: $schedule.intervalDays, in: 1...365) {
          Text(L10n.format("Интервал, дней: %@", String(schedule.intervalDays), locale: locale))
        }
      }
      if schedule.recurrence == .weekdays {
        ForEach(WorkoutWeekday.allCases, id: \.rawValue) { day in
          Toggle(
            L10n.text(day.title, locale: locale),
            isOn: Binding(
              get: { schedule.weekdays.contains(day.rawValue) },
              set: { selected in
                schedule.weekdays.removeAll { $0 == day.rawValue }
                if selected { schedule.weekdays.append(day.rawValue) }
                schedule.weekdays.sort()
              }))
        }
      }
      DatePicker(
        L10n.text("Начало приёма", locale: locale), selection: $schedule.startDate,
        displayedComponents: .date)
      Toggle(
        L10n.text("Указать окончание", locale: locale),
        isOn: Binding(
          get: { schedule.endDate != nil },
          set: { schedule.endDate = $0 ? max(schedule.startDate, .now) : nil }))
      if schedule.endDate != nil {
        DatePicker(
          L10n.text("Окончание приёма", locale: locale),
          selection: Binding(
            get: { schedule.endDate ?? schedule.startDate }, set: { schedule.endDate = $0 }),
          in: schedule.startDate..., displayedComponents: .date)
      }
      ForEach(schedule.times.indices, id: \.self) { index in
        HStack {
          DatePicker(
            L10n.text("Время приёма", locale: locale), selection: timeBinding(index),
            displayedComponents: .hourAndMinute)
          if schedule.times.count > 1 {
            Button(
              L10n.text("Удалить время", locale: locale), systemImage: "minus.circle",
              role: .destructive
            ) {
              schedule.times.remove(at: index)
            }.labelStyle(.iconOnly)
          }
        }
      }
      if schedule.times.count < 8 {
        Button(L10n.text("Добавить время", locale: locale), systemImage: "plus") {
          let next = (0..<1440).first { !schedule.times.contains($0) } ?? 0
          schedule.times.append(next)
        }
      }
      Text(schedule.timeZoneID).font(.caption).foregroundStyle(.secondary)
      Toggle(L10n.text("Напоминать о приёме", locale: locale), isOn: $schedule.remindersEnabled)
    } header: {
      Text(L10n.text("Периодичность и напоминания", locale: locale))
    } footer: {
      Text(
        L10n.text(
          "Время сохраняется в часовом поясе расписания. Напоминание не отмечает приём автоматически. Открывайте приложение регулярно, чтобы обновлять ближайшие напоминания.",
          locale: locale))
    }
    .environment(\.timeZone, TimeZone(identifier: schedule.timeZoneID) ?? .current)
  }
  private func timeBinding(_ index: Int) -> Binding<Date> {
    var referenceCalendar = Calendar(identifier: .gregorian)
    referenceCalendar.timeZone = TimeZone(identifier: schedule.timeZoneID) ?? .current
    let calendar = referenceCalendar
    return Binding(
      get: {
        guard schedule.times.indices.contains(index) else { return schedule.startDate }
        let minutes = schedule.times[index]
        return calendar.date(
          bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: schedule.startDate)
          ?? schedule.startDate
      },
      set: { date in
        guard schedule.times.indices.contains(index) else { return }
        schedule.times[index] =
          calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
      })
  }

  private func nutrientField(_ title: String, text: Binding<String>, id: String) -> some View {
    TextField(L10n.text(title, locale: locale), text: text).keyboardType(.decimalPad)
      .accessibilityIdentifier(id)
  }
  private func save() {
    guard workspaceID == diary.workspaceID else {
      dismiss()
      return
    }
    do {
      let entry = try model.validatedEntry()
      if isPlan {
        schedule.prototype = entry
        schedule.times.sort()
        let value = schedule
        try value.validate()
        saving = true
        saveTask?.cancel()
        saveTask = Task {
          defer { saving = false }
          if await diary.savePlan(value) { dismiss() } else { model.error = diary.error }
        }
      } else if diary.saveSupplement(entry) {
        dismiss()
      } else {
        model.error = diary.error
      }
    } catch { model.error = error.localizedDescription }
  }
}
