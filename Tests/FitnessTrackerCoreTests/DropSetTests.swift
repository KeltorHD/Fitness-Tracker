import Foundation
import Testing

@testable import FitnessTrackerCore

private let dropDate = Date(timeIntervalSince1970: 1_700_000_000)
private func dropWorkout() -> Workout {
  Workout(
    name: "Drops", startedAt: dropDate,
    exercises: [
      WorkoutExercise(
        exercise: Exercise(name: "Row", muscle: .back),
        sets: [
          WorkoutSet(
            repetitions: 10, weightKG: 50, loadMultiplier: 2,
            dropStages: [
              DropSetStage(repetitions: 8, weightKG: 40),
              DropSetStage(repetitions: 6, weightKG: 30),
            ])
        ])
    ], restSeconds: 60)
}
private func completeBase(_ workout: inout Workout) throws {
  let row = try #require(workout.exercises.first)
  let set = try #require(row.sets.first)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50,
    at: dropDate.addingTimeInterval(1))
}
private func completeDrop(_ index: Int, in workout: inout Workout, seconds: Double) throws {
  let row = try #require(workout.exercises.first)
  let set = try #require(row.sets.first)
  let stage = try #require(set.dropStages?[index])
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: stage.id,
    repetitions: stage.repetitions, weightKG: stage.weightKG,
    at: dropDate.addingTimeInterval(seconds))
}

@Test func legacySetsAndTemplatesDecodeWithoutDropMetadata() throws {
  let set = WorkoutSet(weightKG: 20)
  let encoded = try JSONEncoder().encode(set)
  let decoded = try JSONDecoder().decode(WorkoutSet.self, from: encoded)
  #expect(decoded.dropStages == nil && !decoded.isDropSet && decoded == set)
  let template = TemplateExercise(exercise: Exercise(name: "Legacy", muscle: .legs))
  let restored = try JSONDecoder().decode(
    TemplateExercise.self, from: JSONEncoder().encode(template))
  #expect(restored.plannedSets == nil && restored == template)
}

@Test func dropStagesCompleteInOrderWithoutIntermediateRest() throws {
  var workout = dropWorkout()
  try Validation.workout(workout)
  #expect(workout.totalSets == 1 && workout.completedSets == 0 && workout.volume == 0)
  try completeBase(&workout)
  #expect(
    workout.restEndsAt == nil && workout.completedSets == 1 && workout.fullyCompletedSets == 0)
  #expect(workout.volume == 1000)
  try completeDrop(0, in: &workout, seconds: 2)
  #expect(workout.restEndsAt == nil && workout.volume == 1640)
  try completeDrop(1, in: &workout, seconds: 3)
  #expect(workout.restEndsAt == dropDate.addingTimeInterval(63))
  #expect(workout.fullyCompletedSets == 1 && workout.volume == 2000)
  try Validation.workout(workout)
}

@Test func dropWrongOrderAndRepeatedActionsAreRejectedWithoutMutation() throws {
  var workout = dropWorkout()
  let original = workout
  #expect(throws: TrainingError.invalidDropStageOrder) {
    try completeDrop(0, in: &workout, seconds: 1)
  }
  #expect(workout == original)
  try completeBase(&workout)
  let started = workout
  #expect(throws: TrainingError.invalidDropStageOrder) {
    try completeDrop(1, in: &workout, seconds: 2)
  }
  #expect(workout == started)
  try completeDrop(0, in: &workout, seconds: 2)
  let performed = workout
  #expect(throws: TrainingError.invalidDropStageOrder) {
    try completeDrop(0, in: &workout, seconds: 3)
  }
  #expect(workout == performed)
}

@Test func dropValidationRejectsIncreasingEmptyExcessiveWarmupAndInvalidTargets() throws {
  let set = try #require(dropWorkout().exercises.first?.sets.first)
  for weights in [
    [], [50], [51], [-1], [.nan], [40, 41], [40, 40], [0, 0], [45, 40, 35, 30, 25, 20],
  ] as [[Double]] {
    var invalid = set
    invalid.dropStages = weights.map { DropSetStage(weightKG: $0) }
    #expect(throws: TrainingError.invalidDropSet) { try Validation.set(invalid) }
  }
  var invalid = set
  invalid.isWarmup = true
  #expect(throws: TrainingError.invalidDropSet) { try Validation.set(invalid) }
  invalid = set
  invalid.dropStages?[0].repetitions = 0
  #expect(throws: TrainingError.invalidRepetitions) { try Validation.set(invalid) }
}

