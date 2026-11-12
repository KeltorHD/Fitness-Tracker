import Foundation
import Testing

@testable import FitLifeCore

@Test func applyingHistoryCopiesAllRecordedTargetsWithFreshIDsOnlyOnce() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let sets = [
    WorkoutSet(repetitions: 15, weightKG: 20, isWarmup: true, completedAt: date),
    WorkoutSet(repetitions: 10, weightKG: 40, completedAt: date, note: "Историческая заметка"),
    WorkoutSet(
      repetitions: 8, weightKG: 50, completedAt: date,
      dropStages: [DropSetStage(repetitions: 6, weightKG: 35, completedAt: date)]),
    WorkoutSet(repetitions: 5, weightKG: 60),
  ]
  let previous = try previousValuesFixture(
    at: date, rows: [WorkoutExercise(exercise: exercise, sets: sets)])
  let row = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
  var workout = Workout(name: "Новая", startedAt: date.addingTimeInterval(1000), exercises: [row])
  try WorkoutEngine.applyPreviousTargets(to: [row.id], in: &workout, history: [previous])
  let copied = workout.exercises[0].sets
  #expect(copied.count == 3)
  #expect(copied.map(\.repetitions) == [15, 10, 8])
  #expect(copied.map(\.weightKG) == [20, 40, 50])
  #expect(copied[0].isWarmup && copied[2].dropStages?.first?.weightKG == 35)
  #expect(copied.map(\.note) == [nil, "Историческая заметка", nil])
  #expect(workout.completedSets == 0 && workout.volume == 0 && workout.restEndsAt == nil)
  #expect(
    Set(sets.flatMap(\.stages).map(\.id)).isDisjoint(with: copied.flatMap(\.stages).map(\.id)))
  try WorkoutEngine.removeSet(exerciseID: row.id, setID: copied[2].id, from: &workout)
  let edited = workout
  try WorkoutEngine.applyPreviousTargets(to: [row.id], in: &workout, history: [previous])
  #expect(workout == edited)
  let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
  #expect(restored == workout)
}

@Test func applyingHistoryKeepsRepeatedOccurrencesAndDoesNotFillFromOlderSessions() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Тяга", muscle: .back)
  let history = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 40, completedAt: date)]),
      WorkoutExercise(
        exercise: exercise,
        sets: [
          WorkoutSet(weightKG: 55, completedAt: date), WorkoutSet(weightKG: 60, completedAt: date),
        ]),
    ])
  let rows = (0..<3).map { _ in
    WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
  }
  var current = Workout(name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: rows)
  try WorkoutEngine.applyPreviousTargets(
    to: Set(rows.map(\.id)), in: &current, history: [history])
  #expect(current.exercises.map { $0.sets.count } == [1, 2, 1])
  #expect(current.exercises[0].sets.map(\.weightKG) == [40])
  #expect(current.exercises[1].sets.map(\.weightKG) == [55, 60])
  #expect(current.exercises[2].sets[0].repetitions == 0)
}

@Test func historicalNotesKeepCurrentNotesAndRespectEditingAndClearing() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let source = WorkoutExercise(
    exercise: exercise,
    sets: [
      WorkoutSet(weightKG: 30, completedAt: date, note: "Первый подход"),
      WorkoutSet(weightKG: 40, completedAt: date, note: "Второй подход"),
      WorkoutSet(
        weightKG: 50, completedAt: date,
        dropStages: [DropSetStage(weightKG: 35, completedAt: date)], note: "Дропсет"),
    ])
  let history = try previousValuesFixture(at: date, rows: [source])
  let row = WorkoutExercise(
    exercise: exercise, sets: [WorkoutSet(repetitions: 0, note: "Заметка плана")])
  var current = Workout(name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  try WorkoutEngine.applyPreviousTargets(to: [row.id], in: &current, history: [history])
  #expect(current.exercises[0].sets.map(\.note) == ["Заметка плана", "Второй подход", "Дропсет"])
  let secondID = current.exercises[0].sets[1].id
  let thirdID = current.exercises[0].sets[2].id
  try WorkoutEngine.setNote("", exerciseID: row.id, setID: secondID, in: &current)
  try WorkoutEngine.setNote("Новая заметка", exerciseID: row.id, setID: thirdID, in: &current)
  try WorkoutEngine.applyPreviousTargets(to: [row.id], in: &current, history: [history])
  let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(current))
  #expect(restored.exercises[0].sets.map(\.note) == ["Заметка плана", nil, "Новая заметка"])
  #expect(history.exercises[0] == source)
  #expect(current.completedSets == 0)
}

@Test func historicalNotesFollowEachRepeatedExerciseOccurrence() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Тяга", muscle: .back)
  let history = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(completedAt: date, note: "Первое вхождение")]),
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(completedAt: date, note: "Второе вхождение")]),
    ])
  let rows = (0..<2).map { _ in
    WorkoutExercise(exercise: exercise, sets: [WorkoutSet(repetitions: 0)])
  }
  var current = Workout(name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: rows)
  try WorkoutEngine.applyPreviousTargets(to: Set(rows.map(\.id)), in: &current, history: [history])
  #expect(current.exercises.map { $0.sets[0].note } == ["Первое вхождение", "Второе вхождение"])
}

