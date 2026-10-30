import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func csvNeverMergesDifferentWorkoutOrCustomExerciseNamesByPunctuation() throws {
  let header = FitSessionCSVColumn.allCases.map(\.header).joined(separator: ";")
  let rows = [
    "29.10.26;18:30;CSV-test;Custom A/B;;40;1;;10;;;",
    "29.10.26;18:30;CSV test;Custom A B;;40;1;;10;;;",
    "29.10.26;18:30;CSV test;💪;;40;1;;10;;;",
    "29.10.26;18:30;CSV test;🏋️;;40;1;;10;;;",
  ]
  let archive = try FitSessionCSVImporter.decode(
    Data(([header] + rows).joined(separator: "\n").utf8))
  #expect(archive.workouts.count == 2)
  #expect(Set(archive.workouts.flatMap { $0.exercises.map { $0.exercise.id } }).count == 4)
}

@Test func archiveVersionTwoKeepsLegacySingleLoadAndDurationSemantics() throws {
  let header = FitSessionCSVColumn.allCases.map(\.header).joined(separator: ";")
  let data = Data((header + "\n29.10.26;18:30;CSV fixture;Custom;;40;2;;10;;;").utf8)
  let current = try FitSessionCSVImporter.decode(data)
  var object = try #require(
    JSONSerialization.jsonObject(with: WorkoutArchiveCodec.encode(current)) as? [String: Any])
  object["version"] = 2
  var workouts = try #require(object["workouts"] as? [[String: Any]])
  workouts[0].removeValue(forKey: "durationIsKnown")
  var exercises = try #require(workouts[0]["exercises"] as? [[String: Any]])
  var sets = try #require(exercises[0]["sets"] as? [[String: Any]])
  sets[0].removeValue(forKey: "loadMultiplier")
  exercises[0]["sets"] = sets
  workouts[0]["exercises"] = exercises
  object["workouts"] = workouts
  let migrated = try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
  #expect(migrated.workouts[0].volume == 400)
  #expect(migrated.workouts[0].durationIsKnown == nil)
  #expect(migrated.workouts[0].exercises[0].sets[0].loadMultiplier == nil)
  #expect(migrated.version == WorkoutArchive.currentVersion)
}
