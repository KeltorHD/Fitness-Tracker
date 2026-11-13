import FitLifeCore
import SwiftUI
import UIKit

struct SupplementPlansSection: View {
  @Environment(\.locale) private var locale
  @Environment(\.openURL) private var openURL
  @State private var permissionTask: Task<Void, Never>?
  let model: NutritionDiaryModel
  let add: () -> Void
  let edit: (SupplementPlan) -> Void
  let take: (SupplementEntry) -> Void
  let delete: (SupplementPlan) -> Void

  var body: some View {
    Section {
      if let status = model.reminderStatus {
        Text(L10n.text(status, locale: locale)).font(.subheadline).cardListRow()
        Button(L10n.text("Разрешить уведомления", locale: locale)) {
          permissionTask?.cancel()
          permissionTask = Task { await model.authorizeReminders() }
        }.cardListRow()
        Button(L10n.text("Настройки уведомлений", locale: locale)) {
          if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        }.cardListRow()
        Button(L10n.text("Обновить напоминания", locale: locale)) { model.refreshReminders() }
          .cardListRow()
      }
      ForEach(model.plannedSupplements) { entry in
        let completed = model.supplements.contains { $0.id == entry.id }
        Button {
          take(entry)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.name.isEmpty ? L10n.text(entry.kind.title, locale: locale) : entry.name)
              Text((entry.scheduledFor ?? entry.date), format: .dateTime.hour().minute())
                .font(.caption).foregroundStyle(.secondary)
              Text(entry.amount.formatted() + " " + L10n.text(entry.unit.symbol, locale: locale))
            }
            Spacer()
            Label(
              L10n.text(completed ? "Приём отмечен" : "Отметить приём", locale: locale),
              systemImage: completed ? "checkmark.circle.fill" : "circle")
          }
        }.disabled(completed).cardListRow()
      }
      ForEach(model.plans.sorted { $0.id.uuidString < $1.id.uuidString }) { plan in
        Button {
          edit(plan)
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            Text(
              plan.prototype.name.isEmpty
                ? L10n.text(plan.prototype.kind.title, locale: locale) : plan.prototype.name
            )
            .font(.headline)
            Text(L10n.text(plan.recurrence.title, locale: locale))
            Text(
              plan.times.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(
                separator: ", ") + " · " + plan.timeZoneID
            )
            .font(.caption).foregroundStyle(.secondary)
            if !plan.enabled { Text(L10n.text("Расписание приостановлено", locale: locale)) }
            if plan.remindersEnabled {
              Label(L10n.text("Напоминания включены", locale: locale), systemImage: "bell")
            }
          }.foregroundStyle(.primary)
        }.buttonStyle(.plain).cardListRow()
          .contextMenu {
            Button(L10n.text("Изменить", locale: locale)) { edit(plan) }
            Button(L10n.text("Удалить", locale: locale), role: .destructive) { delete(plan) }
          }
          .swipeActions(allowsFullSwipe: false) {
            Button(L10n.text("Удалить", locale: locale), role: .destructive) { delete(plan) }
          }
      }
      Button(
        L10n.text("Добавить расписание приёма", locale: locale), systemImage: "calendar.badge.plus",
        action: add
      )
      .accessibilityIdentifier("addSupplementPlan").cardListRow()
    } header: {
      Text(L10n.text("Расписания добавок", locale: locale))
    }
  }
}
