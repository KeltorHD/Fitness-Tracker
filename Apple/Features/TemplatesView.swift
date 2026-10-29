import FitSessionCore
import SwiftUI

struct TemplatesView: View {
  @Environment(AppStore.self) private var store
  @State private var creating = false
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 15) {
          if store.templates.isEmpty {
            ContentUnavailableView(
              "Создайте тренировку", systemImage: "dumbbell",
              description: Text("Добавьте упражнения и сохраните свой шаблон."))
          }
          ForEach(store.templates) { template in
            NavigationLink {
              TemplateOverviewView(template: template)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(
                  FitTheme.accent)
                Text(template.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
              }.padding(.horizontal, 18).padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FitTheme.card, in: .capsule)
            }.buttonStyle(.plain)
          }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
      }
      .background(FitTheme.paper).navigationTitle("Тренировки")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            ExerciseLibraryView()
          } label: {
            Text("Упражнения").foregroundStyle(.primary)
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Button("Создать тренировку", systemImage: "plus") { creating = true }
            NavigationLink {
              ExerciseLibraryView()
            } label: {
              Label("Упражнения", systemImage: "dumbbell")
            }
          } label: {
            Image(systemName: "ellipsis").foregroundStyle(.primary)
          }
          Button("Создать тренировку", systemImage: "plus") { creating = true }.foregroundStyle(
            .primary)
        }
      }
      .sheet(isPresented: $creating) {
        TemplateEditor(template: WorkoutTemplate(name: "Новая тренировка", exercises: []))
      }
    }
  }
}

struct TemplateOverviewView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var editing = false
  @State private var confirmDelete = false
  let template: WorkoutTemplate
  private var current: WorkoutTemplate {
    store.templates.first { $0.id == template.id } ?? template
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        WorkoutHero(title: current.name)
        VStack(spacing: 20) {
          HStack(spacing: 8) {
            SummaryMetric(title: "Упражнения", value: "\(current.exercises.count)")
            SummaryMetric(
              title: "Подходы", value: "\(current.exercises.reduce(0) { $0 + $1.setCount })")
            SummaryMetric(title: "Отдых", value: "\(current.restSeconds) с")
          }
          ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, item in
            NavigationLink {
              ExerciseDetailView(exercise: item.exercise)
            } label: {
              HStack(alignment: .top, spacing: 14) {
                Text("\(index + 1)")
                VStack(alignment: .leading, spacing: 6) {
                  Text(item.exercise.name).font(.title3.weight(.medium))
                  Text("\(item.setCount) × \(item.repetitions) повторений").font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let entry = ExerciseLibrary.entry(for: item.exercise.id) {
                  ExercisePhoto(path: entry.images[0]).frame(width: 48, height: 48).clipShape(
                    .rect(cornerRadius: 10))
                }
              }.foregroundStyle(.primary)
            }
            Divider().padding(.leading, 28)
          }
        }.padding(16)
      }
    }.background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Изменить", systemImage: "pencil") { editing = true }
            Button("Удалить", systemImage: "trash", role: .destructive) { confirmDelete = true }
          } label: {
            Image(systemName: "ellipsis")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button("Начать тренировку", systemImage: "play.fill") { store.start(template: current) }
          .font(.headline).buttonStyle(.glassProminent).controlSize(.large).padding()
      }
      .sheet(isPresented: $editing) { TemplateEditor(template: current) }
      .confirmationDialog("Удалить шаблон?", isPresented: $confirmDelete, titleVisibility: .visible)
    {
      Button("Удалить", role: .destructive) {
        store.delete(template: current)
        if store.error == nil { dismiss() }
      }
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
