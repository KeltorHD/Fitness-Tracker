import FitnessTrackerCore
import SwiftUI

private struct SleepAlarmEditorTarget: Identifiable {
  let id = UUID()
  let plan: SleepAlarmPlan?
}

struct SleepAlarmPanel: View {
  @Environment(\.locale) private var locale
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Bindable var store: SleepAlarmStore
  @State private var expanded = false
  @State private var editor: SleepAlarmEditorTarget?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "alarm.fill").font(.title3).foregroundStyle(theme.accent)
        Button {
          withAnimation(reduceMotion ? nil : .snappy) { expanded.toggle() }
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              if let next = store.activePlans.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text(next.fireDate, format: .dateTime.hour().minute()).font(.title3.bold())
                    .monospacedDigit()
                  Text(next.fireDate, format: .dateTime.day().month(.abbreviated)).font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(L10n.text(status(next), locale: locale)).font(.caption).foregroundStyle(
                  .secondary)
              } else {
                Text(L10n.text("Будильники", locale: locale)).font(.headline)
                Text(L10n.text("Настроить пробуждение", locale: locale)).font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 0)
            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.bold())
              .foregroundStyle(.secondary)
          }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("expandSleepAlarms")
          .accessibilityValue(L10n.text(expanded ? "Развёрнуто" : "Свёрнуто", locale: locale))
        Button(L10n.text("Добавить будильник", locale: locale), systemImage: "plus") {
          editor = SleepAlarmEditorTarget(plan: nil)
        }.labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.regular)
          .disabled(store.busy || store.plans.count >= 10).accessibilityIdentifier("addSleepAlarm")
      }
      if !expanded, store.activePlans.count > 1 {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(store.activePlans) { plan in
              Button {
                editor = SleepAlarmEditorTarget(plan: plan)
              } label: {
                HStack(spacing: 5) {
                  Image(
                    systemName: plan.delivery == .watchOnly
                      ? "applewatch" : (plan.delivery == .phoneOnly ? "iphone" : "alarm"))
                  Text(plan.fireDate, format: .dateTime.hour().minute()).monospacedDigit()
                }.font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 8)
              }.buttonStyle(.glass)
            }
          }
        }.scrollIndicators(.hidden).accessibilityIdentifier("sleepAlarmThumbnails")
      }
      if expanded {
        ForEach(store.plans) { plan in
          Divider()
          HStack(alignment: .center, spacing: 12) {
            Button {
              editor = SleepAlarmEditorTarget(plan: plan)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(plan.fireDate, format: .dateTime.hour().minute()).font(.title2.bold())
                  .monospacedDigit()
                Text(plan.fireDate, format: .dateTime.weekday().day().month()).font(.caption)
                  .foregroundStyle(.secondary)
                Text(L10n.text(status(plan), locale: locale)).font(.caption).foregroundStyle(
                  store.watchFailed.contains(plan.id) ? .red : .secondary)
                if plan.windowMinutes > 0 {
                  Text(L10n.format("Окно: %@ мин", String(plan.windowMinutes), locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                }
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("editSleepAlarm_\(plan.id)")
            Toggle(
              L10n.text("Включён", locale: locale),
              isOn: Binding(
                get: { plan.isEnabled },
                set: { value in Task { _ = await store.setEnabled(value, for: plan) } }
              )
            ).labelsHidden().tint(theme.accent).disabled(store.busy)
              .accessibilityLabel(L10n.text("Включить будильник", locale: locale))
              .accessibilityIdentifier("enableSleepAlarm_\(plan.id)")
            Menu {
              Button(L10n.text("Изменить", locale: locale), systemImage: "pencil") {
                editor = SleepAlarmEditorTarget(plan: plan)
              }
              Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive)
              { store.remove(plan) }
            } label: {
              Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(store.busy).accessibilityLabel(
              L10n.text("Действия с будильником", locale: locale))
          }
        }
        if store.plans.isEmpty {
          Text(L10n.text("Будильников пока нет", locale: locale)).font(.subheadline)
            .foregroundStyle(.secondary)
        }
        DisclosureGroup(L10n.text("Как работает умное окно", locale: locale)) {
          Text(
            L10n.text(
              "Часы оценивают движения в выбранном окне. Перед сном откройте FitnessTracker на Watch и подтвердите подготовку. Это оценка движения, а не измерение текущей фазы сна.",
              locale: locale)
          ).font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
        }.font(.subheadline)
      }
      if let error = store.error {
        Text(L10n.text(error, locale: locale)).font(.footnote).foregroundStyle(.red)
      }
      if let notice = store.notice {
        Text(L10n.text(notice, locale: locale)).font(.footnote).foregroundStyle(.secondary)
      }
    }.fitCard().accessibilityElement(children: .contain).accessibilityIdentifier("sleepAlarmPanel")
      .sheet(item: $editor) { target in
        SleepAlarmEditor(store: store, plan: target.plan).presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
  }
  private func status(_ plan: SleepAlarmPlan) -> String {
    if !plan.isEnabled { return "Выключен" }
    if plan.delivery == .phoneOnly { return "На iPhone" }
    if plan.delivery == .watchOnly {
      if store.phoneSilenced.contains(plan.id) {
        return store.watchFailed.contains(plan.id)
          ? "Watch: нужна повторная подготовка" : "Только Apple Watch"
      }
      return "iPhone включён до подтверждения Watch"
    }
    if !store.systemConfirmed.contains(plan.id) { return "Системный резерв требует проверки" }
    return store.watchArmed.contains(plan.id)
      ? "На всех устройствах" : "iPhone готов · Watch ожидает подготовки"
  }
}

private struct SleepAlarmEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @Bindable var store: SleepAlarmStore
  let plan: SleepAlarmPlan?
  @State private var fireDate: Date
  @State private var window: Int
  @State private var delivery: SleepAlarmDelivery
  init(store: SleepAlarmStore, plan: SleepAlarmPlan?) {
    self.store = store
    self.plan = plan
    _fireDate = State(
      initialValue: max(
        plan?.fireDate ?? Date().addingTimeInterval(8 * 3600), Date().addingTimeInterval(60)))
    _window = State(initialValue: plan?.windowMinutes ?? 20)
    _delivery = State(initialValue: plan?.delivery ?? .phoneAndWatch)
  }
  private var deliveryMenu: some View {
    Menu {
      ForEach([SleepAlarmDelivery.phoneOnly, .watchOnly, .phoneAndWatch], id: \.self) { option in
        Button {
          delivery = option
        } label: {
          Label(
            L10n.text(option.menuTitle, locale: locale),
            systemImage: delivery == option ? "checkmark" : option.menuSymbol)
        }
        .disabled(option == .watchOnly && !store.watchReachable && plan?.delivery != .watchOnly)
      }
    } label: {
      HStack(spacing: 6) {
        Text(L10n.text("Где будить", locale: locale)).foregroundStyle(.primary)
        Spacer()
        Text(L10n.text(delivery.menuTitle, locale: locale))
        Image(systemName: "chevron.up.chevron.down").font(.caption.bold())
      }.contentShape(.rect)
    }
    .disabled(store.busy)
    .accessibilityLabel(L10n.text("Где будить", locale: locale))
    .accessibilityValue(L10n.text(delivery.menuTitle, locale: locale))
    .accessibilityIdentifier("sleepAlarmDelivery")
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker(
            L10n.text("Разбудить не позднее", locale: locale), selection: $fireDate, in: Date()...,
            displayedComponents: [.date, .hourAndMinute])
          if delivery.includesWatch {
            Picker(L10n.text("Окно до будильника", locale: locale), selection: $window) {
              ForEach([0, 5, 10, 15, 20, 30], id: \.self) { value in
                Text(
                  value == 0
                    ? L10n.text("Без умного окна", locale: locale)
                    : L10n.format("%@ мин", String(value), locale: locale)
                ).tag(value)
              }
            }.accessibilityIdentifier("sleepAlarmWindow")
          }
        } footer: {
          Text(
            L10n.text(
              delivery == .phoneOnly
                ? "Будильник на выбранную дату с сигналом в указанное время."
                : "Будильник на выбранную дату. Часы могут разбудить в пределах окна до этого времени.",
              locale: locale))
        }
        Section {
          deliveryMenu
          if delivery.includesWatch {
            Label(
              L10n.text(store.watchConnection.message, locale: locale),
              systemImage: store.watchReachable
                ? "applewatch.radiowaves.left.and.right" : "applewatch"
            ).font(.subheadline).foregroundStyle(.secondary)
              .accessibilityIdentifier("sleepWatchConnection")
          }
        } footer: {
          Text(
            L10n.text(
              delivery == .phoneOnly
                ? "Сигнал срабатывает на iPhone в указанное время. Умное окно отключено. iOS может автоматически дублировать системный будильник на парных Apple Watch."
                : delivery == .watchOnly
                  ? "После подтверждения подготовки на Watch сигнал iPhone будет выключен. При разрядке или сбое часов телефон не подстрахует. До подтверждения резерв остаётся включён."
                  : "Часы могут разбудить раньше. Системный сигнал iPhone остаётся резервом до нажатия «Выключить» на Watch.",
              locale: locale))
        }
        if let error = store.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
        Button(
          L10n.text(plan == nil ? "Установить будильник" : "Сохранить изменения", locale: locale)
        ) {
          Task {
            let saved: Bool
            if let plan {
              saved = await store.update(
                plan, fireDate: fireDate, windowMinutes: window, delivery: delivery)
            } else {
              saved = await store.add(fireDate: fireDate, windowMinutes: window, delivery: delivery)
            }
            if saved { dismiss() }
          }
        }.disabled(store.busy).accessibilityIdentifier("saveSleepAlarm")
      }.navigationTitle(
        L10n.text(plan == nil ? "Новый будильник" : "Изменить будильник", locale: locale)
      ).navigationBarTitleDisplayMode(.inline)
    }.interactiveDismissDisabled(store.busy)
      .onChange(of: delivery) { old, new in
        if new == .phoneOnly {
          window = 0
        } else if old == .phoneOnly {
          window = plan?.windowMinutes ?? 20
        }
      }
  }
}

extension SleepAlarmDelivery {
  fileprivate var menuTitle: String {
    switch self {
    case .phoneOnly: "На iPhone"
    case .watchOnly: "На Apple Watch"
    case .phoneAndWatch: "На всех устройствах"
    }
  }
  fileprivate var menuSymbol: String {
    switch self {
    case .phoneOnly: "iphone"
    case .watchOnly: "applewatch"
    case .phoneAndWatch: "alarm"
    }
  }
}
