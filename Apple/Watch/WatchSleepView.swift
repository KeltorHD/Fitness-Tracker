import FitnessTrackerCore
import SwiftUI
import WatchKit

struct WatchSleepView: View {
  @Environment(WatchStore.self) private var store
  @Environment(\.locale) private var locale
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.text("Пробуждение", locale: locale)).font(.title2.bold())
        if let error = store.sleepAlarm.error { Text(error).font(.footnote).foregroundStyle(.red) }
        if store.sleepAlarm.ringing {
          Button(L10n.text("Выключить", locale: locale)) { store.sleepAlarm.stop() }.buttonStyle(
            .glassProminent)
        } else {
          if let plan = store.sleepAlarm.plans.filter({ $0.canArmWatch(at: .now) }).min(by: {
            $0.fireDate < $1.fireDate
          }) {
            Text(plan.fireDate, format: .dateTime.day().month().hour().minute()).font(.headline)
            HStack(spacing: 4) {
              Text(plan.windowStart, style: .time)
              Text(verbatim: "—")
              Text(plan.fireDate, style: .time)
            }
            if store.sleepAlarm.armedPlan == plan {
              Text(L10n.text("Окно запрошено на Watch", locale: locale)).font(.caption)
            }
            Button(L10n.text("Подготовить умное окно", locale: locale)) { store.sleepAlarm.arm() }
              .buttonStyle(.glassProminent)
          } else {
            Text(L10n.text("Создайте будильник в дневнике сна на iPhone.", locale: locale))
          }
          Text(
            L10n.text(
              "Оцениваем движения, а не фазу сна. Если подходящий момент не найден, будим в конце окна.",
              locale: locale)
          )
          .font(.footnote).foregroundStyle(.secondary)
          Text(
            L10n.text(
              "После изменения или удаления будильника на iPhone откройте приложение на часах для синхронизации.",
              locale: locale)
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      }.padding()
    }
  }
}

@MainActor final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
  let store = WatchStore()
  func applicationDidBecomeActive() { store.sleepAlarm.becameActive() }
  func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
    store.sleepAlarm.resume(extendedRuntimeSession)
  }
}
