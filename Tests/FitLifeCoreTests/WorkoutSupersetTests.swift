import Foundation
import Testing

@testable import FitLifeCore

private let supersetDate = Date(timeIntervalSince1970: 1_700_000_000)

private func groupedWorkout(firstCount: Int = 2, secondCount: Int = 2) -> Workout {
  let groupID = UUID()
  return Workout(
    name: "Ноги", startedAt: supersetDate,
    exercises: [
      WorkoutExercise(
        exercise: Exercise(name: "Квадрицепс", muscle: .legs),
        sets: (0..<firstCount).map { _ in WorkoutSet(repetitions: 10, weightKG: 40) },
        supersetID: groupID),
      WorkoutExercise(
        exercise: Exercise(name: "Задняя поверхность", muscle: .legs),
        sets: (0..<secondCount).map { _ in WorkoutSet(repetitions: 12, weightKG: 20) },
        supersetID: groupID),
      WorkoutExercise(
        exercise: Exercise(name: "Пресс", muscle: .core), sets: [WorkoutSet(repetitions: 10)]),
    ], restSeconds: 90)
}

private func record(_ workout: inout Workout, row: Int, set: Int, seconds: Double) throws {
  let exerciseID = workout.exercises[row].id
  let target = workout.exercises[row].sets[set]
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: exerciseID, setID: target.id,
    repetitions: target.repetitions, weightKG: target.weightKG,
    at: supersetDate.addingTimeInterval(seconds))
}

@Test func supersetsAlternateMembersAndStartRestOnlyAfterEveryRoundMember() throws {
  var workout = groupedWorkout()
  let first = workout.exercises[0].id
  let second = workout.exercises[1].id
  let outside = workout.exercises[2].id
  #expect(workout.exerciseGroups.count == 2)
  #expect(workout.exerciseGroups[0].roundCount == 2)
  #expect(workout.nextPendingSet?.exerciseID == first)
  try record(&workout, row: 0, set: 0, seconds: 1)
  #expect(workout.restEndsAt == nil)
  #expect(workout.nextPendingSet?.exerciseID == second)
  #expect(workout.nextPendingSet?.roundIndex == 0)
  #expect(WorkoutLiveState(workout: workout).nextExerciseName == "Задняя поверхность")
  try record(&workout, row: 1, set: 0, seconds: 2)
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(92))
  #expect(workout.nextPendingSet?.exerciseID == first)
  #expect(workout.nextPendingSet?.roundIndex == 1)
  #expect(workout.exerciseGroups[0].completedRounds == 1)
  try record(&workout, row: 0, set: 1, seconds: 3)
  #expect(workout.restEndsAt == nil)
  #expect(workout.nextPendingSet?.exerciseID == second)
  #expect(WorkoutLiveState(workout: workout).nextSetNumber == 2)
  try record(&workout, row: 1, set: 1, seconds: 4)
  #expect(workout.nextPendingSet?.exerciseID == outside)
  #expect(workout.nextPendingSet(inGroupContaining: first) == nil)
  #expect(workout.exerciseGroups[0].isCompleted)
  #expect(workout.volume == 2 * (400 + 240))
  #expect(workout.fullyCompletedSets == 4 && workout.totalSets == 5)
  #expect(WorkoutCompletionProgress(group: workout.exerciseGroups[0]).isComplete)
  try Validation.workout(workout)
}

@Test func unequalSupersetLengthsSkipOnlyMissingMembersWithoutInventingSets() throws {
  var workout = groupedWorkout(firstCount: 3, secondCount: 1)
  let first = workout.exercises[0].id
  let second = workout.exercises[1].id
  let plannedIDs = workout.exercises.flatMap(\.sets).map(\.id)
  try record(&workout, row: 0, set: 0, seconds: 1)
  #expect(workout.nextPendingSet?.exerciseID == second)
  try record(&workout, row: 1, set: 0, seconds: 2)
  #expect(workout.nextPendingSet?.exerciseID == first)
  try record(&workout, row: 0, set: 1, seconds: 100)
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(190))
  #expect(workout.nextPendingSet?.setIndex == 2)
  try record(&workout, row: 0, set: 2, seconds: 200)
  #expect(workout.exerciseGroups[0].completedRounds == 3)
  #expect(workout.exercises.flatMap(\.sets).map(\.id) == plannedIDs)
}

