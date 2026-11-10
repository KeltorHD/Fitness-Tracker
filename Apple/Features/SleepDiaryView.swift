import Charts
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
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Binding var date: Date
  let isSelected: Bool
  @Bindable var alarms: SleepAlarmStore
  @State private var model = SleepDiaryModel(reader: HealthSleepReader())
  @State private var addingAlarm = false
  private var night: SleepNight? { model.nights.last }
  var body: some View {
    List {
      if !model.enabled {
        VStack(alignment: .leading, spacing: 12) {
          Label(L10n.text("Дневник сна", locale: locale), systemImage: "bed.double.fill").font(
            .title2.bold())
          Text(
            L10n.text(
              "Продолжительность и записанные фазы сна из «Здоровья», включая данные Apple Watch.",
              locale: locale))
          Button(L10n.text("Подключить данные сна", locale: locale)) {
            Task { await model.enable() }
          }
          .buttonStyle(.glassProminent).disabled(model.loading)
          .accessibilityIdentifier("enableSleepDiary")
        }.fitCard().cardListRow()
      } else {
        if model.loading { ProgressView().cardListRow() }
        if let error = model.error {
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
            Button(L10n.text("Повторить", locale: locale)) {
              Task { await model.load(day: date, calendar: calendar) }
            }
          }.cardListRow()
        }
        if let night, !model.loading {
          if let asleep = night.asleep {
            VStack(alignment: .leading, spacing: 12) {
              Text(L10n.text("Сон за ночь", locale: locale)).font(.headline)
              Text(duration(asleep)).font(.largeTitle.bold()).monospacedDigit()
              if let start = night.sleepStart, let end = night.sleepEnd {
                HStack(spacing: 4) {
                  Text(start, style: .time)
                  Text(verbatim: "—")
                  Text(end, style: .time)
                }
              }
              if let source = night.sourceName {
                Text(source).font(.caption).foregroundStyle(.secondary)
              }
              if let bed = night.inBed {
                LabeledContent(L10n.text("В постели", locale: locale), value: duration(bed))
              }
              Text(
                L10n.text(
                  "Ночь учитывается с полудня предыдущего дня до полудня выбранного дня.",
                  locale: locale)
              )
              .font(.caption).foregroundStyle(.secondary)
            }.fitCard().cardListRow().accessibilityIdentifier("sleepNightSummary")
            stages(night).fitCard().cardListRow()
          } else if let bed = night.inBed {
            VStack(alignment: .leading, spacing: 8) {
              Text(L10n.text("В постели", locale: locale)).font(.headline)
              Text(duration(bed)).font(.title.bold())
              Text(
                L10n.text(
                  "Источник передал только время в постели, без длительности и фаз сна.",
                  locale: locale)
              ).foregroundStyle(.secondary)
            }.fitCard().cardListRow()
          } else {
            ContentUnavailableView {
              Label(
                L10n.text("Нет записей сна за эту ночь", locale: locale), systemImage: "moon.zzz")
            } description: {
              Text(
                L10n.text(
                  "Данные могут ещё не синхронизироваться с часов. Проверьте записи и доступ в приложении «Здоровье».",
                  locale: locale))
            }.cardListRow()
          }
          week.fitCard().cardListRow()
        }
      }
      alarmsSection
      if let notice = alarms.notice {
        Text(L10n.text(notice, locale: locale)).font(.footnote).cardListRow()
      }
      if let error = alarms.error {
        Text(L10n.text(error, locale: locale)).foregroundStyle(.red).cardListRow()
      }
      if let wake = alarms.lastWatchAlert {
        LabeledContent(L10n.text("Последний сигнал с Watch", locale: locale)) {
          Text(wake, style: .time)
        }.cardListRow()
      }
      if model.enabled {
        Button(L10n.text("Не показывать данные сна", locale: locale)) { model.disable() }
          .cardListRow()
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
    .sheet(isPresented: $addingAlarm) {
      SleepAlarmEditor(store: alarms)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
  }

  private func stages(_ night: SleepNight) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("Записанные фазы сна", locale: locale)).font(.headline)
      Chart(night.periods) { period in
        BarMark(
          xStart: .value("Начало", period.interval.start),
          xEnd: .value("Конец", period.interval.end),
          y: .value("Фаза", L10n.text(period.stage.sleepTitle, locale: locale))
        )
        .foregroundStyle(period.stage.sleepColor)
      }.frame(height: 170)
        .chartYAxis(.hidden)
        .accessibilityLabel(L10n.text("Фазы сна за ночь", locale: locale))
      if night.hasStages {
        ForEach([SleepStage.core, .deep, .rem], id: \.self) { stage in
          LabeledContent {
            Text(duration(night.duration(stage))).monospacedDigit()
          } label: {
            Label(L10n.text(stage.sleepTitle, locale: locale), systemImage: "circle.fill")
              .foregroundStyle(stage.sleepColor)
          }
        }
        LabeledContent(
          L10n.text("Периоды бодрствования", locale: locale), value: String(night.awakePeriods))
      } else {
        Text(L10n.text("Источник не передал подробные фазы сна.", locale: locale)).foregroundStyle(
          .secondary)
      }
      if night.duration(.unspecified) > 0 {
        LabeledContent(
          L10n.text("Сон без уточнения фазы", locale: locale),
          value: duration(night.duration(.unspecified)))
      }
    }
  }
  private var week: some View {
    let recorded = model.nights.filter { $0.asleep != nil }
    return VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("Последние 7 ночей", locale: locale)).font(.headline)
      if !recorded.isEmpty {
        Chart(recorded) { item in
          BarMark(
            x: .value("Дата", item.day, unit: .day), y: .value("Часы", (item.asleep ?? 0) / 3600)
          )
          .foregroundStyle(colorTheme.accent)
        }.frame(height: 150)
        LabeledContent(
          L10n.text("Среднее по ночам с данными", locale: locale),
          value: duration(recorded.compactMap(\.asleep).reduce(0, +) / Double(recorded.count)))
      } else {
        Text(L10n.text("Недостаточно данных для анализа недели.", locale: locale)).foregroundStyle(
          .secondary)
      }
    }
  }
  private var alarmsSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text(L10n.text("Умные будильники", locale: locale)).font(.title2.bold())
        Text(
          L10n.text(
            "Часы оценивают движения в выбранном окне. Это не точное определение фазы сна. В конце окна сработает системный резервный будильник.",
            locale: locale)
        )
        .font(.subheadline).foregroundStyle(.secondary)
        Text(
          L10n.text(
            "Перед сном откройте FitnessTracker на Watch и подтвердите умное окно. Без подтверждения работает обычный будильник.",
            locale: locale)
        )
        .font(.caption).foregroundStyle(.secondary)
        Button(L10n.text("Добавить будильник", locale: locale), systemImage: "alarm.fill") {
          addingAlarm = true
        }
        .buttonStyle(.glassProminent).disabled(alarms.busy || alarms.plans.count >= 10)
        .accessibilityIdentifier("addSleepAlarm")
      }.fitCard().cardListRow()
      ForEach(alarms.plans) { plan in
        VStack(alignment: .leading, spacing: 8) {
          Text(plan.fireDate, format: .dateTime.day().month().hour().minute()).font(.title3.bold())
          if plan.windowMinutes > 0 {
            HStack(spacing: 4) {
              Text(plan.windowStart, style: .time)
              Text(verbatim: "—")
              Text(plan.fireDate, style: .time)
            }
            Label(
              L10n.text(
                alarms.watchArmed.contains(plan.id)
                  ? "Умное окно подготовлено на Watch"
                  : (alarms.watchFailed.contains(plan.id)
                    ? "Умное окно на Watch недоступно" : "Ожидает подтверждения на Watch"),
                locale: locale),
              systemImage: alarms.watchArmed.contains(plan.id) ? "checkmark.circle" : "applewatch"
            )
            .font(.caption)
          }
          Label(
            L10n.text(
              alarms.systemConfirmed.contains(plan.id)
                ? "Системный резерв установлен" : "Системный резерв требует проверки",
              locale: locale),
            systemImage: "checkmark.shield"
          ).font(.caption)
        }.fitCard().cardListRow()
          .swipeActions(allowsFullSwipe: false) {
            Button(L10n.text("Удалить", locale: locale), role: .destructive) { alarms.remove(plan) }
          }
      }
    }
  }
  private func duration(_ value: TimeInterval) -> String {
    Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }
}

