import Foundation

public struct BodyWeightEntry: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var measuredAt: Date
  public var weightKG: Double
  /// An explicitly shared weigh-in can outlive its workout, including cancellation/deletion.
  /// Nil keeps independent and legacy measurements independent.
  public var workoutID: UUID?
  public init(
    id: UUID = UUID(), measuredAt: Date = Date(), weightKG: Double, workoutID: UUID? = nil
  ) {
    self.id = id
    self.measuredAt = measuredAt
    self.weightKG = weightKG
    self.workoutID = workoutID
  }
}

public enum BodyWeightSource: Equatable, Sendable {
  case measurement(UUID)
  case workout(UUID)
}

public struct BodyWeightPoint: Identifiable, Equatable, Sendable {
  public var id: String {
    switch source {
    case .measurement(let id): "measurement/\(id.uuidString)"
    case .workout(let id): "workout/\(id.uuidString)"
    }
  }
  public let source: BodyWeightSource
  public let date: Date
  public let weightKG: Double
}

/// Independent weigh-ins plus completed workout snapshots. Explicitly linked weigh-ins retain
/// their own date and survive cancellation; equal completed snapshots do not add a second point.
/// Matching unrelated measurements by weight or date would erase real records, so links are explicit.
public struct BodyWeightSummary: Equatable, Sendable {
  public let points: [BodyWeightPoint]
  public var latest: BodyWeightPoint? { points.first }
  public var changeKG: Double? {
    guard let latest, let previous = points.dropFirst().first else { return nil }
    return latest.weightKG - previous.weightKG
  }
  public init(entries: [BodyWeightEntry], workouts: [Workout], now: Date = Date()) {
    let recorded = entries.filter { $0.measuredAt <= now }
    var linkedWeights: [UUID: Set<Double>] = [:]
    for entry in recorded {
      if let id = entry.workoutID { linkedWeights[id, default: []].insert(entry.weightKG) }
    }
    let measurements = recorded.map {
      BodyWeightPoint(source: .measurement($0.id), date: $0.measuredAt, weightKG: $0.weightKG)
    }
    let sessions = workouts.compactMap { workout -> BodyWeightPoint? in
      guard workout.status == .completed, workout.startedAt <= now,
        let weight = workout.bodyWeightKG
      else { return nil }
      guard linkedWeights[workout.id]?.contains(weight) != true else { return nil }
      return BodyWeightPoint(
        source: .workout(workout.id), date: workout.startedAt, weightKG: weight)
    }
    points = (measurements + sessions).sorted {
      $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
    }
  }
}
