import Foundation
import Testing

@testable import FitLifeCore

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

@Test func csvArchivePreservesCurrentLoadMultiplierAndUnknownDuration() throws {
  let header = FitSessionCSVColumn.allCases.map(\.header).joined(separator: ";")
  let data = Data((header + "\n29.10.26;18:30;CSV fixture;Custom;;40;2;;10;;;").utf8)
  let current = try FitSessionCSVImporter.decode(data)
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(current))
  #expect(restored == current)
  #expect(restored.workouts[0].volume == 800)
  #expect(restored.workouts[0].durationIsKnown == false)
  #expect(restored.workouts[0].exercises[0].sets[0].loadMultiplier == 2)
  #expect(restored.version == WorkoutArchive.currentVersion)
}