@Test func historicalWarmupNotesDoNotReceiveTheCurrentWorkingSetNote() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let history = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(
        exercise: exercise,
        sets: [
          WorkoutSet(isWarmup: true, completedAt: date, note: "Разминка"),
          WorkoutSet(completedAt: date, note: "Прошлый рабочий подход"),
        ])
    ])
  let row = WorkoutExercise(
    exercise: exercise, sets: [WorkoutSet(repetitions: 0, note: "План рабочего подхода")])
  var current = Workout(name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  try WorkoutEngine.applyPreviousTargets(to: [row.id], in: &current, history: [history])
  #expect(current.exercises[0].sets.map(\.note) == ["Разминка", "План рабочего подхода"])
}

private func previousValuesFixture(
  at date: Date, rows: [WorkoutExercise], id: UUID = UUID()
) throws -> Workout {
  var workout = Workout(id: id, name: "История", startedAt: date, exercises: rows)
  try WorkoutEngine.finish(&workout, at: date.addingTimeInterval(300))
  try Validation.workout(workout)
  return workout
}

@Test func previousWorkoutValuesChooseLatestEarlierCompletedSessionByExerciseIdentity() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let currentRow = WorkoutExercise(exercise: exercise)
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [currentRow])
  let old = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(weightKG: 30, completedAt: date)])
    ])
  var renamed = exercise
  renamed.name = "Новое название"
  let latestDate = date.addingTimeInterval(600)
  let latest = try previousValuesFixture(
    at: latestDate,
    rows: [
      WorkoutExercise(
        exercise: renamed,
        sets: [WorkoutSet(repetitions: 6, weightKG: 45, completedAt: latestDate)])
    ])
  let otherDate = date.addingTimeInterval(650)
  let sameName = try previousValuesFixture(
    at: otherDate,
    rows: [
      WorkoutExercise(
        exercise: Exercise(name: exercise.name, muscle: .chest),
        sets: [WorkoutSet(weightKG: 900, completedAt: otherDate)])
    ])
  var active = latest
  active.id = UUID()
  active.status = .active
  active.endedAt = nil
  var paused = active
  paused.id = UUID()
  paused.status = .paused
  paused.pausedAt = latestDate.addingTimeInterval(100)
  var cancelled = latest
  cancelled.id = UUID()
  cancelled.status = .cancelled
  let futureDate = date.addingTimeInterval(1200)
  let future = try previousValuesFixture(
    at: futureDate,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(weightKG: 900, completedAt: futureDate)])
    ])
  let overlappingDate = date.addingTimeInterval(800)
  let overlapping = try previousValuesFixture(
    at: overlappingDate,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(weightKG: 900, completedAt: overlappingDate)])
    ])
  var sameSession = latest
  sameSession.id = current.id
  let history = [
    old, future, cancelled, sameName, paused, active, overlapping, sameSession, latest,
  ]
  let values = try #require(
    PreviousWorkoutValues(exerciseRowID: currentRow.id, in: current, history: history))
  #expect(values.workoutID == latest.id)
  #expect(values.date == latestDate)
  #expect(values.stages[currentRow.sets[0].id]?.weightKG == 45)
  #expect(values.stages[currentRow.sets[0].id]?.repetitions == 6)
  #expect(current.exercises[0].sets[0].weightKG == 0)
}

@Test func previousWorkoutValuesMatchWarmupsSeparatelyAndKeepUnperformedPositions() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Присед", muscle: .legs)
  let oldRow = WorkoutExercise(
    exercise: exercise,
    sets: [
      WorkoutSet(weightKG: 15, isWarmup: true, completedAt: date),
      WorkoutSet(weightKG: 40, completedAt: date),
      WorkoutSet(weightKG: 20, isWarmup: true, completedAt: date),
      WorkoutSet(weightKG: 999),
      WorkoutSet(weightKG: 50, completedAt: date),
    ])
  let previous = try previousValuesFixture(at: date, rows: [oldRow])
  let row = WorkoutExercise(
    exercise: exercise,
    sets: [
      WorkoutSet(), WorkoutSet(isWarmup: true), WorkoutSet(), WorkoutSet(),
      WorkoutSet(isWarmup: true), WorkoutSet(), WorkoutSet(isWarmup: true),
    ])
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  let values = try #require(
    PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [previous]))
  #expect(values.stages[row.sets[0].id]?.weightKG == 40)
  #expect(values.stages[row.sets[1].id]?.weightKG == 15)
  #expect(values.stages[row.sets[2].id] == nil)
  #expect(values.stages[row.sets[3].id]?.weightKG == 50)
  #expect(values.stages[row.sets[4].id]?.weightKG == 20)
  #expect(values.stages[row.sets[5].id] == nil)
  #expect(values.stages[row.sets[6].id] == nil)
  #expect(values.stages.count == 4)
}

