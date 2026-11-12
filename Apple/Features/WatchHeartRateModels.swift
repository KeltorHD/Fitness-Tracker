import FitLifeCore
import Foundation
import Observation

/// Receives only immediate, ordered Watch events for the phone's current sensor request.
@MainActor final class AppleWatchHeartRateService: LiveHeartRateServing {
  var onChange: (@MainActor (LiveHeartRateSnapshot) -> Void)?
  private let send: @MainActor (WatchHeartRateCommand) throws -> Void
  private let now: () -> Date
  private var sessionID: UUID?
  private var sequence: UInt64 = 0
  private var received: UInt64 = 0
  private var requestedState = LiveHeartRateState.stopped
  private var timeout: Task<Void, Never>?
  init(
    now: @escaping () -> Date = Date.init,
    send: @escaping @MainActor (WatchHeartRateCommand) throws -> Void
  ) {
    self.now = now
    self.send = send
  }
  func start(sessionID: UUID) async throws {
    guard self.sessionID == nil else { throw TrainingError.invalidState }
    self.sessionID = sessionID
    received = 0
    requestedState = .running
    onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .starting))
    do {
      try command(.start)
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(45)) } catch { return }
        guard let self, self.sessionID == sessionID else { return }
        self.connectionFailed(sessionID: sessionID)
      }
    } catch {
      self.sessionID = nil
      requestedState = .stopped
      onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .failed))
      throw error
    }
  }
  func pause() {
    guard sessionID != nil else { return }
    requestedState = .paused
    do { try command(.pause) } catch { fail() }
    if let sessionID { onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .paused)) }
  }
  func resume() {
    guard sessionID != nil else { return }
    requestedState = .running
    do { try command(.resume) } catch { fail() }
  }
  func stop() {
    guard let sessionID else { return }
    timeout?.cancel()
    timeout = nil
    // Clear identity before sending: synchronous transport failures cannot re-enter this request.
    self.sessionID = nil
    requestedState = .stopped
    sequence += 1
    do {
      try send(
        WatchHeartRateCommand(sessionID: sessionID, sequence: sequence, action: .stop, date: now()))
    } catch {
      // The transport keeps the stop command as context for reconnection. Surface failure to the owner.
      onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .failed))
      return
    }
    onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .stopped))
  }
  func receive(_ event: WatchHeartRateEvent) {
    guard event.sessionID == sessionID, event.sequence > received, event.isRecent(at: now())
    else { return }
    received = event.sequence
    if event.state == .running, requestedState != .running { return }
    if event.state == .paused, requestedState != .paused { return }
    if event.state != .starting {
      timeout?.cancel()
      timeout = nil
    }
    let state = LiveHeartRateState(rawValue: event.state.rawValue) ?? .failed
    onChange?(
      LiveHeartRateSnapshot(sessionID: event.sessionID, state: state, reading: event.reading))
    if state == .failed || state == .stopped {
      sessionID = nil
      requestedState = .stopped
    }
  }
  func connectionFailed(sessionID: UUID) {
    guard self.sessionID == sessionID else { return }
    fail()
  }
  func disconnected() {
    if let sessionID { connectionFailed(sessionID: sessionID) }
  }
  private func fail() {
    guard let sessionID else { return }
    timeout?.cancel()
    timeout = nil
    self.sessionID = nil
    requestedState = .stopped
    sequence += 1
    do {
      try send(
        WatchHeartRateCommand(sessionID: sessionID, sequence: sequence, action: .stop, date: now()))
    } catch {
      // The failed snapshot reports the transport error; no health payload is logged.
      onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .failed))
      return
    }
    onChange?(LiveHeartRateSnapshot(sessionID: sessionID, state: .failed))
  }
  private func command(_ action: WatchHeartRateCommand.Action) throws {
    guard let sessionID else { return }
    sequence += 1
    try send(
      WatchHeartRateCommand(sessionID: sessionID, sequence: sequence, action: action, date: now()))
  }
}

/// Owns the Watch sensor task; pause, stop and delayed callbacks stay within their request identity.
@MainActor @Observable final class WatchHeartRateController {
  private(set) var snapshot = LiveHeartRateSnapshot()
  private(set) var error: String?
  @ObservationIgnored var send: ((WatchHeartRateEvent) -> Void)?
  @ObservationIgnored private let source: any LiveHeartRateServing
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var startTask: Task<Void, Never>?
  @ObservationIgnored private var command: WatchHeartRateCommand?
  @ObservationIgnored private var eventSequence: UInt64 = 0
  init(source: any LiveHeartRateServing, now: @escaping () -> Date = Date.init) {
    self.source = source
    self.now = now
    source.onChange = { [weak self] in self?.receive($0) }
  }
  func receive(_ value: WatchHeartRateCommand) {
    if value.action == .start {
      guard value.isRecent(at: now()),
        command.map({ value.date >= $0.date && value.sessionID != $0.sessionID }) ?? true
      else { return }
      startTask?.cancel()
      source.stop()
      command = value
      error = nil
      eventSequence = 0
      snapshot = LiveHeartRateSnapshot(sessionID: value.sessionID, state: .starting)
      startTask = Task { [weak self] in
        guard let self else { return }
        guard self.command?.sessionID == value.sessionID, self.command?.action == .start,
          !Task.isCancelled
        else { return }
        do { try await self.source.start(sessionID: value.sessionID) } catch {
          guard self.command?.sessionID == value.sessionID, !Task.isCancelled else { return }
          self.receive(LiveHeartRateSnapshot(sessionID: value.sessionID, state: .failed))
        }
      }
      return
    }
    guard let previous = command, value.sessionID == previous.sessionID,
      value.sequence > previous.sequence, previous.action != .stop,
      value.action == .stop || value.isRecent(at: now())
    else { return }
    command = value
    switch value.action {
    case .pause:
      if snapshot.state == .starting { stop() } else { source.pause() }
    case .resume: source.resume()
    case .stop: stop()
    case .start: break
    }
  }
  func stop() {
    startTask?.cancel()
    source.stop()
    if let value = command {
      command = WatchHeartRateCommand(
        sessionID: value.sessionID, sequence: value.sequence, action: .stop, date: value.date)
      receive(LiveHeartRateSnapshot(sessionID: value.sessionID, state: .stopped))
    }
  }
  func deliveryFailed() {
    error = "Не удалось передать пульс на iPhone. Держите телефон рядом и проверьте подключение."
  }
  private func receive(_ value: LiveHeartRateSnapshot) {
    guard let command, value.sessionID == command.sessionID else { return }
    if command.action == .stop, value.state != .stopped { return }
    if command.action == .pause, value.state == .running { return }
    snapshot = value
    if value.state == .failed {
      error =
        "Не удалось включить пульс. Проверьте разрешения «Здоровья» на часах и повторите с iPhone."
    }
    guard let state = WatchHeartRateEvent.State(rawValue: value.state.rawValue) else { return }
    eventSequence += 1
    send?(
      WatchHeartRateEvent(
        sessionID: command.sessionID, sequence: eventSequence, state: state, date: now(),
        reading: value.reading))
  }
}
