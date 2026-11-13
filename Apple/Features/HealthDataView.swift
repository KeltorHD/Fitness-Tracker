import AuthenticationServices
import FitLifeCore
import SwiftUI

private enum HealthDataAction: Hashable {
  case read, connect, disconnect
  case shareApple(Bool)
}

struct HealthDataView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @Environment(\.webAuthenticationSession) private var authentication
  @AppStorage("weightUnit") private var weightUnit = WeightUnit.kilograms
  @State private var model: HealthDataViewModel
  @State private var action: HealthDataAction?
  @State private var disconnecting = false
  @State private var readRevision = 0

  init(sources: HealthDataSources) {
    _model = State(initialValue: HealthDataViewModel(sources: sources))
  }

  var body: some View {
    @Bindable var model = self.model
    Form {
      Section {
        ForEach(
          HealthMetric.allCases.filter { model.sources.supportedMetrics.contains($0) }, id: \.self
        ) { metric in
          Picker(
            L10n.text(metric.titleKey, locale: locale),
            selection: Binding<HealthProviderID?>(
              get: { model.sources.provider(for: metric) },
              set: { if let provider = $0 { model.select(provider, for: metric) } })
          ) {
            ForEach(model.sources.providers(for: metric), id: \.self) { provider in
              Text(L10n.text(provider.titleKey, locale: locale)).tag(Optional(provider))
            }
          }
          .disabled(model.loading || model.connecting)
          .accessibilityIdentifier("healthProviderPicker." + metric.rawValue)
        }
      } header: {
        Text(L10n.text("Основной источник для каждого показателя", locale: locale))
      } footer: {
        Text(
          L10n.text(
            "Apple «Здоровье» и Mi Fitness могут использоваться одновременно. Каждый показатель берётся только из выбранного источника. При ошибке или отсутствии данных другой источник не подставляется.",
            locale: locale))
      }
      if let sync = model.sources.appleSync {
        Section {
          Toggle(
            L10n.text("Синхронизировать Apple Health с аккаунтом", locale: locale),
            isOn: Binding(get: { sync.enabled }, set: { action = .shareApple($0) })
          )
          .disabled(!sync.available || sync.authorizing)
          .accessibilityIdentifier("enableAppleHealthServerSync")
          if sync.enabled {
            Text(
              L10n.text(
                "На этом iPhone показываются локальные данные «Здоровья». Другие устройства видят сохранённую историю аккаунта.",
                locale: locale)
            ).font(.footnote).foregroundStyle(.secondary)
          }
          if sync.syncing || sync.authorizing {
            ProgressView(L10n.text("Синхронизация…", locale: locale))
          }
          if let date = sync.lastSync {
            LabeledContent(L10n.text("Последняя синхронизация", locale: locale)) {
              Text(date, format: .dateTime.day().month().hour().minute())
            }
          }
          if let message = sync.error {
            Text(L10n.text(message, locale: locale)).foregroundStyle(.red)
          }
          if sync.enabled {
            Button(L10n.text("Синхронизировать сейчас", locale: locale)) {
              sync.requestSync()
            }
          }
          if !sync.available {
            Text(L10n.text("Откройте журнал аккаунта для синхронизации здоровья.", locale: locale))
              .foregroundStyle(.secondary)
          }
        } footer: {
          Text(
            L10n.text(
              "Сон, шаги, вес, доля жира, пульс, кислород, активная энергия и расстояние будут передаваться с этого iPhone на ваш сервер и доступны другим устройствам аккаунта. Первое чтение — за последние 30 дней, затем передаются изменения. Отключение останавливает передачу и сохраняет историю на сервере.",
              locale: locale))
        }
      }
      Group {
        Section {
          if model.connection?.connected == true {
            Label(L10n.text("Подключено", locale: locale), systemImage: "checkmark.circle")
            Button(L10n.text("Отключить Mi Fitness", locale: locale), role: .destructive) {
              disconnecting = true
            }
          } else {
            Text(
              L10n.text(
                model.connection == nil
                  ? "Состояние подключения Mi Fitness пока неизвестно."
                  : "Подключите аккаунт Mi Fitness и разрешите нужные показатели.", locale: locale))
            Button(L10n.text("Подключить Mi Fitness", locale: locale)) { action = .connect }
              .disabled(store.account == nil || model.connection?.available == false)
              .accessibilityIdentifier("connectMiFitness")
            if model.connection?.available == false {
              Text(L10n.text("Подключение Mi Fitness пока недоступно.", locale: locale))
                .foregroundStyle(.secondary)
            }
            if let message = model.connectionError {
              Text(L10n.text(message, locale: locale)).font(.footnote).foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Mi Fitness")
        } footer: {
          Text(
            L10n.text(
              "Данные поступают из облака после синхронизации устройства с Mi Fitness. Доступ подтверждается в окне Xiaomi.",
              locale: locale))
        }
      }
      Section {
        DatePicker(
          L10n.text("День", locale: locale), selection: $model.day, in: ...Date(),
          displayedComponents: .date)
        Picker(L10n.text("Период истории", locale: locale), selection: $model.historyDays) {
          Text(L10n.text("1 день", locale: locale)).tag(1)
          Text(L10n.text("7 дней", locale: locale)).tag(7)
          Text(L10n.text("30 дней", locale: locale)).tag(30)
        }
        Button(
          L10n.text(model.loading ? "Чтение показателей…" : "Прочитать показатели", locale: locale)
        ) { action = .read }
        .disabled(model.loading).accessibilityIdentifier("readHealthProviderData")
        if model.loading || model.connecting {
          ProgressView(L10n.text("Загрузка…", locale: locale))
        }
        if let result = model.result {
          LabeledContent(
            L10n.text(result.cached ? "Сохранённые данные от" : "Данные получены", locale: locale)
          ) {
            if let date = result.fetchedAt {
              Text(date, format: .dateTime.day().month().hour().minute())
            }
          }
          if result.cached {
            Text(
              L10n.text(
                "Источник недоступен. Показана последняя сохранённая копия этого периода.",
                locale: locale)
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        }
        if let error = model.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
      } footer: {
        Text(
          L10n.text(
            "Последние измерения за выбранный период; шаги и энергия — за выбранный день. Отсутствующие значения обозначены прочерком.",
            locale: locale))
      }
      if let result = model.result {
        Section(L10n.text("Показатели здоровья", locale: locale)) {
          ForEach(model.readings) { reading in
            VStack(alignment: .leading, spacing: 4) {
              LabeledContent(
                L10n.text(reading.metric.titleKey, locale: locale), value: text(reading))
              Text(L10n.text(reading.provider.titleKey, locale: locale))
                .font(.caption).foregroundStyle(.secondary)
              if reading.cached {
                Text(L10n.text("Сохранённые данные", locale: locale))
                  .font(.caption).foregroundStyle(.secondary)
              }
              if let message = reading.failureMessage {
                Text(L10n.text(message, locale: locale)).font(.footnote).foregroundStyle(.red)
              }
              if let date = reading.date {
                Text(date, format: .dateTime.day().month().hour().minute()).font(.caption)
                  .foregroundStyle(.secondary)
              } else if !reading.permitted && reading.failureMessage == nil {
                Text(L10n.text("Доступ к этому показателю не предоставлен.", locale: locale)).font(
                  .caption
                ).foregroundStyle(.secondary)
              }
            }.accessibilityElement(children: .combine)
          }
          if let weight = result.snapshot(for: .bodyWeight)?.latest(.bodyWeight) {
            Button(
              L10n.text(
                store.bodyWeights.contains { $0.id == weight.id }
                  ? "Измерение уже сохранено" : "Сохранить измерение веса", locale: locale)
            ) {
              _ = store.saveBodyWeight(
                BodyWeightEntry(id: weight.id, measuredAt: weight.end, weightKG: weight.value))
            }.disabled(store.bodyWeights.contains { $0.id == weight.id }).accessibilityIdentifier(
              "importProviderBodyWeight")
          }
        }
      }
      if model.enabled {
        Section {
          Button(L10n.text("Не показывать показатели", locale: locale)) {
            model.stopDisplaying()
            action = nil
            readRevision += 1
          }
        }
      }
    }
    .disabled(store.isDemoMode || model.connecting || store.account?.isBusy == true)
    .navigationTitle(L10n.text("Источники здоровья", locale: locale))
    .navigationBarTitleDisplayMode(.inline)
    .task(
      id:
        "\(model.sources.contextID)-\(store.workspaceID)-\(model.day)-\(model.historyDays)-\(phase)-\(readRevision)"
    ) {
      guard phase == .active, !store.isDemoMode else { return }
      model.resetContext()
      await model.loadConnection()
      await model.load(calendar: calendar)
    }
    .task(id: action) {
      guard let requested = action else { return }
      switch requested {
      case .shareApple(let enabled): await model.sources.appleSync?.setEnabled(enabled)
      case .read: await model.load(calendar: calendar, explicit: true)
      case .disconnect: await model.disconnect()
      case .connect:
        await model.connect(using: store.account) { url in
          guard let account = store.account else { throw HealthDataError.unavailable }
          let callback: ASWebAuthenticationSession.Callback
          switch account.callback {
          case .https:
            callback = .https(host: account.callbackHost, path: ServerConfiguration.callbackPath)
          case .customScheme(let scheme): callback = .customScheme(scheme)
          }
          do {
            return try await authentication.authenticate(
              using: url, callback: callback, additionalHeaderFields: [:])
          } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw ServerError.authenticationCancelled
          }
        }
      }
      if action == requested { action = nil }
    }
    .confirmationDialog(
      L10n.text("Отключить Mi Fitness", locale: locale), isPresented: $disconnecting,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Отключить Mi Fitness", locale: locale), role: .destructive) {
        action = .disconnect
      }
      Button(L10n.text("Отменить", locale: locale), role: .cancel) {}
    } message: {
      Text(
        L10n.text(
          "Разрешение будет отозвано, сохранённая копия данных Mi Fitness на этом устройстве удалена. Исходные записи в Mi Fitness сохранятся.",
          locale: locale))
    }
  }

  private func text(_ reading: HealthMetricReading) -> String {
    guard let raw = reading.value else { return "—" }
    let value =
      reading.metric == .sleep
      ? raw / 3600 : reading.metric == .bodyWeight ? weightUnit.display(raw) : raw
    let unit = reading.metric == .bodyWeight ? weightUnit.rawValue : reading.metric.unitKey
    return value.formatted(.number.locale(locale).precision(.fractionLength(0...3)))
      + (unit.isEmpty ? "" : " " + L10n.text(unit, locale: locale))
  }
}