@Test func previousWorkoutValuesIncludeOnlyPerformedDropStagesAndPreserveZeroLoad() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Подтягивания", muscle: .back)
  let recorded = WorkoutSet(
    repetitions: 10, weightKG: 20, completedAt: date,
    dropStages: [
      DropSetStage(repetitions: 7, weightKG: 0, completedAt: date.addingTimeInterval(10))
    ])
  let incomplete = WorkoutSet(
    repetitions: 6, weightKG: 40, completedAt: date.addingTimeInterval(20),
    dropStages: [DropSetStage(repetitions: 12, weightKG: 30)])
  let previous = try previousValuesFixture(
    at: date, rows: [WorkoutExercise(exercise: exercise, sets: [recorded, incomplete])])
  let currentSet = WorkoutSet(
    weightKG: 30,
    dropStages: [DropSetStage(weightKG: 20), DropSetStage(weightKG: 10)])
  let second = WorkoutSet(weightKG: 40, dropStages: [DropSetStage(weightKG: 30)])
  let row = WorkoutExercise(exercise: exercise, sets: [currentSet, second])
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  let values = try #require(
    PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [previous]))
  #expect(values.stages[currentSet.id]?.repetitions == 10)
  #expect(values.stages[currentSet.stages[1].id]?.weightKG == 0)
  #expect(values.stages[currentSet.stages[1].id]?.repetitions == 7)
  #expect(values.stages[currentSet.stages[2].id] == nil)
  #expect(values.stages[second.id]?.weightKG == 40)
  #expect(values.stages[second.stages[1].id] == nil)
  #expect(values.stages.count == 3)
}

@Test func previousWorkoutValuesMatchRepeatedExerciseOccurrenceWithoutMergingRows() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let rows = [
    WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 40, completedAt: date)]),
    WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 30, completedAt: date)]),
  ]
  let previous = try previousValuesFixture(at: date, rows: rows)
  let currentRows = [
    WorkoutExercise(exercise: exercise), WorkoutExercise(exercise: exercise),
    WorkoutExercise(exercise: exercise),
  ]
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: currentRows)
  let first = try #require(
    PreviousWorkoutValues(exerciseRowID: currentRows[0].id, in: current, history: [previous]))
  let second = try #require(
    PreviousWorkoutValues(exerciseRowID: currentRows[1].id, in: current, history: [previous]))
  #expect(first.stages[currentRows[0].sets[0].id]?.weightKG == 40)
  #expect(second.stages[currentRows[1].sets[0].id]?.weightKG == 30)
  #expect(first.stages[currentRows[1].sets[0].id] == nil)
  #expect(
    PreviousWorkoutValues(exerciseRowID: currentRows[2].id, in: current, history: [previous]) == nil
  )
  let newerDate = date.addingTimeInterval(500)
  let newerSingleRow = try previousValuesFixture(
    at: newerDate,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(weightKG: 90, completedAt: newerDate)])
    ])
  let secondWithNewer = try #require(
    PreviousWorkoutValues(
      exerciseRowID: currentRows[1].id, in: current, history: [newerSingleRow, previous]))
  #expect(secondWithNewer.workoutID == previous.id)
}

@Test func previousWorkoutValuesUseOneSessionWithoutBackfillingExtraTargets() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Тяга", muscle: .back)
  let old = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(
        exercise: exercise,
        sets: [
          WorkoutSet(weightKG: 40, completedAt: date), WorkoutSet(weightKG: 50, completedAt: date),
        ])
    ])
  let newerDate = date.addingTimeInterval(500)
  let latest = try previousValuesFixture(
    at: newerDate,
    rows: [
      WorkoutExercise(
        exercise: exercise, sets: [WorkoutSet(weightKG: 60, completedAt: newerDate)])
    ])
  let row = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(), WorkoutSet()])
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  let values = try #require(
    PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [old, latest]))
  #expect(values.workoutID == latest.id)
  #expect(values.stages[row.sets[0].id]?.weightKG == 60)
  #expect(values.stages[row.sets[1].id] == nil)
}

@Test func previousWorkoutValuesAreDeterministicForEqualDatesAndMissingHistory() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let first = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 40, completedAt: date)])
    ], id: #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")))
  let second = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 50, completedAt: date)])
    ], id: #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002")))
  let row = WorkoutExercise(exercise: exercise)
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  let a = PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [first, second])
  let b = PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [second, first])
  #expect(a == b)
  #expect(a?.workoutID == first.id)
  #expect(PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: []) == nil)
  #expect(
    PreviousWorkoutValues(exerciseRowID: UUID(), in: current, history: [first, second]) == nil)
}

@Test func previousWorkoutValuesSkipRowsWithNoRecordedWork() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let exercise = Exercise(name: "Жим", muscle: .chest)
  let row = WorkoutExercise(exercise: exercise)
  let current = Workout(
    name: "Сейчас", startedAt: date.addingTimeInterval(1000), exercises: [row])
  let unrelated = Exercise(name: "Тяга", muscle: .back)
  let previous = try previousValuesFixture(
    at: date,
    rows: [
      WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weightKG: 999)]),
      WorkoutExercise(exercise: unrelated, sets: [WorkoutSet(weightKG: 40, completedAt: date)]),
    ])
  #expect(PreviousWorkoutValues(exerciseRowID: row.id, in: current, history: [previous]) == nil)
}
