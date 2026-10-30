import FitnessTrackerCore
import Foundation
import HealthKit

@MainActor final class HealthKitService: HealthWorkoutExporting {
  private let store = HKHealthStore()
  func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    // Read permission is unnecessary: FitnessTracker only exports workouts on explicit request.
    try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
  }
  func export(_ workout: Workout) async throws {
    try Validation.workout(workout)
    guard workout.status == .completed, let end = workout.endedAt else {
      throw TrainingError.invalidState
    }
    guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
      throw ServiceError.unavailable("Разрешите запись тренировок в приложении «Здоровье».")
    }
    let config = HKWorkoutConfiguration()
    config.activityType = .traditionalStrengthTraining
    config.locationType = .indoor
    let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
    try await builder.beginCollection(at: workout.startedAt)
    try await builder.addMetadata([
      HKMetadataKeySyncIdentifier: AppCompatibility.healthSyncPrefix + workout.id.uuidString,
      HKMetadataKeySyncVersion: 1,
      HKMetadataKeyWorkoutBrandName: "FitnessTracker",
    ])
    var events: [HKWorkoutEvent] = []
    for pause in workout.pauses {
      events.append(
        HKWorkoutEvent(
          type: .pause, dateInterval: DateInterval(start: pause.startedAt, duration: 0),
          metadata: nil))
      events.append(
        HKWorkoutEvent(
          type: .resume, dateInterval: DateInterval(start: pause.endedAt, duration: 0),
          metadata: nil))
    }
    if !events.isEmpty { try await builder.addWorkoutEvents(events) }
    try await builder.endCollection(at: end)
    _ = try await builder.finishWorkout()
  }
}