@Test func dropConfigurationIsAtomicAndCannotChangeStartedPausedOrCompletedSets() throws {
  var workout = dropWorkout()
  let row = try #require(workout.exercises.first)
  let set = try #require(row.sets.first)
  let original = workout
  #expect(throws: TrainingError.invalidDropSet) {
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50,
      stages: [DropSetStage(weightKG: 60)])
  }
  #expect(workout == original)
  #expect(throws: TrainingError.invalidDropSet) {
    try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: row.id, setID: set.id)
  }
  try WorkoutEngine.configureDropSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50, stages: [])
  try WorkoutEngine.setWarmup(true, in: &workout, exerciseID: row.id, setID: set.id)
  #expect(workout.exercises[0].sets[0].isWarmup && !workout.exercises[0].sets[0].isDropSet)
  workout = original
  try completeBase(&workout)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.configureDropSet(
      in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50, stages: [])
  }
  try WorkoutEngine.pause(&workout, at: dropDate.addingTimeInterval(2))
  #expect(throws: TrainingError.invalidState) { try completeDrop(0, in: &workout, seconds: 3) }
  try WorkoutEngine.finish(&workout, at: dropDate.addingTimeInterval(3))
  #expect(throws: TrainingError.invalidState) { try completeDrop(0, in: &workout, seconds: 4) }
}

@Test func dropStageIdentifiersAndDatesAreValidatedAcrossTheWholeWorkout() throws {
  var workout = dropWorkout()
  let baseID = workout.exercises[0].sets[0].id
  workout.exercises[0].sets[0].dropStages?[0].id = baseID
  #expect(throws: TrainingError.duplicateID) { try Validation.workout(workout) }
  workout = dropWorkout()
  try completeBase(&workout)
  workout.exercises[0].sets[0].dropStages?[0].completedAt = dropDate
  #expect(throws: TrainingError.invalidDropStageOrder) { try Validation.workout(workout) }
  workout = dropWorkout()
  try completeBase(&workout)
  try completeDrop(0, in: &workout, seconds: 5)
  #expect(throws: TrainingError.invalidDate) {
    try WorkoutEngine.pause(&workout, at: dropDate.addingTimeInterval(4))
  }
  #expect(throws: TrainingError.invalidDate) {
    try WorkoutEngine.finish(&workout, at: dropDate.addingTimeInterval(4))
  }
}

@Test func dropPartialFinishPreservesOnlyActualWorkAndDoesNotCompleteMissingStages() throws {
  var workout = dropWorkout()
  try completeBase(&workout)
  try completeDrop(0, in: &workout, seconds: 2)
  try WorkoutEngine.finish(&workout, at: dropDate.addingTimeInterval(3))
  try Validation.workout(workout)
  #expect(workout.completedSets == 1 && workout.fullyCompletedSets == 0 && workout.volume == 1640)
  #expect(workout.exercises[0].sets[0].dropStages?[1].completedAt == nil)
  let history = ExerciseProgressReport(workouts: [workout], now: dropDate.addingTimeInterval(10))
  let point = try #require(history.exercises.first?.points.first)
  #expect(
    point.setCount == 1 && point.repetitions == 18 && point.volume == 1640
      && point.maximumWeightKG == 50)
  #expect(
    point.estimatedOneRepMaxKG
      == TrainingStatistics.estimatedOneRepMax(weightKG: 50, repetitions: 10))
}

@Test func repeatingDropSetsGeneratesNewStageIDsAndKeepsOnlyPerformedTargets() throws {
  var workout = dropWorkout()
  try completeBase(&workout)
  try completeDrop(0, in: &workout, seconds: 2)
  try WorkoutEngine.finish(&workout, at: dropDate.addingTimeInterval(3))
  let copy = try WorkoutEngine.repeatWorkout(workout, at: dropDate.addingTimeInterval(100))
  let originalIDs = Set(workout.exercises.flatMap(\.sets).flatMap(\.stages).map(\.id))
  let newStages = copy.exercises.flatMap(\.sets).flatMap(\.stages)
  #expect(newStages.count == 2 && originalIDs.isDisjoint(with: newStages.map(\.id)))
  #expect(newStages.allSatisfy { $0.completedAt == nil })
  #expect(copy.exercises[0].sets[0].loadMultiplier == 2 && copy.volume == 0)
}

@Test func templatesPreserveMixedWarmupAndDropPlansWithoutReusingIdentifiers() throws {
  var workout = dropWorkout()
  workout.exercises[0].sets.insert(
    WorkoutSet(repetitions: 15, weightKG: 20, isWarmup: true, completedAt: dropDate), at: 0)
  let row = workout.exercises[0]
  let drop = row.sets[1]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: row.id, setID: drop.id, repetitions: 10, weightKG: 50,
    at: dropDate.addingTimeInterval(1))
  let stage = try #require(drop.dropStages?.first)
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: drop.id, stageID: stage.id, repetitions: 8,
    weightKG: 40, at: dropDate.addingTimeInterval(2))
  try WorkoutEngine.finish(&workout, at: dropDate.addingTimeInterval(3))
  let template = try WorkoutEngine.makeTemplate(from: workout)
  #expect(template.exercises[0].plannedSets?.count == 2)
  let a = try template.start(at: dropDate.addingTimeInterval(100))
  let b = try template.start(at: dropDate.addingTimeInterval(200))
  #expect(a.exercises[0].sets[0].isWarmup && a.exercises[0].sets[1].dropStages?.count == 1)
  #expect(a.exercises[0].sets[1].stages.allSatisfy { $0.completedAt == nil })
  #expect(
    Set(a.exercises.flatMap(\.sets).flatMap(\.stages).map(\.id)).isDisjoint(
      with: b.exercises.flatMap(\.sets).flatMap(\.stages).map(\.id)))
}

