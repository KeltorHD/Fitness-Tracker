import FitnessTrackerCore
import Foundation
import HealthKit

/// iOS 26 live workout data (including paired AirPods Pro 3). HealthKit chooses the sensor.
/// The temporary builder is discarded; only an explicit journal export saves an HKWorkout.
@MainActor final class AirPodsHeartRateService: NSObject, LiveHeartRateServing {
  var onChange: (@MainActor (LiveHeartRateSnapshot) -> Void)?
  private var store: HKHealthStore?
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  private var activeRequest: UUID?
  private var snapshot = LiveHeartRateSnapshot()

  func start(sessionID: UUID) async throws {
    guard activeRequest == nil else { throw TrainingError.invalidState }
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ServiceError.unavailable("HealthKit недоступен на этом устройстве.")
    }
    let healthStore = store ?? HKHealthStore()
    store = healthStore
    activeRequest = sessionID
    publish(LiveHeartRateSnapshot(sessionID: sessionID, state: .starting))
    try await withTaskCancellationHandler {
      do {
        try await authorize(healthStore)
        try check(sessionID)
        guard healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
          throw ServiceError.unavailable(
            "Разрешите доступ к тренировкам в «Здоровье», чтобы получать пульс AirPods.")
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let currentSession = try HKWorkoutSession(
          healthStore: healthStore, configuration: configuration)
        let currentBuilder = currentSession.associatedWorkoutBuilder()
        let source = HKLiveWorkoutDataSource(
          healthStore: healthStore, workoutConfiguration: configuration)
        let heartRate = HKQuantityType(.heartRate)
        for type in source.typesToCollect where type != heartRate {
          source.disableCollection(for: type)
        }
        source.enableCollection(for: heartRate, predicate: nil)
        currentBuilder.dataSource = source
        currentSession.delegate = self
        currentBuilder.delegate = self
        session = currentSession
        builder = currentBuilder
        let start = Date()
        currentSession.startActivity(with: start)
        // Completion APIs keep SDK handles in their owner; only Void/errors cross suspension.
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          currentBuilder.beginCollection(withStart: start) { success, error in
            if let error {
              continuation.resume(throwing: error)
            } else if success {
              continuation.resume()
            } else {
              continuation.resume(throwing: TrainingError.invalidState)
            }
          }
        }
        try check(sessionID)
        if snapshot.state == .starting {
          publish(LiveHeartRateSnapshot(sessionID: sessionID, state: .running))
        }
      } catch {
        if activeRequest == sessionID {
          tearDown()
          publish(
            LiveHeartRateSnapshot(
              sessionID: sessionID, state: error is CancellationError ? .stopped : .failed))
        }
        throw error
      }
    } onCancel: {
      // One bounded actor hop; the view owns and cancels the start operation.
      Task { @MainActor [weak self] in
        if self?.activeRequest == sessionID { self?.stop() }
      }
    }
  }

  func pause() {
    guard activeRequest != nil else { return }
    if snapshot.state == .starting {
      stop()
      return
    }
    guard snapshot.state == .running else { return }
    session?.pause()
    publish(LiveHeartRateSnapshot(sessionID: activeRequest, state: .paused))
  }
  func resume() {
    guard activeRequest != nil, snapshot.state == .paused else { return }
    session?.resume()
    publish(LiveHeartRateSnapshot(sessionID: activeRequest, state: .running))
  }
  func stop() {
    guard let request = activeRequest else { return }
    tearDown()
    publish(LiveHeartRateSnapshot(sessionID: request, state: .stopped))
  }
  private func check(_ request: UUID) throws {
    try Task.checkCancellation()
    guard activeRequest == request else { throw CancellationError() }
  }
  private func tearDown() {
    activeRequest = nil
    session?.delegate = nil
    builder?.delegate = nil
    if let session, [.running, .paused].contains(session.state) {
      session.stopActivity(with: Date())
    }
    builder?.discardWorkout()
    session?.end()
    builder = nil
    session = nil
  }
  private func publish(_ value: LiveHeartRateSnapshot) {
    snapshot = value
    onChange?(value)
  }
  private func authorize(_ store: HKHealthStore) async throws {
    let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKObjectType.workoutType()]
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read) {
        success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: TrainingError.invalidState)
        }
      }
    }
  }
}

extension AirPodsHeartRateService: HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    // Journal pause/resume dates remain the source of truth; no polling or synthetic samples.
  }
  nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    let type = HKQuantityType(.heartRate)
    guard collectedTypes.contains(type), let stats = workoutBuilder.statistics(for: type),
      let value = stats.mostRecentQuantity(), let interval = stats.mostRecentQuantityDateInterval()
    else { return }
    let reading = HeartRateReading(
      date: interval.end,
      beatsPerMinute: value.doubleValue(for: .count().unitDivided(by: .minute())))
    guard reading.isValid else { return }
    let identity = ObjectIdentifier(workoutBuilder)
    Task { @MainActor [weak self] in
      guard let self, self.builder.map(ObjectIdentifier.init) == identity,
        let request = self.activeRequest, self.snapshot.state == .running
      else { return }
      self.publish(LiveHeartRateSnapshot(sessionID: request, state: .running, reading: reading))
    }
  }
}

extension AirPodsHeartRateService: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState, date: Date
  ) {
    let identity = ObjectIdentifier(workoutSession)
    let state = toState.rawValue
    Task { @MainActor [weak self] in
      guard let self, self.session.map(ObjectIdentifier.init) == identity,
        let request = self.activeRequest
      else { return }
      switch HKWorkoutSessionState(rawValue: state) {
      case .running:
        guard self.snapshot.state != .paused else { return }
        self.publish(LiveHeartRateSnapshot(sessionID: request, state: .running))
      case .paused:
        guard self.session?.state == .paused else { return }
        self.publish(LiveHeartRateSnapshot(sessionID: request, state: .paused))
      case .stopped, .ended:
        self.tearDown()
        self.publish(LiveHeartRateSnapshot(sessionID: request, state: .stopped))
      default: break
      }
    }
  }
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didFailWithError error: any Error
  ) {
    AppErrorReporter.record(error, operation: "liveWorkoutHeartRate")
    let identity = ObjectIdentifier(workoutSession)
    Task { @MainActor [weak self] in
      guard let self, self.session.map(ObjectIdentifier.init) == identity,
        let request = self.activeRequest
      else { return }
      self.tearDown()
      self.publish(LiveHeartRateSnapshot(sessionID: request, state: .failed))
    }
  }
}