@Test func groupingNonAdjacentRowsKeepsRecordedWorkAndMakesOneContiguousBlock() throws {
  var workout = groupedWorkout()
  workout.exercises[0].supersetID = nil
  workout.exercises[1].supersetID = nil
  try record(&workout, row: 0, set: 0, seconds: 1)
  let before = workout.exercises
  let groupID = try WorkoutEngine.groupExercises([before[2].id, before[0].id], in: &workout)
  #expect(workout.exercises.map(\.id) == [before[0].id, before[2].id, before[1].id])
  #expect(workout.exercises.prefix(2).allSatisfy { $0.supersetID == groupID })
  #expect(workout.exercises[0].sets == before[0].sets)
  #expect(workout.restEndsAt == nil)
  try Validation.workout(workout)
  try WorkoutEngine.ungroupExercises(supersetID: groupID, in: &workout)
  #expect(workout.exercises.allSatisfy { $0.supersetID == nil })
  #expect(workout.exercises[0].sets == before[0].sets)
}

@Test func groupingExistingSupersetsMergesCompleteGroups() throws {
  var workout = groupedWorkout()
  let secondGroup = UUID()
  workout.exercises[2].supersetID = secondGroup
  workout.exercises.append(
    WorkoutExercise(
      exercise: Exercise(name: "Тяга", muscle: .back), supersetID: secondGroup))
  let ids = workout.exercises.map(\.id)
  let newID = try WorkoutEngine.groupExercises([ids[1], ids[2]], in: &workout)
  #expect(workout.exercises.map(\.id) == ids)
  #expect(workout.exercises.allSatisfy { $0.supersetID == newID })
  #expect(workout.exerciseGroups.count == 1)
  try Validation.workout(workout)
}

@Test func invalidGroupingAndGroupSplittingReorderAreAtomic() throws {
  var workout = groupedWorkout()
  let original = workout
  #expect(throws: TrainingError.invalidSuperset) {
    try WorkoutEngine.groupExercises([workout.exercises[0].id], in: &workout)
  }
  #expect(throws: TrainingError.duplicateID) {
    try WorkoutEngine.groupExercises(
      [original.exercises[0].id, original.exercises[0].id], in: &workout)
  }
  #expect(throws: TrainingError.missingExercise) {
    try WorkoutEngine.groupExercises([original.exercises[0].id, UUID()], in: &workout)
  }
  #expect(throws: TrainingError.invalidSuperset) {
    try WorkoutEngine.reorderExercises(
      [original.exercises[0].id, original.exercises[2].id, original.exercises[1].id], in: &workout)
  }
  #expect(workout == original)
  try WorkoutEngine.pause(&workout, at: supersetDate)
  let paused = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.groupExercises(Array(original.exercises.prefix(2)).map(\.id), in: &workout)
  }
  #expect(workout == paused)
}

@Test func exerciseInsertionAndRemovalPreserveValidSupersetBoundaries() throws {
  var workout = groupedWorkout()
  let firstID = workout.exercises[0].id
  let secondID = workout.exercises[1].id
  let insertion = Exercise(name: "Новое", muscle: .arms)
  try WorkoutEngine.addExercise(insertion, to: &workout, position: .after(firstID))
  #expect(workout.exercises[1].id == secondID)
  #expect(workout.exercises[2].exercise == insertion)
  try Validation.workout(workout)
  try WorkoutEngine.removeExercise(id: firstID, from: &workout)
  #expect(workout.exercises[0].id == secondID)
  #expect(workout.exercises[0].supersetID == nil)
  try Validation.workout(workout)
}

@Test func replacingARecordedSupersetMemberPreservesItsWorkAndGroup() throws {
  var workout = groupedWorkout()
  try record(&workout, row: 0, set: 0, seconds: 1)
  let original = workout.exercises[0]
  let freshID = try WorkoutEngine.replaceExercise(
    id: original.id, with: Exercise(name: "Альтернатива", muscle: .legs), in: &workout)
  #expect(workout.exercises[0] == original)
  #expect(workout.exercises[1].id == freshID)
  #expect(workout.exercises[1].supersetID == original.supersetID)
  #expect(workout.exercises[1].sets[0].completedAt == nil)
  #expect(workout.exerciseGroups[0].exercises.count == 3)
  try Validation.workout(workout)
}

