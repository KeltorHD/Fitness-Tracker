import Foundation
import Testing

@testable import FitnessTrackerCore

private let demoDate = Date(timeIntervalSince1970: 1_793_330_000)
private var demoCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
  return calendar
}

@MainActor private final class FailingDemoPersonalRepository: WorkoutRepository {
  let memory = MemoryWorkoutRepository()
  var failRead = false
  func workouts() throws -> [Workout] { try memory.workouts() }
  func templates() throws -> [WorkoutTemplate] {
    if failRead { throw TrainingError.invalidState }
    return try memory.templates()
  }
  func save(_ workout: Workout) throws { try memory.save(workout) }
  func saveTemplate(_ template: WorkoutTemplate) throws { try memory.saveTemplate(template) }
  func deleteWorkout(id: UUID) throws { try memory.deleteWorkout(id: id) }
  func deleteTemplate(id: UUID) throws { try memory.deleteTemplate(id: id) }
  func importArchive(_ archive: WorkoutArchive) throws -> ArchiveImportSummary {
    try memory.importArchive(archive)
  }
}

@Test func demoDataIsRepeatableValidatedHistoricalAndClearlyLabelled() throws {
  let first = try DemoWorkoutData.archive(relativeTo: demoDate, calendar: demoCalendar)
  #expect(try DemoWorkoutData.archive(relativeTo: demoDate, calendar: demoCalendar) == first)
  #expect(first.workouts.count == 24 && first.templates.count == 3)
  #expect(
    first.workouts.allSatisfy {
      $0.status == .completed && ($0.endedAt ?? .distantFuture) < demoDate
    })
  #expect(
    first.workouts.allSatisfy { $0.name.hasPrefix("ДЕМО") && !$0.notes.isEmpty && $0.volume > 0 })
  #expect(first.workouts.contains { !$0.pauses.isEmpty })
  #expect(first.workouts.contains { $0.completedSets < $0.totalSets })
  #expect(try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(first)) == first)
  #expect(Set(first.workouts.flatMap { $0.exercises.map(\.id) }).count == 72)
  #expect(Set(first.workouts.flatMap { $0.exercises.flatMap { $0.sets.map(\.id) } }).count == 288)
}

@Test func demoSupportsEnglishAndCalendarDaysAcrossDST() throws {
  var calendar = demoCalendar
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let date = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 0)))
  let archive = try DemoWorkoutData.archive(
    relativeTo: date, calendar: calendar, language: .english)
  #expect(archive.workouts.allSatisfy { $0.name.hasPrefix("DEMO") })
  #expect(archive.workouts.allSatisfy { calendar.component(.hour, from: $0.startedAt) == 18 })
  #expect(archive.workouts.allSatisfy { ($0.endedAt ?? .distantFuture) < date })
  #expect(
    Set(archive.workouts.flatMap { $0.exercises.map { $0.exercise.id } })
      .isSubset(of: Set(ExerciseCatalog.all.map(\.id))))
}

@MainActor @Test func demoWorkspaceCannotOverwriteOrDeletePersonalDataEvenWithMatchingIDs() throws {
  let archive = try DemoWorkoutData.archive(relativeTo: demoDate, calendar: demoCalendar)
  let personal = MemoryWorkoutRepository()
  var own = try #require(archive.workouts.first)
  own.name = "Мои настоящие данные"
  try personal.save(own)
  let workspace = WorkoutWorkspaceRepository(personal: personal)
  try workspace.openDemo(archive)
  try workspace.deleteWorkout(id: own.id)
  #expect(try personal.workouts() == [own])
  #expect(try workspace.workouts().count == 23)
  try workspace.openDemo(archive)
  #expect(try workspace.workouts().count == 24)
  let restored = try workspace.closeDemo()
  #expect(restored.workouts == [own] && !workspace.isDemoMode)
  #expect(try workspace.workouts() == [own])
}

@MainActor @Test func demoCannotHideAnUnfinishedPersonalWorkout() throws {
  let personal = MemoryWorkoutRepository()
  let active = Workout(name: "Текущая тренировка", startedAt: demoDate)
  try personal.save(active)
  let workspace = WorkoutWorkspaceRepository(personal: personal)
  #expect(throws: TrainingError.invalidState) {
    try workspace.openDemo(DemoWorkoutData.archive(relativeTo: demoDate, calendar: demoCalendar))
  }
  #expect(!workspace.isDemoMode)
  #expect(try workspace.workouts() == [active])
}

@MainActor @Test func failedWorkspaceChangesPreserveBothPersonalAndDemoData() throws {
  let personal = FailingDemoPersonalRepository()
  let workspace = WorkoutWorkspaceRepository(personal: personal)
  let archive = try DemoWorkoutData.archive(relativeTo: demoDate, calendar: demoCalendar)
  try workspace.openDemo(archive)
  let original = try workspace.workouts()
  let duplicate = WorkoutArchive(workouts: [original[0], original[0]], templates: [])
  #expect(throws: WorkoutArchiveError.duplicateID) { try workspace.openDemo(duplicate) }
  #expect(try workspace.workouts() == original)
  personal.failRead = true
  #expect(throws: TrainingError.invalidState) { try workspace.closeDemo() }
  #expect(workspace.isDemoMode)
  #expect(try workspace.workouts() == original)
  personal.failRead = false
  _ = try workspace.closeDemo()
  #expect(!workspace.isDemoMode)
  #expect(try workspace.workouts().isEmpty)
}
