import Foundation

public enum ExerciseCatalog {
  // Stable IDs preserve record continuity across devices and releases.
  public static let all: [Exercise] = [
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Приседания",
      muscle: .legs,
      instructions:
        "Контролируйте движение и сохраняйте устойчивую опору. Используйте комфортную амплитуду."),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "Жим лёжа",
      muscle: .chest,
      instructions:
        "Удерживайте стопы на полу и контролируйте опускание снаряда. Используйте страховку."),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Тяга в наклоне",
      muscle: .back),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, name: "Жим над головой",
      muscle: .shoulders),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, name: "Румынская тяга",
      muscle: .legs),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, name: "Подтягивания",
      muscle: .back),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!, name: "Сгибания на бицепс",
      muscle: .arms),
    Exercise(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!, name: "Скручивания",
      muscle: .core),
  ]
  public static let starterTemplates: [WorkoutTemplate] = [
    WorkoutTemplate(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Всё тело · A",
      exercises: [all[0], all[1], all[2]].map { TemplateExercise(exercise: $0) }),
    WorkoutTemplate(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, name: "Всё тело · B",
      exercises: [all[4], all[3], all[5]].map { TemplateExercise(exercise: $0) }),
  ]
}
