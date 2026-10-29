import FitSessionCore
import SwiftUI

struct TemplatesView: View {
  @Environment(AppStore.self) private var store
  @State private var creating = false
  @State private var editing: WorkoutTemplate?
  var body: some View {
    NavigationStack {
      List {
        if store.templates.isEmpty {
          ContentUnavailableView(
            "Создайте свой план", systemImage: "square.grid.2x2",
            description: Text("Соберите упражнения в шаблон для следующей тренировки."))
        }
        ForEach(store.templates) { template in
          VStack(alignment: .leading, spacing: 12) {
            Text(template.name).font(.headline)
            Text(template.exercises.map(\.exercise.name).joined(separator: " · "))
              .font(.subheadline).foregroundStyle(.secondary)
            HStack {
              Button("Начать", systemImage: "play.fill") { store.start(template: template) }
                .buttonStyle(.glassProminent)
              Button("Изменить", systemImage: "pencil") { editing = template }.buttonStyle(.glass)
            }
          }.padding(.vertical, 8)
            .swipeActions {
              Button("Удалить", role: .destructive) { store.delete(template: template) }
            }
        }
      }
      .navigationTitle("Планы")
      .toolbar { Button("Создать план", systemImage: "plus") { creating = true } }
      .sheet(isPresented: $creating) {
        TemplateEditor(template: WorkoutTemplate(name: "Новый план", exercises: []))
      }
      .sheet(item: $editing) { TemplateEditor(template: $0) }
    }
  }
}

struct TemplateEditor: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State var template: WorkoutTemplate
  @State private var picking = false
  @State private var validationMessage: String?
  var body: some View {
    NavigationStack {
      Form {
        Section("Название") { TextField("Название плана", text: $template.name) }
        Section("Отдых между подходами") {
          Stepper(
            "\(template.restSeconds) секунд", value: $template.restSeconds, in: 0...3600, step: 15)
        }
        ForEach($template.exercises) { $exercise in
          Section(exercise.exercise.name) {
            NavigationLink("Техника выполнения") { ExerciseDetailView(exercise: exercise.exercise) }
            Stepper("Подходы: \(exercise.setCount)", value: $exercise.setCount, in: 1...30)
            Stepper(
              "Повторения: \(exercise.repetitions)", value: $exercise.repetitions, in: 1...1000)
            TextField("Добавленный вес, кг", value: $exercise.weightKG, format: .number)
              .keyboardType(.decimalPad)
            Button("Убрать упражнение", role: .destructive) {
              template.exercises.removeAll { $0.id == exercise.id }
            }
          }
        }
        Button("Добавить упражнение", systemImage: "plus") { picking = true }
        if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
      }
      .navigationTitle("План тренировки").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Сохранить") {
            do {
              try Validation.template(template)
              if store.save(template: template) {
                dismiss()
              } else {
                validationMessage = store.error
              }
            } catch { validationMessage = error.localizedDescription }
          }
        }
      }
      .sheet(isPresented: $picking) {
        ExercisePicker { template.exercises.append(TemplateExercise(exercise: $0)) }
      }
    }
  }
}
