import CoreTransferable
import FitSessionCore
import Foundation
import UniformTypeIdentifiers

struct WorkoutDocument: Transferable {
  let workout: Workout
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { document in
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      return try encoder.encode(document.workout)
    }
    .suggestedFileName("FitSession-workout.json")
  }
}
