import CoreTransferable
import FitSessionCore
import Foundation
import UniformTypeIdentifiers

struct WorkoutDocument: Transferable {
  let workout: Workout
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { document in
      try WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [document.workout], templates: []))
    }
    .suggestedFileName("FitSession-workout.json")
  }
}