@Test func supersetDropStagesStayAtomicAndDoNotStartIntermediateRest() throws {
  var workout = groupedWorkout(firstCount: 1, secondCount: 1)
  workout.exercises[0].sets[0].dropStages = [DropSetStage(repetitions: 8, weightKG: 20)]
  let row = workout.exercises[0]
  let set = row.sets[0]
  let stage = try #require(set.dropStages?.first)
  try record(&workout, row: 0, set: 0, seconds: 1)
  #expect(workout.nextPendingSet?.exerciseID == row.id)
  #expect(workout.restEndsAt == nil)
  #expect(WorkoutLiveState(workout: workout).nextDropStageNumber == 2)
  try WorkoutEngine.completeDropStage(
    in: &workout, exerciseID: row.id, setID: set.id, stageID: stage.id,
    repetitions: 8, weightKG: 20, at: supersetDate.addingTimeInterval(2))
  #expect(workout.nextPendingSet?.exerciseID == workout.exercises[1].id)
  #expect(workout.restEndsAt == nil)
  try record(&workout, row: 1, set: 0, seconds: 3)
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(93))
  #expect(WorkoutCompletionProgress(group: workout.exerciseGroups[0]).completed == 3)
}

@Test func removingAnUnperformedDropStartsRestOnlyWhenWholeSupersetRoundBecomesComplete() throws {
  var workout = groupedWorkout(firstCount: 1, secondCount: 1)
  workout.exercises[0].sets[0].dropStages = [DropSetStage(repetitions: 8, weightKG: 20)]
  try record(&workout, row: 1, set: 0, seconds: 1)
  try record(&workout, row: 0, set: 0, seconds: 2)
  #expect(workout.restEndsAt == nil)
  let row = workout.exercises[0]
  let target = row.sets[0]
  let stage = try #require(target.dropStages?.first)
  try WorkoutEngine.removeDropStage(
    in: &workout, exerciseID: row.id, setID: target.id, stageID: stage.id)
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(92))
}

@Test func repeatingAndMakingTemplatesRemapSupersetIdentityAndRemoveOrphans() throws {
  var workout = groupedWorkout()
  try record(&workout, row: 0, set: 0, seconds: 1)
  try record(&workout, row: 1, set: 0, seconds: 2)
  try WorkoutEngine.finish(&workout, at: supersetDate.addingTimeInterval(10))
  let repeated = try WorkoutEngine.repeatWorkout(workout, at: supersetDate.addingTimeInterval(20))
  let template = try WorkoutEngine.makeTemplate(from: workout)
  #expect(repeated.exercises.count == 2 && template.exercises.count == 2)
  #expect(repeated.exercises[0].supersetID != workout.exercises[0].supersetID)
  #expect(repeated.exercises[0].supersetID == repeated.exercises[1].supersetID)
  #expect(template.exercises[0].supersetID != workout.exercises[0].supersetID)
  #expect(template.exercises[0].supersetID == template.exercises[1].supersetID)
  let started = try template.start(at: supersetDate.addingTimeInterval(30), prefillTargets: false)
  #expect(started.exercises[0].supersetID != template.exercises[0].supersetID)
  #expect(started.exercises.allSatisfy { $0.sets[0].repetitions == 0 })
  try Validation.workout(repeated)
  try Validation.workout(started)

  var partial = groupedWorkout()
  try record(&partial, row: 0, set: 0, seconds: 1)
  try WorkoutEngine.finish(&partial, at: supersetDate.addingTimeInterval(2))
  #expect(try WorkoutEngine.makeTemplate(from: partial).exercises[0].supersetID == nil)
  #expect(
    try WorkoutEngine.repeatWorkout(partial, at: supersetDate.addingTimeInterval(3))
      .exercises[0].supersetID == nil)
}

@Test func combiningTemplatesDissolvesSupersetsAfterDuplicateRemoval() throws {
  let firstExercise = Exercise(name: "Первое", muscle: .legs)
  let secondExercise = Exercise(name: "Второе", muscle: .legs)
  let id = UUID()
  let single = WorkoutTemplate(name: "Один", exercises: [TemplateExercise(exercise: firstExercise)])
  let group = WorkoutTemplate(
    name: "Пара",
    exercises: [
      TemplateExercise(exercise: firstExercise, supersetID: id),
      TemplateExercise(exercise: secondExercise, supersetID: id),
    ])
  let combined = try WorkoutTemplate.start(combining: [single, group], at: supersetDate)
  #expect(combined.exercises.count == 2)
  #expect(combined.exercises.allSatisfy { $0.supersetID == nil })
  try Validation.workout(combined)
}

