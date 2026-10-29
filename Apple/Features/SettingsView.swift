import FitSessionCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @AppStorage("weeklyGoal") private var goal = 3
  @AppStorage("cloudSync") private var cloud = false
  @AppStorage("widgetSharing") private var widgetSharing = false
  @AppStorage("liveActivities") private var liveActivities = true
  @AppStorage("restNotifications") private var notifications = false
  @State private var cloudStatus = ""
  @State private var showPro = false
  var body: some View {
    NavigationStack {
      Form {
        Section("Тренировки") {
          Picker("Единицы веса", selection: $unit) {
            ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          Stepper("Цель: \(goal) тренировок в неделю", value: $goal, in: 1...7)
          Toggle(
            "Уведомление об окончании отдыха",
            isOn: Binding(
              get: { notifications },
              set: { enabled in
                if enabled {
                  Task {
                    notifications = await store.enableNotifications()
                    store.refreshIntegrations()
                  }
                } else {
                  notifications = false
                  store.refreshIntegrations()
                }
              }))
          Toggle("Live Activities", isOn: $liveActivities)
        }
        Section {
          Toggle("Синхронизация iCloud", isOn: $cloud)
          Button("Проверить учётную запись") {
            Task {
              do { cloudStatus = try await CloudKitService.accountDescription() } catch {
                cloudStatus = error.localizedDescription
              }
            }
          }
          if !cloudStatus.isEmpty { Text(cloudStatus).font(.footnote) }
        } header: {
          Text("iCloud")
        } footer: {
          Text(
            "Изменение вступит в силу после перезапуска приложения. Требуются настроенный CloudKit container и вход в iCloud. Одновременные изменения одной тренировки объединяются по принципу последней записи. Статус учётной записи не подтверждает завершение синхронизации."
          )
        }
        Section {
          Toggle("Передавать сводку виджету", isOn: $widgetSharing)
        } header: {
          Text("Конфиденциальность")
        } footer: {
          Text(
            "Виджет получает только количество тренировок за неделю и цель. Он может быть виден на экране блокировки. История хранится на устройстве и, по вашему выбору, в личном iCloud. Данные не отправляются в аналитику или рекламу."
          )
        }
        Section("FitSession") {
          NavigationLink("Библиотека упражнений") { ExerciseLibraryView() }
          NavigationLink("Источники упражнений и фотографий") { ExerciseCreditsView() }
          Button(store.purchases.isPro ? "FitSession Pro активен" : "FitSession Pro") {
            showPro = true
          }
          Text("SwiftUI · iOS 26 · Native Liquid Glass").font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Настройки").sheet(isPresented: $showPro) { ProView() }
      .onChange(of: goal) { store.refreshIntegrations() }
      .onChange(of: widgetSharing) { store.refreshIntegrations() }
      .onChange(of: liveActivities) { store.refreshIntegrations() }
    }
  }
}