@Test func dropArchiveVersionFourRoundTripsAndOlderVersionsMigrate() throws {
  let archive = WorkoutArchive(workouts: [dropWorkout()], templates: [])
  #expect(archive.version == 4)
  #expect(
    try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive)).workouts == archive.workouts
  )
  let plain = WorkoutArchive(workouts: [Workout(name: "Old", startedAt: dropDate)], templates: [])
  for version in 1...3 {
    var object = try #require(
      JSONSerialization.jsonObject(with: WorkoutArchiveCodec.encode(plain)) as? [String: Any])
    object["version"] = version
    if version == 1 { object.removeValue(forKey: "bodyWeights") }
    let migrated = try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: object))
    #expect(migrated.version == 4 && migrated.workouts == plain.workouts)
  }
  var mislabeled = try #require(
    JSONSerialization.jsonObject(with: WorkoutArchiveCodec.encode(archive)) as? [String: Any])
  mislabeled["version"] = 3
  #expect(throws: WorkoutArchiveError.invalidFile) {
    try WorkoutArchiveCodec.decode(JSONSerialization.data(withJSONObject: mislabeled))
  }
}

@Test func liveStateKeepsTheCurrentDropGroupUntilItsLastStage() throws {
  var workout = dropWorkout()
  let first = WorkoutLiveState(workout: workout, at: dropDate)
  #expect(first.nextDropStageNumber == 1 && first.nextDropStageCount == 3)
  try completeBase(&workout)
  let middle = WorkoutLiveState(workout: workout, at: dropDate.addingTimeInterval(1))
  #expect(middle.nextSetNumber == 1 && middle.nextDropStageNumber == 2 && middle.completedSets == 0)
  try completeDrop(0, in: &workout, seconds: 2)
  try completeDrop(1, in: &workout, seconds: 3)
  let done = WorkoutLiveState(workout: workout, at: dropDate.addingTimeInterval(3))
  #expect(done.nextExerciseName == nil && done.nextDropStageNumber == nil && done.progress == 1)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
  object.removeValue(forKey: "nextDropStageNumber")
  object.removeValue(forKey: "nextDropStageCount")
  let legacy = try JSONDecoder().decode(
    WorkoutLiveState.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(legacy.nextDropStageNumber == nil && legacy.nextDropStageCount == nil)
}

@Test func updatingFutureDropTargetsCannotRewritePerformedStagesOrTheirDates() throws {
  var workout = dropWorkout()
  try completeBase(&workout)
  try completeDrop(0, in: &workout, seconds: 2)
  let row = workout.exercises[0]
  let set = row.sets[0]
  var targets = try #require(set.dropStages)
  let final = targets[1]
  let original = workout
  targets[0].weightKG = 39
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: set.id, stageID: final.id, repetitions: 6,
      weightKG: 20, dropStages: targets, at: dropDate.addingTimeInterval(3))
  }
  #expect(workout == original)
  targets = try #require(set.dropStages)
  targets[1].completedAt = dropDate.addingTimeInterval(3)
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.completeDropStage(
      in: &workout, exerciseID: row.id, setID: set.id, stageID: final.id, repetitions: 6,
      weightKG: 20, dropStages: targets, at: dropDate.addingTimeInterval(3))
  }
  #expect(workout == original)
  targets = try #require(set.dropStages)
  targets[1].weightKG = 20
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: final.id, repetitions: 6,
    weightKG: 20, dropStages: targets, at: dropDate.addingTimeInterval(3))
  #expect(workout.volume == 1880 && workout.fullyCompletedSets == 1)
}

@Test func finalZeroAddedLoadStageRecordsRepetitionsWithoutInventingVolume() throws {
  var workout = dropWorkout()
  let row = workout.exercises[0]
  let set = row.sets[0]
  let stage = DropSetStage(repetitions: 15, weightKG: 0)
  try WorkoutEngine.configureDropSet(
    in: &workout, exerciseID: row.id, setID: set.id, repetitions: 10, weightKG: 50, stages: [stage])
  try completeBase(&workout)
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: stage.id, repetitions: 15,
    weightKG: 0, at: dropDate.addingTimeInterval(2))
  #expect(workout.volume == 1000 && workout.exercises[0].sets[0].performedRepetitions == 25)
}
