import FitSessionCore
import SwiftUI

struct SettingsView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @AppStorage("weeklyGoal") private var goal = 3
  @AppStorage("appearance") private var appearance = "auto"
  @AppStorage("appLanguage") private var language: AppLanguage = .system
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
        Section(L10n.text("Тренировка", locale: locale)) {
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
          ) { SettingsLabel(title: L10n.text("Уведомления", locale: locale), symbol: "bell") }
          .disabled(model.requestingNotifications)
          if model.requestingNotifications {
            ProgressView(L10n.text("Запрос разрешения…", locale: locale))
          }
          if let message = model.notificationMessage {
            Text(L10n.text(message, locale: locale)).font(.footnote).foregroundStyle(.secondary)
          }
          Toggle(isOn: $keepScreenAwake) {
            SettingsLabel(
              title: L10n.text("Отключить автоблокировку", locale: locale), symbol: "lock.iphone")
          }
          Toggle(isOn: $liveActivities) { SettingsLabel(title: "Live Activities", symbol: "timer") }
          Stepper(value: $goal, in: 1...7) {
            SettingsLabel(
              title: L10n.format("Цель на неделю: %@", String(goal), locale: locale),
              symbol: "calendar")
          }
        }
        Section(L10n.text("Основные", locale: locale)) {
          NavigationLink {
            TrackerView(model: store.tracker)
          } label: {
            SettingsLabel(title: L10n.text("Трекер", locale: locale), symbol: "heart.circle")
          }.accessibilityIdentifier("openTracker")
          Picker(L10n.text("Язык приложения", locale: locale), selection: $language) {
            Text(L10n.text("Как на устройстве", locale: locale)).tag(AppLanguage.system)
            Text("Русский").tag(AppLanguage.russian)
            Text("English").tag(AppLanguage.english)
          }.pickerStyle(.menu).accessibilityIdentifier("appLanguagePicker")
          Text(L10n.text("Системные диалоги используют язык iOS.", locale: locale))
            .font(.footnote).foregroundStyle(.secondary)
          Picker(selection: $appearance) {
            Text(L10n.text("Авто", locale: locale)).tag("auto")
            Text(L10n.text("Светлая", locale: locale)).tag("light")
            Text(L10n.text("Тёмная", locale: locale)).tag("dark")
          } label: {
            SettingsLabel(
              title: L10n.text("Тема", locale: locale), symbol: "circle.lefthalf.filled")
          }
          Picker(selection: $unit) {
            ForEach(WeightUnit.allCases, id: \.self) {
              Text(L10n.text($0.rawValue, locale: locale)).tag($0)
            }
          } label: {
            SettingsLabel(
              title: L10n.text("Единицы измерения", locale: locale), symbol: "scalemass")
          }
          NavigationLink {
            List {
              Text(
                L10n.text(
                  "Откройте завершённую тренировку в дневнике и выберите «Экспорт в Здоровье». FitSession запросит разрешение на запись.",
                  locale: locale)
              )
              Text(
                L10n.text(
                  "Передаются тип, длительность и интервалы пауз. Данные пульса и калорий не генерируются.",
                  locale: locale)
              )
            }.navigationTitle(L10n.text("Здоровье", locale: locale))
          } label: {
            SettingsLabel(
              title: L10n.text("Здоровье", locale: locale), symbol: "heart.fill", color: .pink)
          }
        }
        Section {
          if AppCapabilities.current.supportsCloudSync {
            Toggle(isOn: $cloud) {
              SettingsLabel(
                title: L10n.text("Синхронизация iCloud", locale: locale), symbol: "icloud")
            }
          }
          Button {
            store.archiveTransfer.present()
          } label: {
            SettingsLabel(
              title: L10n.text("Импорт и экспорт", locale: locale), symbol: "arrow.up.arrow.down")
          }.accessibilityIdentifier("openArchiveTransfer")
          if AppCapabilities.current.supportsCloudSync {
            Button {
              cloudRequest += 1
            } label: {
              SettingsLabel(
                title: L10n.text("Проверить учётную запись", locale: locale),
                symbol: "person.crop.circle")
            }.disabled(model.cloudState == .loading)
            if model.cloudState == .loading {
              ProgressView(L10n.text("Проверка iCloud…", locale: locale))
            }
            if let message = model.cloudState.message {
              Text(L10n.text(message, locale: locale)).font(.footnote).foregroundStyle(.secondary)
            }
            if model.cloudState == .failed {
              Button(L10n.text("Повторить", locale: locale)) { cloudRequest += 1 }
            }
          }
        } header: {
          Text(L10n.text("Данные", locale: locale))
        } footer: {
          if AppCapabilities.current.supportsCloudSync {
            Text(
              L10n.text(
                "Изменение синхронизации вступит в силу после перезапуска. История хранится на устройстве и, по вашему выбору, в личном iCloud.",
                locale: locale)
            )
          } else {
            Text(
              L10n.text(
                "История хранится на этом устройстве. Для переноса используйте импорт и экспорт файлов.",
                locale: locale)
            )
          }
        }
        Section {
          Toggle(isOn: $widgetSharing) {
            SettingsLabel(
              title: L10n.text("Сводка для виджета", locale: locale), symbol: "square.grid.2x2")
          }
        } footer: {
          Text(
            L10n.text(
              "Виджет получает только число тренировок и недельную цель. Эта сводка может быть видна на экране блокировки.",
              locale: locale)
          )
        }
        Section {
          NavigationLink {
            ExerciseLibraryView()
          } label: {
            SettingsLabel(
              title: L10n.text("Библиотека упражнений", locale: locale), symbol: "dumbbell")
          }
          NavigationLink {
            ExerciseCreditsView()
          } label: {
            SettingsLabel(
              title: L10n.text("Источники и фотографии", locale: locale), symbol: "info.circle")
          }
          LabeledContent {
            Text(
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "1.0")
          } label: {
            SettingsLabel(title: L10n.text("Версия", locale: locale), symbol: "app")
          }
        } footer: {
          Text(L10n.text("Все функции FitSession доступны бесплатно.", locale: locale))
        }
      }
      .scrollContentBackground(.hidden).background(FitTheme.grouped).navigationTitle(
        L10n.text("Настройки", locale: locale)
      )
      .tint(FitTheme.accent)
      .task(id: cloudRequest) {
        if cloudRequest > 0 && AppCapabilities.current.supportsCloudSync {
          await model.checkCloudAccount()
        }
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
