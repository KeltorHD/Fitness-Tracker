import Foundation

public enum FitSessionCSVColumn: String, CaseIterable, Sendable {
  case date, time, workout, exercise, distance, weight, multiplier, seconds, repetitions, rest,
    skipped, note
  public var header: String {
    switch self {
    case .date: "ДАТА"
    case .time: "ВРЕМЯ"
    case .workout: "ТРЕНИРОВКА"
    case .exercise: "УПРАЖНЕНИЕ"
    case .distance: "ДИСТАНЦИЯ КМ"
    case .weight: "ВЕС КГ"
    case .multiplier: "МНОЖИТЕЛЬ"
    case .seconds: "ВРЕМЯ С"
    case .repetitions: "ПОВТОРЕНИЯ"
    case .rest: "ОТДЫХ С"
    case .skipped: "ПРОПУЩЕН"
    case .note: "ЗАМЕТКА"
    }
  }
}

public enum FitSessionCSVError: Error, Equatable, LocalizedError, Sendable {
  case invalidEncoding, missingColumns, noRecords, tooManyRows
  case malformed(line: Int)
  case invalidValue(line: Int, column: FitSessionCSVColumn)
  case unsupportedMeasurement(line: Int)
  public var errorDescription: String? {
    switch self {
    case .invalidEncoding: "Не удалось прочитать кодировку CSV. Сохраните файл в UTF-8."
    case .missingColumns: "В CSV отсутствуют необходимые столбцы журнала тренировок."
    case .noRecords: "В CSV нет тренировок для импорта."
    case .tooManyRows: "CSV содержит больше 100 000 строк. Разделите экспорт на несколько файлов."
    case .malformed: "Нарушен формат CSV: проверьте разделители и кавычки."
    case .invalidValue: "В строке CSV указано некорректное значение."
    case .unsupportedMeasurement:
      "CSV содержит подход с дистанцией или временем. Этот тип подхода пока не поддерживается."
    }
  }
}

/// Converts the two semicolon exports to the same validated, additive archive as native imports.
/// CSV local dates are Gregorian in the selected time zone; identity never depends on that zone.
public enum FitSessionCSVImporter {
  public static func decode(_ data: Data, timeZone: TimeZone = .current) throws -> WorkoutArchive {
    let rows = try SemicolonCSV.read(data)
    guard let header = rows.first else { throw FitSessionCSVError.noRecords }
    let columns = try columnMap(header.fields)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var sessions: [Workout] = []
    var indices: [UUID: Int] = [:]
    let lookup = exerciseLookup()
    for row in rows.dropFirst() {
      try Task.checkCancellation()
      guard row.fields.count == header.fields.count else {
        throw FitSessionCSVError.malformed(line: row.line)
      }
      func rawValue(_ column: FitSessionCSVColumn) -> String {
        guard let index = columns[column] else { return "" }
        return row.fields[index]
      }
      func value(_ column: FitSessionCSVColumn) -> String {
        rawValue(column).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      func invalid(_ column: FitSessionCSVColumn) -> FitSessionCSVError {
        .invalidValue(line: row.line, column: column)
      }
      guard value(.distance).isEmpty, value(.seconds).isEmpty else {
        throw FitSessionCSVError.unsupportedMeasurement(line: row.line)
      }
      let name = value(.workout)
      let exerciseName = value(.exercise)
      guard (1...80).contains(name.count) else { throw invalid(.workout) }
      guard (1...80).contains(exerciseName.count) else { throw invalid(.exercise) }
      let parsed = try date(value(.date), time: value(.time), calendar: calendar, line: row.line)
      guard let repetitions = Int(value(.repetitions)), (0...1000).contains(repetitions) else {
        throw invalid(.repetitions)
      }
      let weight = try number(value(.weight), default: 0, line: row.line, column: .weight)
      guard (0...1500).contains(weight) else { throw invalid(.weight) }
      let factor = try number(value(.multiplier), default: 1, line: row.line, column: .multiplier)
      guard (1...10).contains(factor), factor.rounded() == factor else {
        throw invalid(.multiplier)
      }
      let rest = try number(value(.rest), default: 0, line: row.line, column: .rest)
      guard (0...3600).contains(rest), rest.rounded() == rest else { throw invalid(.rest) }
      let skipped = try skipped(value(.skipped), line: row.line)
      let sessionID = StableIdentifier.uuid(
        "com.fitnesstracker.csv/workout/\(parsed.identity)/\(identityName(name))")
      let index: Int
      if let existing = indices[sessionID] {
        index = existing
      } else {
        guard sessions.count < 10_000 else { throw WorkoutArchiveError.tooManyRecords }
        index = sessions.count
        indices[sessionID] = index
        var workout = Workout(id: sessionID, name: name, startedAt: parsed.date, restSeconds: 0)
        workout.durationIsKnown = false
        sessions.append(workout)
      }
      // Rest is a target only; the CSV has no timestamps from which to invent pause intervals.
      sessions[index].restSeconds = max(sessions[index].restSeconds, Int(rest))
      let exerciseID =
        lookup[normalized(exerciseName)]?.id
        ?? StableIdentifier.uuid("com.fitnesstracker.csv/exercise/\(identityName(exerciseName))")
      var exercise =
        lookup[normalized(exerciseName)]
        ?? Exercise(id: exerciseID, name: exerciseName, muscle: .fullBody)
      exercise.name = exerciseName
      if sessions[index].exercises.last?.exercise.id != exerciseID
        || (sessions[index].exercises.last?.sets.count ?? 0) >= 30
      {
        let ordinal = sessions[index].exercises.count
        sessions[index].exercises.append(
          WorkoutExercise(
            id: StableIdentifier.uuid("\(sessionID)/row/\(ordinal)/\(exerciseID)"),
            exercise: exercise, sets: []))
      }
      let rowIndex = sessions[index].exercises.count - 1
      let rowID = sessions[index].exercises[rowIndex].id
      let ordinal = sessions[index].exercises[rowIndex].sets.count
      sessions[index].exercises[rowIndex].sets.append(
        WorkoutSet(
          id: StableIdentifier.uuid("\(rowID)/set/\(ordinal)"), repetitions: repetitions,
          weightKG: weight,
          completedAt: skipped || repetitions == 0 ? nil : parsed.date,
          loadMultiplier: factor == 1 ? nil : Int(factor)))
      var details = rawValue(.note)
      if rest > 0 {
        if !details.isEmpty { details += "\n" }
        details += "\(FitSessionCSVColumn.rest.header): \(Int(rest))"
      }
      if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let note = "\(exerciseName) [\(ordinal + 1)]: \(details)"
        if !sessions[index].notes.isEmpty { sessions[index].notes += "\n" }
        sessions[index].notes += note
      }
    }
    guard !sessions.isEmpty else { throw FitSessionCSVError.noRecords }
    for index in sessions.indices {
      if sessions[index].completedSets > 0 {
        try WorkoutEngine.finish(&sessions[index], at: sessions[index].startedAt)
      } else {
        try WorkoutEngine.cancel(&sessions[index], at: sessions[index].startedAt)
      }
    }
    // Stable export date makes importing either filename or repeating the same CSV deterministic.
    let archive = WorkoutArchive(
      workouts: sessions, templates: [], exportedAt: sessions.map(\.startedAt).max() ?? .distantPast
    )
    _ = try WorkoutArchiveCodec.encode(archive)
    try Task.checkCancellation()
    return archive
  }