private struct SleepAlarmEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @Bindable var store: SleepAlarmStore
  @State private var fireDate = Date().addingTimeInterval(8 * 3600)
  @State private var window = 20
  var body: some View {
    NavigationStack {
      Form {
        DatePicker(
          L10n.text("Разбудить не позднее", locale: locale), selection: $fireDate, in: Date()...,
          displayedComponents: [.date, .hourAndMinute])
        Picker(L10n.text("Окно до будильника", locale: locale), selection: $window) {
          ForEach([0, 5, 10, 15, 20, 30], id: \.self) { value in
            if value == 0 {
              Text(L10n.text("Без умного окна", locale: locale)).tag(value)
            } else {
              Text(L10n.format("%@ мин", String(value), locale: locale)).tag(value)
            }
          }
        }.accessibilityIdentifier("sleepAlarmWindow")
        Text(
          L10n.text(
            "Будильник на выбранную дату. Умное окно может разбудить раньше, но не позже указанного времени.",
            locale: locale)
        )
        .font(.caption).foregroundStyle(.secondary)
        if let error = store.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
        Button(L10n.text("Установить будильник", locale: locale)) {
          Task { if await store.add(fireDate: fireDate, windowMinutes: window) { dismiss() } }
        }.disabled(store.busy).accessibilityIdentifier("saveSleepAlarm")
      }
      .navigationTitle(L10n.text("Новый будильник", locale: locale)).navigationBarTitleDisplayMode(
        .inline)
    }.interactiveDismissDisabled(store.busy)
  }
}

extension SleepStage {
  fileprivate var sleepTitle: String {
    switch self {
    case .inBed: "В постели"
    case .awake: "Бодрствование"
    case .core: "Базовый сон"
    case .deep: "Глубокий сон"
    case .rem: "Быстрый сон (REM)"
    case .unspecified: "Сон без уточнения фазы"
    }
  }
  fileprivate var sleepColor: Color {
    switch self {
    case .inBed: .gray
    case .awake: .orange
    case .core: .blue
    case .deep: .indigo
    case .rem: .purple
    case .unspecified: .secondary
    }
  }
}
