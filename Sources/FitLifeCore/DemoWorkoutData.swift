import Foundation

/// Explicitly synthetic journal data. No health, body measurements or sensor samples.
public enum DemoWorkoutData {
  public static func archive(
    relativeTo date: Date = Date(), calendar: Calendar = .current,
    language: AppLanguage = .russian
  ) throws -> WorkoutArchive {
    guard ExerciseCatalog.all.count >= 8, date.timeIntervalSince1970.isFinite else {
      throw TrainingError.invalidDate
    }
    let english = language.resolved() == .english
    let titles =
      english
      ? ["Full body A", "Full body B", "Upper body"]
      : ["Всё тело A", "Всё тело B", "Верх тела"]
    let prefix = english ? "DEMO · " : "ДЕМО · "
    let selections = [[0, 1, 2], [4, 3, 5], [1, 2, 6]]
    let startingWeights: [Double] = [60, 40, 25, 20, 70, 0, 10, 0]
    let templates = selections.enumerated().map { plan, indices in
      WorkoutTemplate(
        id: identifier(kind: 1, index: UInt8(plan)), name: prefix + titles[plan],
        exercises: indices.enumerated().map { row, index in
          let original = ExerciseCatalog.all[index]
          let exercise =
            ExerciseLibrary.entry(for: original.id, language: language)?.exercise ?? original
          return TemplateExercise(
            id: identifier(kind: 2, index: UInt8(plan), row: UInt8(row)),
            exercise: exercise, setCount: 4, repetitions: 8, weightKG: startingWeights[index])
        })
    }
    var workouts: [Workout] = []
    for session in 0..<24 {
      let week = session / 3
      let plan = session % 3
      let daysAgo = (7 - week) * 7 + [5, 3, 1][plan]
      guard
        let day = calendar.date(
          byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: date)),
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
      else { throw TrainingError.invalidDate }
      let rows = makeRows(template: templates[plan], session: session, week: week)
      var workout = Workout(
        id: identifier(kind: 3, index: UInt8(session)),
        name: templates[plan].name, startedAt: start, exercises: rows)
      workout.notes =
        english
        ? "Demonstration workout. These values are synthetic and are not your training history."
        : "Демонстрационная тренировка. Значения вымышлены и не относятся к вашей истории."
      var event = start.addingTimeInterval(60)
      for (rowIndex, row) in rows.enumerated() {
        for (setIndex, set) in row.sets.enumerated() {
          if session % 5 == 0 && rowIndex == 2 && setIndex == 3 { continue }
          try WorkoutEngine.completeSet(
            in: &workout, exerciseID: row.id, setID: set.id,
            repetitions: set.repetitions, weightKG: set.weightKG, at: event)
          event = event.addingTimeInterval(150)
        }
        if session % 4 == 0 && rowIndex == 0 {
          try WorkoutEngine.pause(&workout, at: event)
          event = event.addingTimeInterval(120)
          try WorkoutEngine.resume(&workout, at: event)
        }
      }
      try WorkoutEngine.finish(&workout, at: event.addingTimeInterval(300))
      workouts.append(workout)
    }
    let archive = WorkoutArchive(workouts: workouts, templates: templates, exportedAt: date)
    try WorkoutArchiveCodec.validate(archive)
    return archive
  }

  private static func identifier(kind: UInt8, index: UInt8, row: UInt8 = 0, set: UInt8 = 0) -> UUID
  {
    UUID(
      uuid: (
        0xD3, 0xA0, 0x72, 0x43, 0x51, 0xD2, 0x4A, 0x08,
        0x93, 0xFE, 0xDA, 0x7A, kind, index, row, set
      ))
  }
  private static func makeRows(template: WorkoutTemplate, session: Int, week: Int)
    -> [WorkoutExercise]
  {
    var rows: [WorkoutExercise] = []
    for (row, item) in template.exercises.enumerated() {
      let step: Double = item.weightKG < 15 ? 1 : 2.5
      let increment: Double = item.weightKG == 0 ? 0 : Double(week) * step
      var sets: [WorkoutSet] = []
      for index in 0..<4 {
        let multiplier: Double = index == 0 ? 0.5 : 1
        let set = WorkoutSet(
          id: identifier(kind: 5, index: UInt8(session), row: UInt8(row), set: UInt8(index)),
          repetitions: index == 0 ? 6 : 8 + session % 3,
          weightKG: (item.weightKG + increment) * multiplier, isWarmup: index == 0)
        sets.append(set)
      }
      rows.append(
        WorkoutExercise(
          id: identifier(kind: 4, index: UInt8(session), row: UInt8(row)),
          exercise: item.exercise, sets: sets))
    }
    return rows
  }
}
