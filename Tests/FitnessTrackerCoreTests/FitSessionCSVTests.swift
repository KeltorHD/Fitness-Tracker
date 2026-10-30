import Foundation
import Testing

@testable import FitnessTrackerCore

private func csvData(_ rows: [String], skipHeader: String = "ПРОПУЩЕН") -> Data {
  let header = FitSessionCSVColumn.allCases.map { $0 == .skipped ? skipHeader : $0.header }.joined(
    separator: ";")
  return Data(([header] + rows).joined(separator: "\n").utf8)
}
private let csvZone = TimeZone(secondsFromGMT: 0) ?? .gmt
private let csvRow = "29.10.26;18:30;CSV test;Жим лёжа;;40;2;;10;;;"

@Test func stableImportUUIDMatchesTheRFCVersionFiveVector() throws {
  let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
  #expect(
    StableIdentifier.uuid("https://example.com/" + String(repeating: "a", count: 100)).uuidString
      .lowercased() == "eaca78b0-b79e-5e39-a599-4ec7379ac706")
  #expect(
    StableIdentifier.uuid("www.widgets.com", namespace: dns).uuidString.lowercased()
      == "21f7f8de-8051-5b89-8680-0195ef798b6a")
}

@Test func csvSupportsBothSkipHeadersAndPreservesMultiplierAndZeroRepetitions() throws {
  let zero = "29.10.26;18:30;CSV test;Жим лёжа;;40;2;;0;;;"
  let first = try FitSessionCSVImporter.decode(csvData([csvRow, zero]), timeZone: csvZone)
  let second = try FitSessionCSVImporter.decode(
    csvData([csvRow, zero], skipHeader: "ПРОПУЩЕННЫЙ"), timeZone: csvZone)
  #expect(first == second)
  let workout = try #require(first.workouts.first)
  #expect(workout.status == .completed && workout.completedSets == 1 && workout.totalSets == 2)
  #expect(workout.volume == 800)
  #expect(workout.exercises[0].sets[0].weightKG == 40)
  #expect(workout.exercises[0].sets[0].loadMultiplier == 2)
  #expect(workout.exercises[0].sets[1].repetitions == 0)
  #expect(workout.exercises[0].sets[1].completedAt == nil)
  #expect(workout.durationIsKnown == false && workout.endedAt == workout.startedAt)
  #expect(workout.bodyWeightKG == nil)
  #expect(workout.exercises[0].exercise.id == ExerciseCatalog.all[1].id)
  try Validation.workout(workout)
}

@Test func csvPreservesUTF8BOMQuotesSemicolonsAndMultilineNotes() throws {
  let row =
    "29.10.26;18:30;\"CSV; test\";\"Custom; \"\"exercise\"\"\";;10;1;;5;;;\"First line\r\nSecond \"\"line\"\"; note\""
  let data = Data(
    ("\u{feff}"
      + String(decoding: csvData([row]), as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n")
      + "\r\n;;;;;;;;;;;\r\n").utf8)
  let archive = try FitSessionCSVImporter.decode(data, timeZone: csvZone)
  let workout = try #require(archive.workouts.first)
  #expect(workout.name == "CSV; test")
  #expect(workout.exercises.first?.exercise.name == "Custom; \"exercise\"")
  #expect(workout.notes.contains("First line"))
  #expect(workout.notes.contains("Second \"line\"; note"))
  #expect(workout.exercises.first?.exercise.muscle == .fullBody)
}

@Test @MainActor func csvReimportIsIdempotentAndNeverOverwritesExistingSessions() throws {
  let archive = try FitSessionCSVImporter.decode(csvData([csvRow, csvRow]), timeZone: csvZone)
  let repository = MemoryWorkoutRepository()
  let first = try repository.importArchive(archive)
  #expect(first.addedWorkouts == 1)
  #expect(archive.workouts[0].totalSets == 2)
  #expect(Set(archive.workouts[0].exercises[0].sets.map(\.id)).count == 2)
  let changed = try FitSessionCSVImporter.decode(
    csvData([csvRow.replacingOccurrences(of: ";40;", with: ";45;"), csvRow]), timeZone: csvZone)
  #expect(changed.workouts[0].id == archive.workouts[0].id)
  let repeated = try repository.importArchive(changed)
  #expect(!repeated.hasChanges && repeated.skippedExisting == 1)
  #expect(try repository.workouts() == archive.workouts)
}

@Test func csvTimezoneChangesDatesWithoutChangingImportIdentity() throws {
  let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
  let first = try FitSessionCSVImporter.decode(csvData([csvRow]), timeZone: csvZone)
  let second = try FitSessionCSVImporter.decode(csvData([csvRow]), timeZone: moscow)
  #expect(first.workouts[0].id == second.workouts[0].id)
  #expect(first.workouts[0].startedAt.timeIntervalSince(second.workouts[0].startedAt) == 3 * 3600)
}

@Test func csvSkippedAndEmptyWeightRowsNeverInventCompletedSetsOrBodyWeight() throws {
  let rows = [
    "29.10.26;18:30;CSV test;Custom;;;;;12;;;",
    "29.10.26;18:30;CSV test;Custom;;30;1;;12;;true;",
    "28.10.26;18:30;Skipped;Custom;;30;1;;0;;;",
  ]
  let archive = try FitSessionCSVImporter.decode(csvData(rows), timeZone: csvZone)
  #expect(archive.workouts.count == 2)
  let performed = try #require(archive.workouts.first { $0.status == .completed })
  #expect(performed.completedSets == 1 && performed.volume == 0)
  #expect(performed.bodyWeightKG == nil)
  #expect(archive.workouts.filter { $0.status == .cancelled }.count == 1)
}

@Test func csvRepeatAndTemplatePreserveLoadMultiplierButStartARecordedNativeTimer() throws {
  let original = try FitSessionCSVImporter.decode(csvData([csvRow]), timeZone: csvZone).workouts[0]
  let repeated = try WorkoutEngine.repeatWorkout(original)
  #expect(repeated.durationIsKnown != false)
  #expect(repeated.exercises[0].sets[0].loadMultiplier == 2)
  let template = try WorkoutEngine.makeTemplate(from: original)
  #expect(try template.start().exercises[0].sets[0].loadMultiplier == 2)
  #expect(
    try WorkoutArchiveCodec.decode(
      WorkoutArchiveCodec.encode(WorkoutArchive(workouts: [original], templates: [template]))
    ).workouts == [original])
  #expect(TrainingStatistics.records(in: [original]).first?.weightKG == 40)
}

