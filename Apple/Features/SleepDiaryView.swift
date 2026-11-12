import FitnessTrackerCore
import SwiftUI

private struct SleepLoadKey: Hashable {
  let day: Date
  let calendar: Calendar
  let active: Bool
  let enabled: Bool
}

struct SleepDiaryView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @Binding var date: Date
  let isSelected: Bool
  @Bindable var alarms: SleepAlarmStore
  @State private var model: SleepDiaryModel
  init(
    date: Binding<Date>, isSelected: Bool, alarms: SleepAlarmStore,
    reader: any HealthSleepReading = HealthSleepReader()
  ) {
    _date = date
    self.isSelected = isSelected
    self.alarms = alarms
    _model = State(initialValue: SleepDiaryModel(reader: reader))
  }
  var body: some View {
    List {
      SleepAlarmPanel(store: alarms).cardListRow()
      if !model.enabled {
        VStack(alignment: .leading, spacing: 14) {
          Label(
            L10n.text("Каждая ночь — часть восстановления", locale: locale),
            systemImage: "moon.stars.fill"
          ).font(.title2.bold()).foregroundStyle(.tint)
          Text(
            L10n.text(
              "Продолжительность и записанные фазы сна из «Здоровья», включая данные Apple Watch.",
              locale: locale)
          ).foregroundStyle(.secondary)
          Button(L10n.text("Подключить данные сна", locale: locale)) {
            Task { await model.enable() }
          }
          .buttonStyle(.glassProminent).disabled(model.loading).accessibilityIdentifier(
            "enableSleepDiary")
        }.fitCard().cardListRow()
      }
      if model.loading {
        ProgressView(L10n.text("Загружаем записи сна", locale: locale)).frame(maxWidth: .infinity)
          .cardListRow()
      }
      if let error = model.error {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
          Button(L10n.text("Повторить", locale: locale)) {
            Task { await model.load(day: date, calendar: calendar) }
          }
        }.cardListRow()
      }
      if model.enabled, !model.loading, !model.nights.isEmpty {
        SleepInsightsView(nights: model.nights, day: date)
      }
      if model.enabled {
        DisclosureGroup(L10n.text("Данные и доступ", locale: locale)) {
          Text(
            L10n.text(
              "Ночь учитывается с полудня предыдущего дня до полудня выбранного дня.",
              locale: locale)
          ).font(.footnote).foregroundStyle(.secondary)
          Button(L10n.text("Не показывать данные сна", locale: locale)) { model.disable() }.padding(
            .top, 8)
        }.font(.subheadline).cardListRow()
      }
    }
    .listStyle(.plain).scrollContentBackground(.hidden).background(FitTheme.paper)
    .accessibilityIdentifier("sleepDiary")
    .refreshable {
      alarms.refresh()
      await model.load(day: date, calendar: calendar)
    }
    .task(
      id: SleepLoadKey(
        day: date, calendar: calendar, active: isSelected && phase == .active,
        enabled: model.enabled)
    ) {
      guard isSelected, phase == .active else { return }
      alarms.refresh()
      await model.load(day: date, calendar: calendar)
    }
  }
}
