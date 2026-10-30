import Foundation

/// Setup guidance, not a device identity or a filter over HealthKit sources.
enum TrackerDeviceProfile: String, CaseIterable, Identifiable, Sendable {
  case xiaomiSmartBand10, huaweiWatchGT6Pro, other
  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .xiaomiSmartBand10: "Xiaomi Smart Band 10"
    case .huaweiWatchGT6Pro: "HUAWEI WATCH GT 6 Pro"
    case .other: "Другой трекер"
    }
  }
  var healthSetupKey: String {
    switch self {
    case .xiaomiSmartBand10:
      "Для Mi Band включите в Mi Fitness: Профиль → Данные сторонних приложений → Здоровье. Разрешите передачу нужных показателей."
    case .huaweiWatchGT6Pro:
      "Подключите WATCH GT 6 Pro к HUAWEI Health на iPhone и включите доступную передачу данных в Apple «Здоровье». В «Здоровье» откройте профиль → Приложения и службы → HUAWEI Health и разрешите запись нужных показателей."
    case .other:
      "В приложении вашего трекера включите передачу данных в Apple «Здоровье» и разрешите запись нужных показателей. Затем разрешите FitnessTracker их чтение."
    }
  }
  var bluetoothSetupKey: String {
    switch self {
    case .xiaomiSmartBand10:
      "На Mi Band 10 откройте Настройки → Share HR и включите передачу пульса. Держите браслет рядом с iPhone."
    case .huaweiWatchGT6Pro:
      "На WATCH GT 6 Pro откройте Настройки → Трансляция пульса (HR Data Broadcasts) и запустите трансляцию. Держите часы рядом с iPhone и нажмите «Найти пульсометр»."
    case .other:
      "Включите на устройстве трансляцию пульса по Bluetooth и держите его рядом с iPhone. Затем нажмите «Найти пульсометр»."
    }
  }
  var bluetoothNoteKey: String? {
    switch self {
    case .huaweiWatchGT6Pro:
      "Если пункта HR Data Broadcasts нет, используйте режим Apple «Здоровье». Во время трансляции связь с HUAWEI Health может временно прерываться."
    case .xiaomiSmartBand10, .other: nil
    }
  }
  var supportURL: URL? {
    switch self {
    case .xiaomiSmartBand10: URL(string: "https://www.mi.com/global/support/faq/details/KA-579104/")
    case .huaweiWatchGT6Pro:
      URL(string: "https://consumer.huawei.com/en/support/content/en-us15827504/")
    case .other: nil
    }
  }
}
