import Foundation
import Testing

@testable import FitnessTrackerCore

private func scheduleCalendar(_ zone: String = "UTC", firstWeekday: Int = 2) throws -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: zone))
  calendar.firstWeekday = firstWeekday
  return calendar
}

private func scheduleDate(_ value: String) throws -> Date {
  try #require(ISO8601DateFormatter().date(from: value))
}

private func scheduledTemplate(_ name: String, days: Set<WorkoutWeekday> = []) -> WorkoutTemplate {
  WorkoutTemplate(
    name: name, exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
    preferredWeekdays: days)
}

@Test func trainingDaysPartitionTemplatesWithoutDuplicatesAndPreserveRelativeOrder() throws {
  let monday = scheduledTemplate("Понедельник", days: [.monday, .wednesday])
  let unscheduled = scheduledTemplate("Без дней")
  let friday = scheduledTemplate("Пятница", days: [.friday])
  let anotherMonday = scheduledTemplate("Ещё один", days: [.monday])
  let templates = [unscheduled, monday, friday, anotherMonday]
  let suggestions = WorkoutTemplateSuggestions(
    templates: templates, date: try scheduleDate("2026-11-02T12:00:00Z"),
    calendar: try scheduleCalendar())
  #expect(suggestions.today == [monday, anotherMonday])
  #expect(suggestions.others == [unscheduled, friday])
  #expect(Set(suggestions.today.map(\.id)).isDisjoint(with: suggestions.others.map(\.id)))
  #expect(suggestions.today.count + suggestions.others.count == templates.count)
  // Day preferences do not restrict starting a template on another day.
  #expect(try friday.start().exercises.count == 1)
}

@Test func templateSuggestionsSupportUnscheduledEmptyAndAllTodayLists() throws {
  let date = try scheduleDate("2026-11-02T12:00:00Z")
  let calendar = try scheduleCalendar()
  let noDays = scheduledTemplate("Любой день")
  let friday = scheduledTemplate("Пятница", days: [.friday])
  let unmatched = WorkoutTemplateSuggestions(
    templates: [noDays, friday], date: date, calendar: calendar)
  #expect(unmatched.today.isEmpty)
  #expect(unmatched.others == [noDays, friday])
  let empty = WorkoutTemplateSuggestions(templates: [], date: date, calendar: calendar)
  #expect(empty.today.isEmpty && empty.others.isEmpty)
  let daily = scheduledTemplate("Каждый день", days: Set(WorkoutWeekday.allCases))
  let today = WorkoutTemplateSuggestions(templates: [daily], date: date, calendar: calendar)
  #expect(today.today == [daily] && today.others.isEmpty)
}

@Test func preferredDaysUseLocalWeekdayAcrossTimeZonesAndWeekBoundaries() throws {
  let monday = scheduledTemplate("Понедельник", days: [.monday])
  let sunday = scheduledTemplate("Воскресенье", days: [.sunday])
  let instant = try scheduleDate("2026-11-01T23:30:00Z")
  let utc = WorkoutTemplateSuggestions(
    templates: [monday, sunday], date: instant, calendar: try scheduleCalendar())
  let tokyo = WorkoutTemplateSuggestions(
    templates: [monday, sunday], date: instant, calendar: try scheduleCalendar("Asia/Tokyo"))
  #expect(utc.today == [sunday])
  #expect(tokyo.today == [monday])
  let mondayFirst = try scheduleCalendar(firstWeekday: 2)
  let sundayFirst = try scheduleCalendar(firstWeekday: 1)
  #expect(WorkoutWeekday.ordered(in: mondayFirst).first == .monday)
  #expect(WorkoutWeekday.ordered(in: sundayFirst).first == .sunday)
  let reordered = WorkoutTemplateSuggestions(
    templates: [monday, sunday], date: instant, calendar: sundayFirst)
  #expect(reordered == utc)
}

@Test func preferredDaysRespectDSTAndLocalMidnight() throws {
  let calendar = try scheduleCalendar("America/New_York")
  let sunday = scheduledTemplate("Воскресенье", days: [.sunday])
  let monday = scheduledTemplate("Понедельник", days: [.monday])
  // Spring-forward Sunday has 23 hours. Its end must not be inferred by adding 86400 seconds.
  for value in ["2026-03-08T06:59:00Z", "2026-03-08T07:01:00Z", "2026-03-09T03:59:00Z"] {
    let suggestions = WorkoutTemplateSuggestions(
      templates: [monday, sunday], date: try scheduleDate(value), calendar: calendar)
    #expect(suggestions.today == [sunday])
  }
  let nextDay = WorkoutTemplateSuggestions(
    templates: [monday, sunday], date: try scheduleDate("2026-03-09T04:00:00Z"), calendar: calendar)
  #expect(nextDay.today == [monday])
}

