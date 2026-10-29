import FitSessionCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @AppStorage("weeklyGoal") private var goal = 3
  @AppStorage("appearance") private var appearance = "auto"
  @AppStorage("keepScreenAwake") private var keepScreenAwake = false
  @AppStorage("cloudSync") private var cloud = false
  @AppStorage("widgetSharing") private var widgetSharing = false
  @AppStorage("liveActivities") private var liveActivities = true
  @AppStorage("restNotifications") private var notifications = false
  let model: SettingsViewModel
  @State private var cloudRequest = 0
  @State private var notificationsRequested = false
  var body: some View {
    NavigationStack {
      Form {
        Section("Тренировка") {
          Toggle(
            isOn: Binding(
              get: { notifications },
              set: { enabled in
                if enabled {
                  notificationsRequested = true
                } else {
                  notifications = false
                  store.refreshIntegrations()
                }
              })
          ) { SettingsLabel(title: "Уведомления", symbol: "bell") }
          .disabled(model.requestingNotifications)
          if model.requestingNotifications { ProgressView("Запрос разрешения…") }
          if let message = model.notificationMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
          }
          Toggle(isOn: $keepScreenAwake) {
            SettingsLabel(title: "Отключить автоблокировку", symbol: "lock.iphone")
          }
          Toggle(isOn: $liveActivities) { SettingsLabel(title: "Live Activities", symbol: "timer") }
          Stepper(value: $goal, in: 1...7) {
            SettingsLabel(title: "Цель на неделю: \(goal)", symbol: "calendar")
          }
        }
        Section("Основные") {
          Picker(selection: $appearance) {
            Text("Авто").tag("auto")
            Text("Светлая").tag("light")
            Text("Тёмная").tag("dark")
          } label: {
            SettingsLabel(title: "Тема", symbol: "circle.lefthalf.filled")
          }
          Picker(selection: $unit) {
            ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          } label: {
            SettingsLabel(title: "Единицы измерения", symbol: "scalemass")
          }
          NavigationLink {
            List {
              Text(
                "Откройте завершённую тренировку в дневнике и выберите «Экспорт в Здоровье». FitSession запросит разрешение на запись."
              )
              Text(
                "Передаются тип, длительность и интервалы пауз. Данные пульса и калорий не генерируются."
              )
            }.navigationTitle("Здоровье")
          } label: {
            SettingsLabel(title: "Здоровье", symbol: "heart.fill", color: .pink)
          }
        }
        Section {
          Toggle(isOn: $cloud) { SettingsLabel(title: "Синхронизация iCloud", symbol: "icloud") }
          Button {
            store.archiveTransfer.present()
          } label: {
            SettingsLabel(title: "Импорт и экспорт", symbol: "arrow.up.arrow.down")
          }.accessibilityIdentifier("openArchiveTransfer")
          Button {
            cloudRequest += 1
          } label: {
            SettingsLabel(title: "Проверить учётную запись", symbol: "person.crop.circle")
          }.disabled(model.cloudState == .loading)
          if model.cloudState == .loading { ProgressView("Проверка iCloud…") }
          if let message = model.cloudState.message {
            Text(message).font(.footnote).foregroundStyle(.secondary)
          }
          if model.cloudState == .failed { Button("Повторить") { cloudRequest += 1 } }
        } header: {
          Text("Данные")
        } footer: {
          Text(
            "Изменение синхронизации вступит в силу после перезапуска. История хранится на устройстве и, по вашему выбору, в личном iCloud."
          )
        }
        Section {
          Toggle(isOn: $widgetSharing) {
            SettingsLabel(title: "Сводка для виджета", symbol: "square.grid.2x2")
          }
        } footer: {
          Text(
            "Виджет получает только число тренировок и недельную цель. Эта сводка может быть видна на экране блокировки."
          )
        }
        Section {
          NavigationLink {
            ExerciseLibraryView()
          } label: {
            SettingsLabel(title: "Библиотека упражнений", symbol: "dumbbell")
          }
          NavigationLink {
            ExerciseCreditsView()
          } label: {
            SettingsLabel(title: "Источники и фотографии", symbol: "info.circle")
          }
          LabeledContent {
            Text(
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0")
          } label: {
            SettingsLabel(title: "Версия", symbol: "app")
          }
        } footer: {
          Text("Все функции FitSession доступны бесплатно.")
        }
      }
      .scrollContentBackground(.hidden).background(FitTheme.grouped).navigationTitle("Настройки")
      .tint(FitTheme.accent)
      .task(id: cloudRequest) {
        if cloudRequest > 0 { await model.checkCloudAccount() }
      }
      .task(id: notificationsRequested) {
        guard notificationsRequested else { return }
        if let allowed = await model.authorizeNotifications() {
          notifications = allowed
          store.refreshIntegrations()
        }
        notificationsRequested = false
      }
      .onChange(of: goal) { store.refreshIntegrations() }
      .onChange(of: widgetSharing) { store.refreshIntegrations() }
      .onChange(of: liveActivities) { store.refreshIntegrations() }
    }
  }
}

private struct SettingsLabel: View {
  let title: String
  let symbol: String
  var color: Color = .gray
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.white)
        .frame(width: 28, height: 28).background(color, in: .rect(cornerRadius: 7))
      Text(title).foregroundStyle(.primary)
    }
  }
}
