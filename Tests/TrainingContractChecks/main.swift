import FitLifeCore
import Foundation

/// Shared by the real Swift wire codec and .NET integration tests; all data is synthetic.
@main struct TrainingContractChecks {
  enum Failure: Error { case invalidID, mismatch }
  static func id(_ number: Int) throws -> UUID {
    guard let result = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))
    else {
      throw Failure.invalidID
    }
    return result
  }

  static func fixture() throws -> [TrainingValue] {
    let start = Date(timeIntervalSince1970: 1_700_000_000.1234567)
    let exercise = try Exercise(
      id: id(1), name: "Жим 🏋️", muscle: .chest,
      instructions: "Первая строка\nВес в кг; \"заметка\".")
    let warmup = try WorkoutSet(
      id: id(10), repetitions: 5, weightKG: 20.125, isWarmup: true,
      completedAt: start.addingTimeInterval(10), note: "Разминка")
    let drop = try WorkoutSet(
      id: id(11), repetitions: 8, weightKG: 60.25, completedAt: start.addingTimeInterval(20),
      loadMultiplier: 2,
      dropStages: [
        DropSetStage(
          id: id(12), repetitions: 6, weightKG: 40, completedAt: start.addingTimeInterval(25)),
        DropSetStage(
          id: id(13), repetitions: 4, weightKG: 20, completedAt: start.addingTimeInterval(30)),
      ], note: "Рабочий подход 🟠")
    let pending = try WorkoutSet(id: id(14), repetitions: 0, weightKG: 0, note: "")
    let row = try WorkoutExercise(
      id: id(20), exercise: exercise, sets: [warmup, drop, pending], supersetID: id(30))
    let second = try WorkoutExercise(
      id: id(21), exercise: exercise,
      sets: [
        WorkoutSet(
          id: id(15), repetitions: 10, weightKG: 0, completedAt: start.addingTimeInterval(40),
          loadMultiplier: 1)
      ],
      supersetID: id(30))
    var completed = try Workout(
      id: id(100), name: "Тренировка со всеми подходами", startedAt: start,
      exercises: [row, second], restSeconds: 75, bodyWeightKG: 80.125)
    completed.status = .completed
    completed.endedAt = start.addingTimeInterval(200)
    completed.pauses = [
      WorkoutPause(
        startedAt: start.addingTimeInterval(50), endedAt: start.addingTimeInterval(65.125))
    ]
    completed.pausedSeconds = 15.125
    completed.notes = "Личная заметка\nСуперсет и дроп-сет."
    completed.durationIsKnown = true
    var paused = try Workout(
      id: id(101), name: "Пауза и незаполненный подход", startedAt: start.addingTimeInterval(600),
      exercises: [
        WorkoutExercise(
          id: id(22), exercise: Exercise(id: exercise.id, name: "Изменённое имя", muscle: .chest),
          sets: [WorkoutSet(id: id(16), repetitions: 0)])
      ], restSeconds: 0)
    paused.status = .paused
    paused.pausedAt = start.addingTimeInterval(620.0625)
    var active = try Workout(
      id: id(102), name: "Текущий отдых", startedAt: start.addingTimeInterval(900))
    active.restEndsAt = start.addingTimeInterval(1000)
    var unknown = try Workout(
      id: id(103), name: "Импорт без длительности", startedAt: start.addingTimeInterval(1200),
      exercises: [
        WorkoutExercise(
          id: id(23), exercise: exercise,
          sets: [
            WorkoutSet(id: id(17), repetitions: 12, completedAt: start.addingTimeInterval(1200))
          ])
      ])
    unknown.status = .completed
    unknown.endedAt = unknown.startedAt
    unknown.durationIsKnown = false

    var targetWarmup = warmup
    targetWarmup.id = try id(300)
    targetWarmup.completedAt = nil
    let targetDrop = try WorkoutSet(
      id: id(301), repetitions: 8, weightKG: 60, loadMultiplier: 2,
      dropStages: [DropSetStage(id: id(302), repetitions: 5, weightKG: 30)], note: "План подхода")
    let firstPlan = try TemplateExercise(
      id: id(200), exercise: exercise, setCount: 2, repetitions: 8, weightKG: 60, loadMultiplier: 2,
      plannedSets: [targetWarmup, targetDrop], supersetID: id(250))
    let secondPlan = try TemplateExercise(
      id: id(201), exercise: exercise, setCount: 3, repetitions: 10, weightKG: 0,
      supersetID: id(250))
    let variation = try WorkoutTemplateVariation(
      id: id(260), name: "Вариант 🟠",
      exercises: [
        TemplateExercise(
          id: id(202), exercise: exercise, setCount: 1, repetitions: 15, weightKG: 12.5)
      ])
    let template = try WorkoutTemplate(
      id: id(500), name: "План с вариантами", exercises: [firstPlan, secondPlan], restSeconds: 120,
      muscleGroups: [.chest, .arms], muscles: [.chest, .biceps],
      preferredWeekdays: [.monday, .friday],
      variations: [variation], baseVariationName: "Базовый вариант",
      muscleRegions: [.chestUpper, .bicepsLong])
    let live = try HeartRateRecording(
      workoutID: completed.id, mode: .appleHealth,
      readings: [
        HeartRateReading(date: start.addingTimeInterval(5.1234567), beatsPerMinute: 93.125),
        HeartRateReading(date: start.addingTimeInterval(11.5), beatsPerMinute: 105.75),
      ], origin: .liveHealthKit)
    let bluetooth = try HeartRateRecording(
      workoutID: paused.id, mode: .bluetooth,
      readings: [
        HeartRateReading(date: start.addingTimeInterval(602), beatsPerMinute: 87),
        HeartRateReading(date: start.addingTimeInterval(607.25), beatsPerMinute: 101),
      ])
    let values: [TrainingValue] = [
      .workout(completed), .workout(paused), .workout(active), .workout(unknown),
      .template(template),
      .bodyWeight(
        try BodyWeightEntry(
          id: id(600), measuredAt: start, weightKG: 80.125, workoutID: completed.id)),
      .bodyWeight(
        try BodyWeightEntry(
          id: id(601), measuredAt: start.addingTimeInterval(20), weightKG: 79.75, workoutID: id(999)
        )),
      .heartRate(live), .heartRate(bluetooth),
    ]
    for value in values {
      try value.validate()
      let data = try value.canonicalData()
      guard try TrainingCoding.decoder().decode(TrainingValue.self, from: data) == value else {
        throw Failure.mismatch
      }
    }
    return values
  }

  static func main() throws {
    let values = try fixture()
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else { throw Failure.mismatch }
    let path = URL(fileURLWithPath: arguments[2])
    let data = try TrainingCoding.encoder().encode(values)
    switch arguments[1] {
    case "--write": try data.write(to: path, options: .atomic)
    case "--verify":
      guard try Data(contentsOf: path) == data else { throw Failure.mismatch }
    case "--verify-server":
      let page = try TrainingCoding.decoder().decode(
        TrainingPage.self, from: Data(contentsOf: path))
      try page.validate(after: 0)
      guard page.changes.compactMap(\.value) == values else { throw Failure.mismatch }
    default: throw Failure.mismatch
    }
    print(
      "Training contract: all workout/template/set/pause/weight/pulse fields and fractional dates preserved."
    )
  }
}
