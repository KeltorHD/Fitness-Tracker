import FitnessTrackerCore
import Foundation
import Observation

struct BodyWeightHistoryItem: Identifiable {
  var id: String { point.id }
  let point: BodyWeightPoint
  let workoutName: String?
}

@MainActor @Observable final class BodyWeightViewModel {
  private(set) var summary = BodyWeightSummary(entries: [], workouts: [])
  private(set) var items: [BodyWeightHistoryItem] = []
  @ObservationIgnored private let now: () -> Date
  init(now: @escaping () -> Date = Date.init) { self.now = now }
  func refresh(entries: [BodyWeightEntry], workouts: [Workout]) {
    summary = BodyWeightSummary(entries: entries, workouts: workouts, now: now())
    let names = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
    items = summary.points.map { point in
      let name: String?
      switch point.source {
      case .measurement: name = nil
      case .workout(let id): name = names[id]
      }
      return BodyWeightHistoryItem(point: point, workoutName: name)
    }
  }
}

@MainActor @Observable final class BodyWeightEditorModel {
  var text: String
  var date: Date
  var error: String?
  let id: UUID
  let unit: WeightUnit
  @ObservationIgnored private let decimalSeparator: String
  @ObservationIgnored private let originalWeightKG: Double?
  @ObservationIgnored private let originalText: String
  init(
    weightKG: Double? = nil, date: Date = Date(), id: UUID = UUID(), unit: WeightUnit,
    locale: Locale = .current
  ) {
    self.id = id
    self.date = date
    self.unit = unit
    decimalSeparator = locale.decimalSeparator ?? "."
    originalWeightKG = weightKG
    let initialText =
      weightKG.map {
        unit.display($0).formatted(
          .number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
      } ?? ""
    originalText = initialText
    text = initialText
  }
  func valueInKG() throws -> Double {
    if text == originalText, let originalWeightKG {
      try Validation.bodyWeight(originalWeightKG)
      return originalWeightKG
    }
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.count <= 20 else { throw TrainingError.invalidBodyWeight }
    var normalized = ""
    for character in input {
      if let digit = character.wholeNumberValue, (0...9).contains(digit) {
        normalized += String(digit)
      } else if character == "," || character == "." || String(character) == decimalSeparator {
        normalized += "."
      } else {
        throw TrainingError.invalidBodyWeight
      }
    }
    guard let displayed = Double(normalized) else { throw TrainingError.invalidBodyWeight }
    let kilograms = unit.kilograms(from: displayed)
    try Validation.bodyWeight(kilograms)
    return kilograms
  }
}
