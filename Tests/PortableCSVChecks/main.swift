import FitnessTrackerCore
import Foundation

private struct CSVCheckFailure: Error { let message: String }
private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CSVCheckFailure(message: message) }
}

@main struct PortableCSVChecks {
  @MainActor static func main() throws {
    let header = FitSessionCSVColumn.allCases.map(\.header).joined(separator: ";")
    let fixture = Data((header + "\n29.10.26;18:30;CSV fixture;Custom;;10;2;;8;;;").utf8)
    let paths = Array(CommandLine.arguments.dropFirst())
    let repository = MemoryWorkoutRepository()
    let dataSets =
      try paths.isEmpty ? [fixture] : paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    for (index, data) in dataSets.enumerated() {
      let archive = try FitSessionCSVImporter.decode(data)
      try WorkoutArchiveCodec.validate(archive)
      let encoded = try WorkoutArchiveCodec.encode(archive)
      try expect(
        try WorkoutArchiveCodec.decode(encoded) == archive,
        "Converted CSV must round-trip without data loss")
      try expect(
        archive.workouts.allSatisfy { $0.durationIsKnown == false && $0.bodyWeightKG == nil },
        "CSV must not invent duration or body weight")
      try expect(
        archive.workouts.allSatisfy {
          $0.formattedRecordedDuration(locale: Locale(identifier: "ru_RU")) == "—"
        },
        "Unknown duration must be displayed as a dash")
      let imported = try repository.importArchive(archive)
      try expect(
        try !repository.importArchive(archive).hasChanges, "Repeated CSV import must be idempotent")
      let sets = archive.workouts.flatMap { $0.exercises.flatMap(\.sets) }
      let zero = sets.filter { $0.repetitions == 0 }.count
      try expect(
        sets.filter { $0.repetitions == 0 }.allSatisfy { $0.completedAt == nil },
        "Zero repetitions must remain unperformed")
      print(
        "CSV source \(index + 1): \(archive.workouts.count) workouts, \(sets.count) sets, \(zero) zero-repetition sets, \(imported.addedWorkouts) added, round-trip/reimport passed."
      )
    }
    print("Portable CSV checks passed (no Apple SDK).")
  }
}
