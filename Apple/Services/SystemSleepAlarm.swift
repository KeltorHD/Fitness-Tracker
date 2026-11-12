import AlarmKit
import FitLifeCore
import Foundation
import SwiftUI

private struct SleepAlarmMetadata: AlarmMetadata { let planID: UUID }

@MainActor final class SystemSleepAlarm: SleepAlarmScheduling {
  func schedule(_ plan: SleepAlarmPlan) async throws {
    let manager = AlarmManager.shared
    guard plan.isValid, plan.fireDate > Date() else { throw SleepAlarmError.invalid }
    if manager.authorizationState != .authorized {
      guard try await manager.requestAuthorization() == .authorized else {
        throw SleepAlarmError.permission
      }
    }
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource("Пора просыпаться", locale: L10n.locale))
    } else {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource("Пора просыпаться", locale: L10n.locale),
        stopButton: AlarmButton(
          text: LocalizedStringResource("Выключить", locale: L10n.locale), textColor: .white,
          systemImageName: "stop.fill"))
    }
    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: SleepAlarmMetadata(planID: plan.id),
      tintColor: (FitnessColorTheme(
        rawValue: UserDefaults.standard.string(forKey: "colorTheme") ?? "") ?? .defaultTheme).accent
    )
    _ = try await manager.schedule(
      id: plan.id,
      configuration: AlarmManager.AlarmConfiguration.alarm(
        schedule: .fixed(plan.fireDate), attributes: attributes))
  }
  func cancel(_ id: UUID) throws {
    guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }) else { return }
    if alarm.state == .alerting { try AlarmManager.shared.stop(id: id) }
    if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
      try AlarmManager.shared.cancel(id: id)
    }
  }
  func activeIDs() throws -> Set<UUID> {
    if AlarmManager.shared.authorizationState == .denied { throw SleepAlarmError.permission }
    guard AlarmManager.shared.authorizationState == .authorized else { return [] }
    return Set(try AlarmManager.shared.alarms.map(\.id))
  }
}
