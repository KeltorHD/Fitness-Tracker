import FitLifeCore
import Foundation

extension HealthProviderID {
  var titleKey: String {
    switch self {
    case .appleHealth: "Apple «Здоровье»"
    case .miFitness: "Mi Fitness"
    }
  }
}

extension HealthMetric {
  var titleKey: String {
    switch self {
    case .sleep: "Сон"
    case .steps: "Шаги"
    case .bodyWeight: "Вес тела"
    case .bodyFatPercentage: "Доля жира"
    case .heartRate: "Пульс"
    case .restingHeartRate: "Пульс в покое"
    case .activeEnergy: "Активная энергия"
    case .totalEnergy: "Общая энергия"
    case .bloodOxygen: "Кислород в крови"
    case .distance: "Пройденное расстояние"
    }
  }
  var unitKey: String {
    switch self {
    case .sleep: "ч"
    case .steps: ""
    case .bodyWeight: "кг"
    case .bodyFatPercentage, .bloodOxygen: "%"
    case .heartRate, .restingHeartRate: "уд/мин"
    case .activeEnergy, .totalEnergy: "ккал"
    case .distance: "м"
    }
  }
}

enum HealthProviderMessage {
  static func error(_ error: any Error) -> String {
    switch error {
    case HealthSyncFailure.stateConflict:
      "Не удалось согласовать очередь синхронизации с сервером. Данные сохранены на этом iPhone."
    case HealthSyncFailure.limit:
      "Достигнут лимит истории здоровья на сервере. Очередь сохранена на этом iPhone."
    case HealthDataError.notConnected:
      "Откройте журнал аккаунта и проверьте подключение источника здоровья."
    case HealthDataError.permissionRequired:
      "Разрешите нужные показатели при подключении источника здоровья."
    case HealthDataError.unsupportedMetric: "Этот источник не предоставляет выбранные показатели."
    case HealthDataError.invalidData, ServerError.invalidResponse:
      "Не удалось проверить данные источника здоровья. Повторите попытку."
    case HealthDataError.unavailable:
      "Источник здоровья недоступен. Проверьте подключение и повторите."
    case ServerError.signInRequired: "Войдите в FitLife, чтобы подключить источник здоровья."
    case let value as ServerError:
      value.errorDescription ?? "Не удалось прочитать показатели. Повторите попытку."
    default: "Не удалось прочитать показатели. Повторите попытку."
    }
  }
}
