import Foundation
import Testing

@testable import FitLifeCore

@Test func personalExercisesIncludeWorkoutsAndTemplateVariationsWithoutCatalogDuplicates() {
  let first = Exercise(name: "Жим из импорта", muscle: .chest)
  let second = Exercise(name: "Другая тяга", muscle: .back)
  let known = ExerciseCatalog.all[0]
  let workout = Workout(
    name: "Тренировка", startedAt: .now,
    exercises: [WorkoutExercise(exercise: first), WorkoutExercise(exercise: known)])
  let template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: first)],
    variations: [
      WorkoutTemplateVariation(name: "Вариант", exercises: [TemplateExercise(exercise: second)])
    ])
  let personal = PersonalExercises.list(workouts: [workout], templates: [template])
  #expect(Set(personal.map(\.id)) == [first.id, second.id])
}

@Test func linkingMergesProgressButPreservesHistoricalWorkoutRows() throws {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let catalog = try #require(ExerciseLibrary.entries.first?.exercise)
  let imported = Exercise(name: "Мой вариант", muscle: catalog.muscle)
  let link = ExerciseLink(id: imported.id, catalogID: catalog.id)
  try link.validate()
  var workout = Workout(
    name: "Тренировка", startedAt: date,
    exercises: [
      WorkoutExercise(
        exercise: imported, sets: [WorkoutSet(repetitions: 5, weightKG: 20, completedAt: date)]),
      WorkoutExercise(
        exercise: catalog, sets: [WorkoutSet(repetitions: 4, weightKG: 30, completedAt: date)]),
    ])
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(1))
  let original = workout
  let report = ExerciseProgressReport(
    workouts: [workout], now: date.addingTimeInterval(2), links: [link])
  let history = try #require(report.exercises.first)
  #expect(report.exercises.count == 1)
  #expect(history.exercise.id == catalog.id)
  #expect(history.points.first?.volume == 220)
  #expect(history.points.first?.setCount == 2)
  let rows = ExerciseWorkoutHistoryEntry.entries(
    for: imported.id, workouts: [workout], now: date.addingTimeInterval(2), links: [link])
  #expect(rows.first?.rows.map(\.name) == [imported.name, catalog.name])
  #expect(workout == original)
  #expect(
    ExerciseProgressReport(workouts: [workout], now: date.addingTimeInterval(2)).exercises.count
      == 2)
  #expect(throws: TrainingSyncError.self) {
    try ExerciseLink(id: catalog.id, catalogID: catalog.id).validate()
  }
  let records = TrainingStatistics.records(in: [workout], links: [link])
  #expect(records.count == 1 && records.first?.exercise.id == catalog.id)
  #expect(records.first?.weightKG == 30)
  let reportForMonth = TrainingReport(
    workouts: [workout], month: date, now: date.addingTimeInterval(2), links: [link])
  #expect(reportForMonth.exerciseVolumes[catalog.id]?.first?.volume == 220)
  var next = Workout(
    name: "Следующая", startedAt: date.addingTimeInterval(60),
    exercises: [WorkoutExercise(exercise: catalog, sets: [WorkoutSet(repetitions: 0)])])
  try WorkoutEngine.applyPreviousTargets(
    to: [next.exercises[0].id], in: &next, history: [workout], links: [link])
  #expect(next.exercises[0].sets.first?.weightKG == 20)
}

@Test @MainActor func exerciseLinksFollowAccountsAndSyncChanges() throws {
  let repository = MemoryWorkoutRepository()
  let source = UUID()
  let catalog = try #require(ExerciseLibrary.entries.first)
  let link = ExerciseLink(id: source, catalogID: catalog.id)
  try repository.saveExerciseLink(link)
  try repository.activateTrainingAccount("account-a")
  #expect(try repository.exerciseLinks() == [link])
  try repository.activateTrainingAccount("account-b")
  #expect(try repository.exerciseLinks().isEmpty)
  let change = try TrainingChange(
    key: TrainingRecordKey(kind: .exerciseLink, id: source), revision: 1,
    value: .exerciseLink(link))
  let decoded = try TrainingCoding.decoder().decode(
    TrainingChange.self, from: TrainingCoding.encoder().encode(change))
  try repository.applyTrainingChanges([decoded])
  #expect(try repository.exerciseLinks() == [link])
  try repository.applyTrainingChanges([
    TrainingChange(key: change.key, revision: 2, value: nil)
  ])
  #expect(try repository.exerciseLinks().isEmpty)
  try repository.activateTrainingAccount("account-a")
  #expect(try repository.exerciseLinks() == [link])
}

@Test @MainActor func exerciseLinksStayIsolatedFromDemoWorkspace() throws {
  let personal = MemoryWorkoutRepository()
  let link = ExerciseLink(id: UUID(), catalogID: try #require(ExerciseLibrary.entries.first?.id))
  try personal.saveExerciseLink(link)
  let workspace = WorkoutWorkspaceRepository(personal: personal)
  try workspace.openDemo(WorkoutArchive(workouts: [], templates: []))
  #expect(try workspace.exerciseLinks().isEmpty)
  #expect(try workspace.personalExerciseLinks() == [link])
  _ = try workspace.closeDemo()
  #expect(try workspace.exerciseLinks() == [link])
}
