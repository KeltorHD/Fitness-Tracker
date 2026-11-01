import FitnessTrackerCore
import SwiftUI

struct TemplatesView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @State private var creating = false
  @State private var deleting: WorkoutTemplate?
  var body: some View {
    NavigationStack {
      List {
        if store.templates.isEmpty {
          ContentUnavailableView(
            L10n.text("Создайте тренировку", locale: locale), systemImage: "dumbbell",
            description: Text(
              L10n.text("Добавьте упражнения и сохраните свой шаблон.", locale: locale))
          ).cardListRow()
        }
        ForEach(store.templates) { template in
          NavigationLink {
            TemplateOverviewView(template: template)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(
                colorTheme.accent)
              VStack(alignment: .leading, spacing: 4) {
                Text(template.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                TemplateMuscleGroups(template: template)
              }
              Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 20)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(FitTheme.card, in: .capsule)
          }
          .buttonStyle(.plain).cardListRow()
          .accessibilityIdentifier("templateRow_\(template.id)")
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
              deleting = template
            } label: {
              Label(L10n.text("Удалить", locale: locale), systemImage: "trash")
            }.tint(.red)
              .accessibilityIdentifier("swipeDeleteTemplate_\(template.id)")
          }
          .contextMenu {
            Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive) {
              deleting = template
            }
          }
        }
      }
      .listStyle(.plain).scrollContentBackground(.hidden)
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
      .confirmationDialog(
        L10n.text("Удалить шаблон?", locale: locale),
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
        titleVisibility: .visible
      ) {
        Button(L10n.text("Удалить", locale: locale), role: .destructive) {
          let template = deleting
          deleting = nil
          if let template { store.delete(template: template) }
        }
        .accessibilityIdentifier("confirmDeleteTemplate")
        Button(L10n.text("Отмена", locale: locale), role: .cancel) { deleting = nil }
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
  @State private var technique: Exercise?
  let template: WorkoutTemplate
  private var current: WorkoutTemplate {
    store.templates.first { $0.id == template.id } ?? template
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        WorkoutHero(title: current.name)
        VStack(spacing: 20) {
          TemplateMuscleGroups(template: current)
          WorkoutSummaryCard(metrics: [
            (title: L10n.text("Упражнения", locale: locale), value: "\(current.exercises.count)"),
            (
              title: L10n.text("Подходы", locale: locale),
              value: "\(current.exercises.reduce(0) { $0 + $1.setCount })"
            ),
            (
              title: L10n.text("Отдых", locale: locale),
              value: current.restSeconds == 0
                ? L10n.text("Произвольный", locale: locale)
                : L10n.format("%@ с", String(current.restSeconds), locale: locale)
            ),
          ])
          ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, item in
            TemplateExerciseCard(
              item: item, index: index, onTechnique: { technique = item.exercise })
          }
        }.padding(16)
      }
    }.background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $technique) { exercise in
        ExerciseDetailView(exercise: exercise)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(L10n.text("Изменить", locale: locale), systemImage: "pencil") { editing = true }
              .accessibilityIdentifier("editTemplate")
            Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive) {
              confirmDelete = true
            }
          } label: {
            Image(systemName: "ellipsis")
          }
          .accessibilityLabel(L10n.text("Действия шаблона", locale: locale))
          .accessibilityIdentifier("templateActions")
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
  @State private var technique: Exercise?
  @State private var validationMessage: String?
  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("Название", locale: locale)) {
          TextField(L10n.text("Название плана", locale: locale), text: $template.name)
        }
        Section {
          NavigationLink {
            MuscleSelectionView(selection: $template.muscleSelection)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(L10n.text("Группы и мышцы", locale: locale))
              Text(
                template.muscleSelection.isEmpty
                  ? L10n.text("Не выбраны", locale: locale)
                  : MuscleSelectionText.summary(template.muscleSelection, locale: locale)
              ).font(.subheadline).foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("chooseTemplateMuscles")
        } header: {
          Text(L10n.text("Основные группы мышц", locale: locale))
        } footer: {
          Text(
            L10n.text(
              "Необязательно. Выбор включит фильтр по основным мышцам при добавлении упражнений.",
              locale: locale))
        }
        ForEach(Array(template.exercises.enumerated()), id: \.element.id) { index, item in
          Section {
            TemplateExerciseCard(
              item: item, index: index, onTechnique: { technique = item.exercise },
              onRemove: { removeExercise(item.id) }
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                removeExercise(item.id)
              } label: {
                Label(L10n.text("Убрать упражнение", locale: locale), systemImage: "minus.circle")
              }
              .accessibilityIdentifier("swipeRemoveTemplateExercise_\(item.id)")
            }
          }
        }
        Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
          picking = true
        }
        Section {
          DisclosureGroup(L10n.text("Параметры выполнения", locale: locale)) {
            TemplateTrainingDays(selection: $template.preferredWeekdays)
            Picker(
              L10n.text("Отдых между подходами", locale: locale),
              selection: Binding(
                get: { template.restSeconds > 0 },
                set: { template.restSeconds = $0 ? 90 : 0 }
              )
            ) {
              Text(L10n.text("Произвольный", locale: locale)).tag(false)
              Text(L10n.text("По таймеру", locale: locale)).tag(true)
            }
            if template.restSeconds > 0 {
              Stepper(
                L10n.format("%@ секунд", String(template.restSeconds), locale: locale),
                value: $template.restSeconds, in: 1...3600, step: 15)
            }
            Text(
              L10n.text(
                "Отдых общий для всех упражнений. При произвольном отдыхе таймер не запускается.",
                locale: locale)
            ).font(.caption).foregroundStyle(.secondary)
            ForEach($template.exercises) { $exercise in
              VStack(alignment: .leading, spacing: 12) {
                Text(L10n.exerciseName(exercise.exercise, locale: locale)).font(.headline)
                TemplateExerciseParameters(exercise: $exercise)
              }.padding(.vertical, 4)
            }
          }
          .accessibilityIdentifier("templateExecutionParameters")
        }
        if let validationMessage {
          Text(L10n.text(validationMessage, locale: locale)).foregroundStyle(.red)
        }
      }
      .listStyle(.insetGrouped)
      .navigationDestination(item: $technique) { exercise in
        ExerciseDetailView(exercise: exercise)
      }
      .navigationTitle(L10n.text("План тренировки", locale: locale)).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
            .accessibilityIdentifier("cancelTemplateEditing")
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
        ExercisePicker(initialGroups: template.muscleGroups, initialMuscles: template.muscles) {
          template.exercises.append(TemplateExercise(exercise: $0))
        }
      }
      .archiveTransferPresenter(when: store.showingTemplateEditor && !picking)
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    }
  }

  private func removeExercise(_ id: UUID) {
    template.exercises.removeAll { $0.id == id }
  }

}

private struct TemplateTrainingDays: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Binding var selection: Set<WorkoutWeekday>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("Дни тренировок", locale: locale)).font(.headline)
      ForEach(WorkoutWeekday.ordered(in: calendar), id: \.self) { day in
        Toggle(
          L10n.text(day.title, locale: locale),
          isOn: Binding(
            get: { selection.contains(day) },
            set: { selected in
              if selected { selection.insert(day) } else { selection.remove(day) }
            })
        )
        .accessibilityIdentifier("templateWeekday_\(day.rawValue)")
      }
      Text(
        L10n.text(
          "Необязательно. В выбранные дни шаблон будет показываться первым при начале тренировки.",
          locale: locale)
      ).font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 4)
  }
}

private struct TemplateExerciseParameters: View {
  @Environment(\.locale) private var locale
  @Binding var exercise: TemplateExercise

  var body: some View {
    Group {
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
    }
  }
}

struct TemplateMuscleGroups: View {
  @Environment(\.locale) private var locale
  let template: WorkoutTemplate

  var body: some View {
    if !template.muscleSelection.isEmpty {
      Text(MuscleSelectionText.summary(template.muscleSelection, locale: locale))
        .font(.subheadline).foregroundStyle(.secondary)
    }
  }
}