@Test @MainActor func templateTrainingDaysSurviveArchiveAndRepositoryAndCanBeCleared() throws {
  var template = scheduledTemplate("План", days: [.monday, .friday, .sunday])
  template.muscleGroups = [.chest, .arms]
  template.restSeconds = 120
  let archive = WorkoutArchive(workouts: [], templates: [template])
  let restored = try WorkoutArchiveCodec.decode(WorkoutArchiveCodec.encode(archive))
  #expect(restored.templates == [template])
  let repository = MemoryWorkoutRepository()
  try repository.saveTemplate(try #require(restored.templates.first))
  #expect(try repository.templates() == [template])
  template.preferredWeekdays = []
  try repository.saveTemplate(template)
  #expect(try repository.templates() == [template])
}

@Test func templatesWithoutTrainingDaysKeepTheirIdentityAndTargets() throws {
  let template = scheduledTemplate("Старый шаблон")
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
  object.removeValue(forKey: "preferredWeekdays")
  let data = try JSONSerialization.data(withJSONObject: object)
  let restored = try JSONDecoder().decode(WorkoutTemplate.self, from: data)
  #expect(restored == template)
  #expect(restored.preferredWeekdays.isEmpty)
  object.removeValue(forKey: "muscleGroups")
  let originalFormat = try JSONDecoder().decode(
    WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(originalFormat == template)
}

@Test func templateSearchMatchesTemplateExerciseAndEnglishNamesWithoutChangingRecords() throws {
  let date = try scheduleDate("2026-11-02T12:00:00Z")
  let calendar = try scheduleCalendar()
  let template = WorkoutTemplate(
    name: "Силовая А", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
    preferredWeekdays: [.monday])
  var filter = WorkoutTemplateFilter()
  for query in ["силовая", "ПРИСЕДАНИЯ", "Barbell Squat", " силовая   приседания "] {
    filter.query = query
    let result = filter.apply(to: [template], date: date, calendar: calendar)
    #expect(result.today == [template] && result.others.isEmpty)
  }
  filter.query = "несуществующий шаблон"
  let noMatches = filter.apply(to: [template], date: date, calendar: calendar)
  #expect(noMatches.today.isEmpty && noMatches.others.isEmpty)
  #expect(template.preferredWeekdays == [.monday])
}

@Test func templateScheduleFiltersRespectLocalDayAndUnscheduledPlans() throws {
  let monday = scheduledTemplate("Понедельник", days: [.monday])
  let sunday = scheduledTemplate("Воскресенье", days: [.sunday])
  let unscheduled = scheduledTemplate("Без расписания")
  let date = try scheduleDate("2026-11-01T23:30:00Z")
  var filter = WorkoutTemplateFilter()
  filter.schedule = .today
  let utc = filter.apply(
    to: [monday, unscheduled, sunday], date: date, calendar: try scheduleCalendar())
  #expect(utc.today == [sunday] && utc.others.isEmpty)
  let tokyo = filter.apply(
    to: [monday, unscheduled, sunday], date: date, calendar: try scheduleCalendar("Asia/Tokyo"))
  #expect(tokyo.today == [monday] && tokyo.others.isEmpty)
  filter.schedule = .unscheduled
  let onlyUnscheduled = filter.apply(
    to: [monday, unscheduled, sunday], date: date, calendar: try scheduleCalendar())
  #expect(onlyUnscheduled.today.isEmpty && onlyUnscheduled.others == [unscheduled])
}

@Test func templateMuscleFiltersUseExplicitTargetsAndInferLegacyExerciseMuscles() throws {
  var explicit = scheduledTemplate("Бицепс")
  explicit.muscleSelection = ExerciseMuscleSelection(muscles: [.biceps])
  let legacyLegs = scheduledTemplate("Ноги")
  var filter = WorkoutTemplateFilter()
  filter.muscles = ExerciseMuscleSelection(groups: [.arms])
  let date = try scheduleDate("2026-11-02T12:00:00Z")
  let calendar = try scheduleCalendar()
  #expect(
    filter.apply(to: [explicit, legacyLegs], date: date, calendar: calendar).others == [explicit])
  filter.muscles = ExerciseMuscleSelection(muscles: [.quadriceps])
  #expect(
    filter.apply(to: [explicit, legacyLegs], date: date, calendar: calendar).others == [legacyLegs])
  let custom = WorkoutTemplate(
    name: "Своё упражнение",
    exercises: [TemplateExercise(exercise: Exercise(name: "Своё", muscle: .arms))])
  filter.muscles = ExerciseMuscleSelection(muscles: [.biceps])
  #expect(filter.apply(to: [custom], date: date, calendar: calendar).others.isEmpty)
  filter.muscles = ExerciseMuscleSelection(groups: [.arms])
  #expect(filter.apply(to: [custom], date: date, calendar: calendar).others == [custom])
}

@Test func templateFiltersCombineEquipmentSearchScheduleAndPreserveGroupOrder() throws {
  let monday = WorkoutTemplate(
    name: "Силовая", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
    preferredWeekdays: [.monday])
  let other = WorkoutTemplate(name: "Другой день", exercises: monday.exercises)
  var filter = WorkoutTemplateFilter()
  filter.query = "присед"
  filter.schedule = .today
  filter.equipment = [.barbell, .dumbbell]
  filter.muscles = ExerciseMuscleSelection(groups: [.legs])
  #expect(filter.isActive && filter.hasFilters)
  let date = try scheduleDate("2026-11-02T12:00:00Z")
  let calendar = try scheduleCalendar()
  let matching = filter.apply(to: [other, monday], date: date, calendar: calendar)
  #expect(matching.today == [monday] && matching.others.isEmpty)
  filter.equipment = [.bands]
  let empty = filter.apply(to: [other, monday], date: date, calendar: calendar)
  #expect(empty.today.isEmpty && empty.others.isEmpty)
  filter = WorkoutTemplateFilter()
  #expect(!filter.isActive && !filter.hasFilters)
  let all = filter.apply(to: [other, monday], date: date, calendar: calendar)
  #expect(all.today == [monday] && all.others == [other])
}