@Test func validationRejectsOrphanAndNonAdjacentSupersetMetadata() throws {
  var workout = groupedWorkout()
  workout.exercises[1].supersetID = nil
  #expect(throws: TrainingError.invalidSuperset) { try Validation.workout(workout) }
  workout = groupedWorkout()
  workout.exercises.swapAt(1, 2)
  #expect(throws: TrainingError.invalidSuperset) { try Validation.workout(workout) }
}

@Test func changesToOtherGroupsPreserveRestFromAnUnchangedCompletedExercise() throws {
  var workout = groupedWorkout()
  try record(&workout, row: 2, set: 0, seconds: 1)
  let deadline = workout.restEndsAt
  let first = workout.exercises[0].id
  let second = workout.exercises[1].id
  let group = try WorkoutEngine.groupExercises([first, second], in: &workout)
  #expect(workout.restEndsAt == deadline)
  try WorkoutEngine.ungroupExercises(supersetID: group, in: &workout)
  #expect(workout.restEndsAt == deadline)
  try WorkoutEngine.groupExercises([first, second], in: &workout)
  try WorkoutEngine.addSet(exerciseID: first, to: &workout)
  #expect(workout.restEndsAt == deadline)
  try WorkoutEngine.removeExercise(id: first, from: &workout)
  #expect(workout.restEndsAt == deadline)
  try Validation.workout(workout)
}

@Test func addingALaterRoundPreservesRestButGroupingAnUnfinishedMemberInvalidatesIt() throws {
  var workout = groupedWorkout()
  try record(&workout, row: 0, set: 0, seconds: 1)
  try record(&workout, row: 1, set: 0, seconds: 2)
  let deadline = workout.restEndsAt
  try WorkoutEngine.addSet(exerciseID: workout.exercises[0].id, to: &workout)
  #expect(workout.restEndsAt == deadline)
  try WorkoutEngine.groupExercises(
    [workout.exercises[0].id, workout.exercises[2].id], in: &workout)
  #expect(workout.restEndsAt == nil)
}

@Test func removingAnEarlierPendingMemberInvalidatesRestAfterItsRoundOrdinalsShift() throws {
  var workout = groupedWorkout(firstCount: 3, secondCount: 3)
  try record(&workout, row: 0, set: 1, seconds: 1)
  try record(&workout, row: 1, set: 1, seconds: 2)
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(92))
  let row = workout.exercises[0]
  try WorkoutEngine.removeSet(exerciseID: row.id, setID: row.sets[0].id, from: &workout)
  #expect(workout.restEndsAt == nil)
  #expect(workout.exercises[0].sets[0].completedAt != nil)
  #expect(workout.exercises[1].sets[1].completedAt != nil)
  try Validation.workout(workout)
}

@Test func templateFromCompletedWorkoutPreservesPlainWarmups() throws {
  var workout = groupedWorkout()
  workout.exercises[0].sets[0].isWarmup = true
  try record(&workout, row: 0, set: 0, seconds: 1)
  try record(&workout, row: 0, set: 1, seconds: 2)
  try WorkoutEngine.finish(&workout, at: supersetDate.addingTimeInterval(3))
  let template = try WorkoutEngine.makeTemplate(from: workout)
  #expect(template.exercises[0].plannedSets?[0].isWarmup == true)
  #expect(template.exercises[0].plannedSets?[1].isWarmup == false)
  let started = try template.start(at: supersetDate.addingTimeInterval(4), prefillTargets: false)
  #expect(started.exercises[0].sets[0].isWarmup)
  #expect(!started.exercises[0].sets[1].isWarmup)
  #expect(started.exercises[0].sets.allSatisfy { $0.repetitions == 0 && $0.weightKG == 0 })
}

@Test func editedWorkoutDraftsDissolveBrokenGroupsWithoutChangingRecordedData() throws {
  var workout = groupedWorkout()
  try record(&workout, row: 0, set: 0, seconds: 1)
  let rows = workout.exercises
  #expect(WorkoutExercise.normalizingSupersets(rows) == rows)
  let orphan = WorkoutExercise.normalizingSupersets([rows[0], rows[2]])
  #expect(orphan[0].supersetID == nil)
  #expect(orphan[0].sets == rows[0].sets && orphan[0].id == rows[0].id)
  let split = WorkoutExercise.normalizingSupersets([rows[0], rows[2], rows[1]])
  #expect(split.allSatisfy { $0.supersetID == nil })
  #expect(split.map(\.id) == [rows[0].id, rows[2].id, rows[1].id])
}