@Test func csvRejectsInvalidDatesNumbersFlagsAndUnsupportedMeasurements() throws {
  let invalid = [
    csvRow.replacingOccurrences(of: "29.10.26", with: "31.02.26"),
    csvRow.replacingOccurrences(of: "18:30", with: "25:30"),
    csvRow.replacingOccurrences(of: ";40;", with: ";nan;"),
    csvRow.replacingOccurrences(of: ";40;", with: ";-1;"),
    csvRow.replacingOccurrences(of: ";2;", with: ";0;"),
    csvRow.replacingOccurrences(of: ";10;", with: ";-1;"),
    "29.10.26;18:30;CSV test;Custom;;20;1;;10;;maybe;",
  ]
  for row in invalid {
    do {
      _ = try FitSessionCSVImporter.decode(csvData([csvRow, row]), timeZone: csvZone)
      Issue.record("Invalid row was accepted")
    } catch let error as FitSessionCSVError {
      guard case .invalidValue(line: 3, column: _) = error else {
        Issue.record("Wrong diagnostic line")
        continue
      }
    }
  }
  #expect(throws: FitSessionCSVError.unsupportedMeasurement(line: 2)) {
    try FitSessionCSVImporter.decode(
      csvData(["29.10.26;18:30;CSV test;Custom;2;;;;10;;;"]), timeZone: csvZone)
  }
}

@Test func csvRejectsMalformedQuotedDataMissingHeadersAndOversizedInput() throws {
  #expect(throws: FitSessionCSVError.malformed(line: 2)) {
    try FitSessionCSVImporter.decode(csvData(["\"unfinished"]), timeZone: csvZone)
  }
  #expect(throws: FitSessionCSVError.malformed(line: 2)) {
    try FitSessionCSVImporter.decode(csvData(["\"closed\"suffix"]), timeZone: csvZone)
  }
  #expect(throws: FitSessionCSVError.missingColumns) {
    try FitSessionCSVImporter.decode(Data("DATE;NAME\n1;Test".utf8))
  }
  #expect(throws: FitSessionCSVError.noRecords) { try FitSessionCSVImporter.decode(csvData([])) }
  #expect(throws: WorkoutArchiveError.tooLarge) {
    try FitSessionCSVImporter.decode(
      Data(repeating: 32, count: WorkoutArchiveCodec.maximumBytes + 1))
  }
}

@Test func csvSplitsLongExerciseRowsWithoutLosingSetsAndKeepsDistinctSessionTimes() throws {
  let rows =
    Array(repeating: csvRow, count: 31) + [csvRow.replacingOccurrences(of: "18:30", with: "19:30")]
  let archive = try FitSessionCSVImporter.decode(csvData(rows), timeZone: csvZone)
  #expect(archive.workouts.count == 2)
  let first = try #require(archive.workouts.first { $0.totalSets == 31 })
  #expect(first.exercises.map { $0.sets.count } == [30, 1])
  #expect(Set(first.exercises.flatMap { $0.sets.map(\.id) }).count == 31)
  #expect(
    ExerciseProgressReport(workouts: [first], now: .distantFuture).exercises.first?.points.first?
      .setCount == 31)
}

@Test func zeroRepetitionImportsStillCannotCompleteAZeroRepetitionSet() throws {
  var workout = Workout(
    name: "Zero fixture",
    exercises: [
      WorkoutExercise(exercise: ExerciseCatalog.all[0], sets: [WorkoutSet(repetitions: 0)])
    ])
  try Validation.workout(workout)
  let previous = workout
  #expect(throws: TrainingError.invalidRepetitions) {
    try WorkoutEngine.completeSet(
      in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
      repetitions: 0, weightKG: 40)
  }
  #expect(workout == previous)
}