  private static func columnMap(_ fields: [String]) throws -> [FitSessionCSVColumn: Int] {
    guard fields.count == FitSessionCSVColumn.allCases.count else {
      throw FitSessionCSVError.missingColumns
    }
    var map: [FitSessionCSVColumn: Int] = [:]
    for (index, name) in fields.enumerated() {
      let key = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      let column =
        key == "ПРОПУЩЕННЫЙ" ? .skipped : FitSessionCSVColumn.allCases.first { $0.header == key }
      guard let column, map[column] == nil else { throw FitSessionCSVError.missingColumns }
      map[column] = index
    }
    return map
  }
  private static func number(
    _ value: String, default fallback: Double, line: Int, column: FitSessionCSVColumn
  ) throws -> Double {
    if value.isEmpty { return fallback }
    guard let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite
    else {
      throw FitSessionCSVError.invalidValue(line: line, column: column)
    }
    return number
  }
  private static func skipped(_ value: String, line: Int) throws -> Bool {
    switch value.lowercased() {
    case "", "0", "false", "нет", "no": false
    case "1", "true", "да", "yes": true
    default: throw FitSessionCSVError.invalidValue(line: line, column: .skipped)
    }
  }
  private static func date(_ value: String, time: String, calendar: Calendar, line: Int) throws -> (
    date: Date, identity: String
  ) {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    let clock = time.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]),
      var year = Int(parts[2]),
      [2, 4].contains(parts[2].count), (2...3).contains(clock.count), let hour = Int(clock[0]),
      let minute = Int(clock[1])
    else { throw FitSessionCSVError.invalidValue(line: line, column: .date) }
    if parts[2].count == 2 { year += year >= 70 ? 1900 : 2000 }
    let second = clock.count == 3 ? Int(clock[2]) : 0
    guard let second, (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
    else {
      throw FitSessionCSVError.invalidValue(line: line, column: .time)
    }
    guard
      let date = calendar.date(
        from: DateComponents(
          year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    else {
      throw FitSessionCSVError.invalidValue(line: line, column: .date)
    }
    let actual = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    guard actual.year == year, actual.month == month, actual.day == day,
      actual.hour == hour, actual.minute == minute, actual.second == second
    else {
      throw FitSessionCSVError.invalidValue(line: line, column: .date)
    }
    return (date, "\(year)-\(month)-\(day)T\(hour):\(minute):\(second)")
  }
  private static func identityName(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping
      .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(
        separator: " ")
  }
  private static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(
      separator: " ")
  }
  private static func exerciseLookup() -> [String: Exercise] {
    var lookup: [String: Exercise] = [:]
    var ambiguous: Set<String> = []
    for entry in ExerciseLibrary.entries {
      for name in [entry.name, entry.englishName] + entry.aliases {
        let key = normalized(name)
        if key.isEmpty { continue }
        if let previous = lookup[key], previous.id != entry.id { ambiguous.insert(key) }
        lookup[key] = entry.exercise
      }
    }
    for key in ambiguous { lookup[key] = nil }
    return lookup
  }
}