@Test func addingSupersetRoundCopiesEachMembersLastValuesAndPreservesRecordedWorkAndRest() throws {
  var workout = groupedWorkout()
  workout.exercises[0].sets[1].loadMultiplier = 2
  try record(&workout, row: 0, set: 0, seconds: 1)
  try record(&workout, row: 1, set: 0, seconds: 2)
  let original = workout
  let groupID = try #require(workout.exercises[0].supersetID)
  try WorkoutEngine.addSupersetRound(supersetID: groupID, to: &workout)
  #expect(workout.exercises.map { $0.sets.count } == [3, 3, 1])
  #expect(workout.restEndsAt == original.restEndsAt)
  for index in 0..<2 {
    #expect(Array(workout.exercises[index].sets.prefix(2)) == original.exercises[index].sets)
    let set = workout.exercises[index].sets[2]
    #expect(set.repetitions == original.exercises[index].sets.last?.repetitions)
    #expect(set.weightKG == original.exercises[index].sets.last?.weightKG && set.completedAt == nil)
    #expect(set.note == nil && set.dropStages == nil && !set.isWarmup)
    #expect(set.loadMultiplier == original.exercises[index].sets.last?.loadMultiplier)
  }
  #expect(workout.exercises[2] == original.exercises[2])
  #expect(workout.volume == original.volume)
  #expect(Set(workout.exercises.flatMap(\.sets).map(\.id)).count == workout.totalSets)
  try Validation.workout(workout)
}

@Test func addingSupersetRoundAlignsUnequalMembersBeforeAddingNewSharedOrdinal() throws {
  var workout = groupedWorkout(firstCount: 3, secondCount: 1)
  try record(&workout, row: 0, set: 0, seconds: 1)
  try record(&workout, row: 1, set: 0, seconds: 2)
  try record(&workout, row: 0, set: 1, seconds: 3)
  let original = workout
  #expect(workout.restEndsAt == supersetDate.addingTimeInterval(93))
  let groupID = try #require(workout.exercises[0].supersetID)
  try WorkoutEngine.addSupersetRound(supersetID: groupID, to: &workout)
  #expect(workout.exercises.map { $0.sets.count } == [4, 4, 1])
  #expect(Array(workout.exercises[0].sets.prefix(3)) == original.exercises[0].sets)
  #expect(workout.exercises[1].sets[0] == original.exercises[1].sets[0])
  #expect(
    workout.exercises[1].sets.dropFirst().allSatisfy {
      $0.repetitions == original.exercises[1].sets[0].repetitions
        && $0.weightKG == original.exercises[1].sets[0].weightKG && $0.completedAt == nil
    })
  #expect(workout.restEndsAt == nil)
  #expect(workout.nextPendingSet?.exerciseID == workout.exercises[1].id)
  #expect(workout.nextPendingSet?.roundIndex == 1)
  #expect(workout.volume == original.volume)
  try Validation.workout(workout)
}

@Test func addingSupersetRoundRejectsLimitsMissingGroupsAndInactiveStatesAtomically() throws {
  var workout = groupedWorkout(firstCount: 30, secondCount: 1)
  let original = workout
  let groupID = try #require(workout.exercises[0].supersetID)
  #expect(throws: TrainingError.invalidSetCount) {
    try WorkoutEngine.addSupersetRound(supersetID: groupID, to: &workout)
  }
  #expect(workout == original)
  #expect(throws: TrainingError.invalidSuperset) {
    try WorkoutEngine.addSupersetRound(supersetID: UUID(), to: &workout)
  }
  #expect(workout == original)
  try WorkoutEngine.pause(&workout, at: supersetDate)
  let paused = workout
  #expect(throws: TrainingError.invalidState) {
    try WorkoutEngine.addSupersetRound(supersetID: groupID, to: &workout)
  }
  #expect(workout == paused)

  var malformed = groupedWorkout()
  let malformedID = try #require(malformed.exercises[0].supersetID)
  malformed.exercises[1].supersetID = nil
  let invalid = malformed
  #expect(throws: TrainingError.invalidSuperset) {
    try WorkoutEngine.addSupersetRound(supersetID: malformedID, to: &malformed)
  }
  #expect(malformed == invalid)
}
