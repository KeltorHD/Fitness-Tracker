import FitnessTrackerCore
import SwiftUI

struct TemplatesView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @State private var creating = false
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 15) {
          if store.templates.isEmpty {
            ContentUnavailableView(
              L10n.text("Создайте тренировку", locale: locale), systemImage: "dumbbell",
              description: Text(
                L10n.text("Добавьте упражнения и сохраните свой шаблон.", locale: locale)))
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
      .background(FitTheme.paper).navigationTitle(L10n.text("Шаблоны", locale: locale))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            ExerciseLibraryView()
          } label: {
            Text(L10n.text("Упражнения", locale: locale)).foregroundStyle(.primary)
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Button(L10n.text("Создать тренировку", locale: locale), systemImage: "plus") {
              creating = true
            }
            NavigationLink {
              ExerciseLibraryView()
            } label: {
              Label(L10n.text("Упражнения", locale: locale), systemImage: "dumbbell")
            }
          } label: {
            Image(systemName: "ellipsis").foregroundStyle(.primary)
          }
          Button(L10n.text("Создать тренировку", locale: locale), systemImage: "plus") {
            creating = true
          }.foregroundStyle(
            .primary)
        }
      }
      .sheet(isPresented: $creating, onDismiss: { store.showingTemplateEditor = false }) {
        TemplateEditor(
          template: WorkoutTemplate(
            name: L10n.text("Новая тренировка", locale: locale), exercises: [])
        )
        .onAppear { store.showingTemplateEditor = true }
      }
    }
  }
}

struct TemplateOverviewView: View {
  @Environment(\.locale) private var locale
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
            SummaryMetric(
              title: L10n.text("Упражнения", locale: locale), value: "\(current.exercises.count)")
            SummaryMetric(
              title: L10n.text("Подходы", locale: locale),
              value: "\(current.exercises.reduce(0) { $0 + $1.setCount })")
            SummaryMetric(
              title: L10n.text("Отдых", locale: locale),
              value: L10n.format("%@ с", String(current.restSeconds), locale: locale))
          }
          ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, item in
            NavigationLink {
              ExerciseDetailView(exercise: item.exercise)
            } label: {
              HStack(alignment: .top, spacing: 14) {
                Text("\(index + 1)")
                VStack(alignment: .leading, spacing: 6) {
                  Text(L10n.exerciseName(item.exercise, locale: locale)).font(
                    .title3.weight(.medium))
                  if let plans = item.plannedSets {
                    Text(
                      WorkoutExerciseSummary.text(
                        WorkoutExercise(exercise: item.exercise, sets: plans), completedOnly: false,
                        unit: .kilograms, locale: locale, numberLocale: L10n.numberLocale)
                    ).font(.subheadline)
                  } else {
                    Text(
                      L10n.format(
                        "%@ × %@ повторений", String(item.setCount),
                        String(item.repetitions), locale: locale)
                    ).font(.subheadline)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let entry = ExerciseLibrary.entry(for: item.exercise.id) {
                  if let path = entry.generatedMedia?.poster ?? entry.images.first {
                    ExercisePhoto(path: path).frame(width: 48, height: 48).clipShape(
                      .rect(cornerRadius: 10))
                  }
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
            Button(L10n.text("Изменить", locale: locale), systemImage: "pencil") { editing = true }
            Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive) {
              confirmDelete = true
            }
          } label: {
            Image(systemName: "ellipsis")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button(L10n.text("Начать тренировку", locale: locale), systemImage: "play.fill") {
          store.start(template: current)
        }
        .font(.headline).buttonStyle(.glassProminent).controlSize(.large).padding()
      }
      .sheet(isPresented: $editing, onDismiss: { store.showingTemplateEditor = false }) {
        TemplateEditor(template: current).onAppear { store.showingTemplateEditor = true }
      }
      .confirmationDialog(
        L10n.text("Удалить шаблон?", locale: locale), isPresented: $confirmDelete,
        titleVisibility: .visible
      ) {
        Button(L10n.text("Удалить", locale: locale), role: .destructive) {
          store.delete(template: current)
          if store.error == nil { dismiss() }
        }
      }
  }
}

struct TemplateEditor: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State var template: WorkoutTemplate
  @State private var picking = false
  @State private var validationMessage: String?
  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("Название", locale: locale)) {
          TextField(L10n.text("Название плана", locale: locale), text: $template.name)
        }
        Section(L10n.text("Отдых между подходами", locale: locale)) {
          Stepper(
            L10n.format("%@ секунд", String(template.restSeconds), locale: locale),
            value: $template.restSeconds, in: 0...3600, step: 15)
        }
        ForEach($template.exercises) { $exercise in
          Section(L10n.exerciseName(exercise.exercise, locale: locale)) {
            NavigationLink(L10n.text("Техника выполнения", locale: locale)) {
              ExerciseDetailView(exercise: exercise.exercise)
            }
            if let plans = exercise.plannedSets {
              Text(
                WorkoutExerciseSummary.text(
                  WorkoutExercise(exercise: exercise.exercise, sets: plans), completedOnly: false,
                  unit: .kilograms, locale: locale, numberLocale: L10n.numberLocale))
              Text(
                L10n.text("Вес и этапы можно изменить после запуска тренировки.", locale: locale)
              ).font(.caption).foregroundStyle(.secondary)
            } else {
              Stepper(
                L10n.format("Подходы: %@", String(exercise.setCount), locale: locale),
                value: $exercise.setCount, in: 1...30)
              Stepper(
                L10n.format(
                  "Повторения: %@", String(exercise.repetitions), locale: locale),
                value: $exercise.repetitions, in: 1...1000)
              TextField(
                L10n.text("Добавленный вес, кг", locale: locale), value: $exercise.weightKG,
                format: .number
              )
              .keyboardType(.decimalPad)
            }
            Button(L10n.text("Убрать упражнение", locale: locale), role: .destructive) {
              template.exercises.removeAll { $0.id == exercise.id }
            }
          }
        }
        Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
          picking = true
        }
        if let validationMessage {
          Text(L10n.text(validationMessage, locale: locale)).foregroundStyle(.red)
        }
      }
      .navigationTitle(L10n.text("План тренировки", locale: locale)).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Сохранить", locale: locale)) {
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
      .archiveTransferPresenter(when: store.showingTemplateEditor && !picking)
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    }
  }
}
