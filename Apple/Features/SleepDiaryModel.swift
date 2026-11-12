import FitLifeCore
import Foundation
import Observation

@MainActor @Observable final class SleepDiaryModel {
  private(set) var nights: [SleepNight] = []
  private(set) var loading = false
  private(set) var enabled: Bool
  var error: String?
  @ObservationIgnored private let reader: any HealthSleepReading
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var generation = UUID()
  init(reader: any HealthSleepReading, defaults: UserDefaults = .standard) {
    self.reader = reader
    self.defaults = defaults
    enabled = defaults.bool(forKey: "sleepDiaryEnabled")
  }
  func enable() async {
    guard !loading else { return }
    loading = true
    error = nil
    do {
      try await reader.authorize()
      try Task.checkCancellation()
      enabled = true
      defaults.set(true, forKey: "sleepDiaryEnabled")
    } catch is CancellationError {} catch {
      self.error = "Не удалось прочитать данные сна. Проверьте доступ к «Здоровью» и повторите."
    }
    loading = false
  }
  func disable() {
    generation = UUID()
    enabled = false
    nights = []
    loading = false
    error = nil
    defaults.set(false, forKey: "sleepDiaryEnabled")
  }
  func load(day: Date, calendar: Calendar) async {
    guard enabled else { return }
    let token = UUID()
    generation = token
    loading = true
    nights = []
    error = nil
    defer { if generation == token { loading = false } }
    do {
      let value = try await reader.nights(endingOn: day, calendar: calendar)
      guard generation == token, !Task.isCancelled, enabled else { return }
      nights = value
    } catch {
      guard generation == token, !Task.isCancelled else { return }
      self.error = "Не удалось прочитать данные сна. Проверьте доступ к «Здоровью» и повторите."
    }
  }
}
