import FitnessTrackerCore
import SwiftUI
import UIKit

struct TrackerView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.openURL) private var openURL
  let model: TrackerViewModel
  @State private var day = Date()
  @State private var request = 0
  @State private var retrySave = 0

  var body: some View {
    Form {
      Section {
        Picker(
          L10n.text("Модель трекера", locale: locale),
          selection: Binding(
            get: { model.deviceProfile }, set: { model.selectDeviceProfile($0) })
        ) {
          ForEach(TrackerDeviceProfile.allCases) { profile in
            Text(L10n.text(profile.titleKey, locale: locale)).tag(profile)
          }
        }.pickerStyle(.menu).accessibilityIdentifier("trackerDevicePicker")
        Picker(
          L10n.text("Режим трекера", locale: locale),
          selection: Binding(
            get: { model.mode }, set: { model.selectMode($0) })
        ) {
          Text(L10n.text("Apple «Здоровье»", locale: locale)).tag(TrackerMode.appleHealth)
          Text(L10n.text("Bluetooth-пульс", locale: locale)).tag(TrackerMode.bluetooth)
        }.pickerStyle(.menu).accessibilityIdentifier("trackerModePicker")
      }
      if model.mode == .appleHealth {
        if model.deviceProfile == .airPodsPro3 {
          Section {
            Text(L10n.text(model.deviceProfile.healthSetupKey, locale: locale))
              .accessibilityIdentifier("trackerAirPodsSetup")
            Text(
              L10n.text(
                "Этот режим предназначен для AirPods Pro 3 с датчиком пульса. iOS выбирает доступный источник; вместе с AirPods может использоваться Apple Watch.",
                locale: locale)
            )
            .font(.footnote).foregroundStyle(.secondary)
            LiveWorkoutHeartRateControls(model: model)
            if let url = model.deviceProfile.supportURL {
              Link(L10n.text("Инструкция производителя", locale: locale), destination: url)
            }
          } header: {
            Text(L10n.text("Пульс во время тренировки", locale: locale))
          } footer: {
            Text(
              L10n.text(
                "Для приёма нужен доступ к пульсу и тренировкам в «Здоровье». Запись тренировки в «Здоровье» остаётся отдельным действием.",
                locale: locale))
          }
        }
        healthSections
      } else if model.deviceProfile == .airPodsPro3 {
        Section {
          Text(L10n.text(model.deviceProfile.bluetoothSetupKey, locale: locale))
          Button(L10n.text("Выбрать Apple «Здоровье»", locale: locale)) {
            model.selectMode(.appleHealth)
          }
        }
      } else {
        bluetoothSections
      }
      if let error = model.error {
        Section {
          Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
          if model.hasPendingSaves {
            Button(L10n.text("Повторить сохранение", locale: locale)) { retrySave += 1 }
          }
          if model.canRetryRecordingLoad {
            Button(L10n.text("Повторить загрузку записи пульса", locale: locale)) {
              model.retryRecordingLoad()
            }
          }
        }
      }
      Section {
        Text(
          L10n.text(
            "Копия пульса в FitnessTracker хранится на этом iPhone и не включается в iCloud, виджеты и файлы экспорта. Данные Apple «Здоровье» и их синхронизацию контролирует iOS.",
            locale: locale)
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle(L10n.text("Трекер", locale: locale))
    .tint(FitTheme.accent)
    .task(id: request) {
      if request > 0 { await model.readHealth(day: day, calendar: calendar) }
    }
    .task(id: retrySave) { if retrySave > 0 { await model.retrySaving() } }
    .onChange(of: day) { if model.hasRequestedHealth { request += 1 } }
    .onDisappear { model.leaveScreen() }
  }

  private var healthSections: some View {
    Group {
      Section {
        if model.deviceProfile != .airPodsPro3 {
          Text(L10n.text(model.deviceProfile.healthSetupKey, locale: locale))
            .accessibilityIdentifier("trackerHealthSetup")
        }
        DatePicker(
          L10n.text("День", locale: locale), selection: $day, in: ...Date(),
          displayedComponents: .date)
        Button(L10n.text("Прочитать показатели", locale: locale)) { request += 1 }
          .disabled(model.loadingHealth).accessibilityIdentifier("readTrackerHealth")
        if model.loadingHealth { ProgressView(L10n.text("Чтение показателей…", locale: locale)) }
      } footer: {
        Text(
          L10n.text(
            "Данные могут поступать с задержкой. Доступны только показатели, переданные в «Здоровье» и разрешённые для FitnessTracker.",
            locale: locale))
      }
      if let summary = model.summary {
        Section {
          LabeledContent(
            L10n.text("Шаги", locale: locale),
            value: summary.steps.map { $0.formatted(.number.locale(L10n.numberLocale)) } ?? "—")
          LabeledContent(
            L10n.text("Активная энергия, ккал", locale: locale),
            value: summary.activeEnergyKCal.map {
              $0.formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0)))
            } ?? "—")
          LabeledContent(
            L10n.text("Сон за ночь", locale: locale),
            value: summary.sleepSeconds.map { $0.formattedWorkoutDuration(locale: locale) } ?? "—")
          LabeledContent(
            L10n.text("Последний пульс", locale: locale),
            value: summary.latestHeartRate.map {
              $0.beatsPerMinute.formatted(.number.precision(.fractionLength(0))) + " "
                + L10n.text("уд/мин", locale: locale)
            } ?? "—")
          if let reading = summary.latestHeartRate {
            Text(reading.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(
              .secondary)
          }
          if let source = summary.heartRateSource {
            LabeledContent(L10n.text("Источник пульса", locale: locale), value: source)
          }
          if summary.isEmpty {
            Text(
              L10n.text(
                "Нет доступных данных. Проверьте синхронизацию приложения трекера и разрешения FitnessTracker в «Здоровье».",
                locale: locale))
          }
        } header: {
          Text(L10n.text("Сводка за день", locale: locale))
        } footer: {
          Text(
            L10n.text(
              "Сводка учитывает доступные источники Apple «Здоровье», а не только выбранный трекер. Сон — между полуднем предыдущего и выбранного дня.",
              locale: locale))
        }
      }
    }
  }

  private var bluetoothSections: some View {
    Group {
      Section {
        Text(L10n.text(model.deviceProfile.bluetoothSetupKey, locale: locale))
          .accessibilityIdentifier("trackerBluetoothSetup")
        if let note = model.deviceProfile.bluetoothNoteKey {
          Text(L10n.text(note, locale: locale)).font(.footnote).foregroundStyle(.secondary)
        }
        if let url = model.deviceProfile.supportURL {
          Link(L10n.text("Инструкция производителя", locale: locale), destination: url)
        }
        LiveHeartRateValue(snapshot: model.bluetooth)
        if let name = model.bluetooth.deviceName,
          model.bluetooth.connection == .connected || model.bluetooth.connection == .connecting
        {
          LabeledContent(L10n.text("Устройство Bluetooth", locale: locale), value: name)
        }
        Text(L10n.text(model.bluetooth.connection.message, locale: locale)).font(.subheadline)
          .foregroundStyle(.secondary)
        if model.bluetooth.connection == .connecting || model.bluetooth.connection == .connected {
          Button(L10n.text("Отключить пульсометр", locale: locale)) { model.disconnect() }
        } else {
          Button(L10n.text("Найти пульсометр", locale: locale)) { model.scan() }
            .disabled(model.bluetooth.connection == .scanning).accessibilityIdentifier(
              "scanHeartRate")
        }
        if model.bluetooth.connection == .scanning {
          ProgressView()
          Button(L10n.text("Остановить поиск", locale: locale)) { model.leaveScreen() }
        }
        ForEach(model.bluetooth.devices) { device in
          Button(device.name) { model.connect(device.id) }
            .disabled(
              ![HeartRateConnection.idle, .scanning, .disconnected, .failed].contains(
                model.bluetooth.connection))
        }
      } footer: {
        Text(
          L10n.text(
            "Запись идёт только во время активной тренировки, включая отдых между подходами. Пауза приостанавливает запись. Поддерживаются Bluetooth-пульсометры с передачей пульса.",
            locale: locale))
      }
      if model.bluetooth.connection == .unauthorized || model.bluetooth.connection == .poweredOff {
        Section {
          Button(L10n.text("Открыть настройки iOS", locale: locale)) {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        }
      }
    }
  }
}

extension HeartRateConnection {
  var message: String {
    switch self {
    case .idle: "Выберите пульсометр из списка или начните поиск."
    case .scanning: "Поиск пульсометров…"
    case .connecting: "Подключение к пульсометру…"
    case .connected: "Пульсометр подключён"
    case .disconnected: "Связь с пульсометром потеряна. Повторите подключение."
    case .poweredOff: "Включите Bluetooth на iPhone."
    case .unauthorized: "Разрешите FitnessTracker доступ к Bluetooth в настройках iOS."
    case .unsupported: "Bluetooth-пульсометр не поддерживается на этом устройстве."
    case .failed:
      "Не удалось подключить пульсометр. Проверьте трансляцию пульса на устройстве и повторите поиск."
    }
  }
}

struct LiveHeartRateValue: View {
  let snapshot: HeartRateBluetoothSnapshot
  var body: some View {
    FreshHeartRateValue(reading: snapshot.reading, isActive: snapshot.connection == .connected)
  }
}

struct FreshHeartRateValue: View {
  @Environment(\.locale) private var locale
  let reading: HeartRateReading?
  let isActive: Bool
  var body: some View {
    TimelineView(.periodic(from: .now, by: 5)) { timeline in
      HStack {
        Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityHidden(true)
        if isActive, let reading,
          reading.isFresh(at: timeline.date)
        {
          Text(reading.beatsPerMinute, format: .number.precision(.fractionLength(0)))
            .monospacedDigit()
          Text(L10n.text("уд/мин", locale: locale))
        } else {
          Text(L10n.text("Нет свежего измерения", locale: locale)).foregroundStyle(.secondary)
        }
      }.accessibilityElement(children: .combine)
    }
  }
}

struct WorkoutTrackerCard: View {
  @Environment(\.locale) private var locale
  let tracker: TrackerViewModel
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if tracker.mode == .bluetooth {
        LiveHeartRateValue(snapshot: tracker.bluetooth)
        Text(L10n.text(tracker.bluetooth.connection.message, locale: locale)).font(.caption)
          .foregroundStyle(.secondary)
        if tracker.preparingRecording { ProgressView() }
      } else if tracker.deviceProfile == .airPodsPro3 {
        LiveWorkoutHeartRateControls(model: tracker)
      } else {
        Text(
          L10n.text(
            "Пульс из «Здоровья» можно загрузить после завершения тренировки.", locale: locale)
        ).font(.caption)
      }
      NavigationLink(L10n.text("Трекер", locale: locale)) { TrackerView(model: tracker) }
      if let error = tracker.error {
        Text(L10n.text(error, locale: locale)).foregroundStyle(.red).font(.caption)
      }
    }
  }
}
