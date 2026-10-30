import Foundation
import Testing

@testable import FitnessTrackerCore

@Test func languageSelectionHonorsPreferenceOrderRegionsAndExplicitChoice() {
  #expect(AppLanguage.system.resolved(preferredLanguages: ["de-DE", "ru-RU", "en-US"]) == .russian)
  #expect(AppLanguage.system.resolved(preferredLanguages: ["en_GB", "ru"]) == .english)
  #expect(AppLanguage.russian.resolved(preferredLanguages: ["en"]) == .russian)
  #expect(AppLanguage.system.resolved(preferredLanguages: []) == .english)
  #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR"]) == .english)
  #expect(AppLanguage.english.locale(regionCode: "GB").identifier == "en_GB")
  #expect(AppLanguage.russian.locale(regionCode: "US").identifier == "ru_US")
}

@Test func pluralRulesCoverRussianTeensAndEnglishSingularWithoutIntegerOverflow() {
  for count in [1, 21, 101, -1] { #expect(AppLanguage.russian.pluralCategory(for: count) == .one) }
  for count in [2, 3, 4, 22, 104] {
    #expect(AppLanguage.russian.pluralCategory(for: count) == .few)
  }
  for count in [0, 5, 11, 12, 14, 25, 111, Int.min] {
    #expect(AppLanguage.russian.pluralCategory(for: count) == .many)
  }
  #expect(AppLanguage.english.pluralCategory(for: 1) == .one)
  #expect(AppLanguage.english.pluralCategory(for: 21) == .other)
  #expect(AppLanguage.english.pluralCategory(for: Int.min) == .other)
}

@Test func englishAndRussianLibrariesShareIdentityAndMediaWithoutChangingStoredWorkouts() throws {
  let ru = try ExerciseLibrary.entries(language: .russian)
  let en = try ExerciseLibrary.entries(language: .english)
  #expect(en.count == 100)
  #expect(en.map(\.id) == ru.map(\.id))
  #expect(en.map(\.images) == ru.map(\.images))
  #expect(en.allSatisfy { $0.name == $0.englishName && !$0.steps.isEmpty })
  let stored = Workout(
    name: "Моя тренировка", exercises: [WorkoutExercise(exercise: ru[0].exercise)])
  let localized = try #require(ExerciseLibrary.entry(for: ru[0].id, language: .english))
  #expect(localized.name == "Barbell Squat")
  #expect(stored.exercises[0].exercise.name == "Приседания")
  #expect(stored.name == "Моя тренировка")
}

@Test func englishCatalogSearchStillFindsRussianNamesAndAliases() {
  let russian = ExerciseLibrary.search(
    "Приседания", group: nil, equipment: .barbell, language: .english)
  let english = ExerciseLibrary.search(
    "Barbell Squat", group: nil, equipment: .barbell, language: .english)
  #expect(!russian.isEmpty && !english.isEmpty)
  #expect(russian.contains { $0.sourceID == "Barbell_Squat" })
  #expect(english.contains { $0.sourceID == "Barbell_Squat" })
  #expect(russian.allSatisfy { $0.name == $0.englishName })
}
