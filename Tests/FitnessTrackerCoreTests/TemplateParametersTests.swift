import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func newTemplateUsesRestWithoutTimerAndKeepsSetTargets() throws {
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  let item = TemplateExercise(
    exercise: ExerciseCatalog.all[0], setCount: 4, repetitions: 10, weightKG: 25)
  let template = WorkoutTemplate(name: "План", exercises: [item])
  var workout = try template.start(at: date)
  #expect(workout.restSeconds == 0)
  #expect(workout.exercises[0].sets.count == 4)
  #expect(workout.exercises[0].sets.allSatisfy { $0.repetitions == 10 && $0.weightKG == 25 })
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 10, weightKG: 25, at: date)
  #expect(workout.restEndsAt == nil)
}

@Test func storedTemplateRetainsTimedRestWhenDefaultChanges() throws {
  let template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])], restSeconds: 120)
  let restored = try JSONDecoder().decode(
    WorkoutTemplate.self, from: JSONEncoder().encode(template))
  #expect(restored == template)
  let date = Date(timeIntervalSince1970: 1_790_000_000)
  var workout = try restored.start(at: date)
  try WorkoutEngine.completeSet(
    in: &workout, exerciseID: workout.exercises[0].id, setID: workout.exercises[0].sets[0].id,
    repetitions: 8, weightKG: 0, at: date)
  #expect(workout.restEndsAt == date.addingTimeInterval(120))
}
