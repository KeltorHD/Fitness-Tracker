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
                if !template.variations.isEmpty {
                  Text(
                    L10n.format(
                      "Вариаций: %@", String(template.variations.count + 1), locale: locale)
                  ).font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 20)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(FitTheme.card, in: .capsule)
              .themeGlow(in: Capsule())
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
        ToolbarItem(placement: .topBarTrailing) {
          Button(L10n.text("Создать тренировку", locale: locale), systemImage: "plus") {
            creating = true
          }.foregroundStyle(
            .primary)
        }
        SettingsToolbar()
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
  @State private var selectedVariationID: UUID?
  @State private var previousResults: [UUID: WorkoutExercise] = [:]
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  let template: WorkoutTemplate
  private var current: WorkoutTemplate {
    store.templates.first { $0.id == template.id } ?? template
  }
  private var selectedExercises: [TemplateExercise] {
    current.variations.first { $0.id == selectedVariationID }?.exercises ?? current.exercises
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        WorkoutHero(title: current.name)
        VStack(spacing: 20) {
          TemplateMuscleGroups(template: current)
          if !current.variations.isEmpty {
            TemplateVariationSelector(template: current, selection: $selectedVariationID)
          }
          WorkoutSummaryCard(metrics: [
            (title: L10n.text("Упражнения", locale: locale), value: "\(selectedExercises.count)"),
            (
              title: L10n.text("Подходы", locale: locale),
              value: "\(selectedExercises.reduce(0) { $0 + $1.setCount })"
            ),
            (
              title: L10n.text("Отдых", locale: locale),
              value: current.restSeconds == 0
                ? L10n.text("Произвольный", locale: locale)
                : L10n.format("%@ с", String(current.restSeconds), locale: locale)
            ),
          ])
          ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { index, item in
            TemplateExerciseCard(
              item: item, index: index, onTechnique: { technique = item.exercise },
              previousResult: previousResults[item.id], unit: unit)
          }
        }.padding(16)
      }
    }.background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
      .onChange(of: selectedExercises, initial: true) { refreshResults() }
      .onChange(of: store.workouts) { refreshResults() }
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
            Section { SettingsLink() }
          } label: {
            Image(systemName: "ellipsis")
          }
          .accessibilityLabel(L10n.text("Действия шаблона", locale: locale))
          .accessibilityIdentifier("templateActions")
        }
      }
      .sheet(isPresented: $editing, onDismiss: { store.showingTemplateEditor = false }) {
        TemplateEditor(template: current, selectedVariationID: selectedVariationID)
          .onAppear { store.showingTemplateEditor = true }
      }
      .onChange(of: current.variations) {
        if let selectedVariationID,
          !current.variations.contains(where: { $0.id == selectedVariationID })
        {
          self.selectedVariationID = nil
        }
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

  private func refreshResults() {
    previousResults = TemplateExercise.previousResults(
      for: selectedExercises, history: store.workouts)
  }
}

struct TemplateEditor: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State var template: WorkoutTemplate
  @State var selectedVariationID: UUID? = nil
  @State private var picking = false
  @State private var technique: Exercise?
  @State private var validationMessage: String?
  @State private var deletingVariation = false
  @State private var replacement: TemplateExercise?
  @State private var previousResults: [UUID: WorkoutExercise] = [:]
  @State private var reorderRevision = 0
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @FocusState private var focusedField: Field?

  private enum Field: Hashable { case name, variationName }

  private var selectedExercises: [TemplateExercise] {
    template.variations.first { $0.id == selectedVariationID }?.exercises ?? template.exercises
  }

  private var exerciseBinding: Binding<[TemplateExercise]> {
    Binding(
      get: { selectedExercises },
      set: { rows in
        if let index = template.variations.firstIndex(where: { $0.id == selectedVariationID }) {
          template.variations[index].exercises = rows
        } else {
          template.exercises = rows
        }
      })
  }

  private var variationName: Binding<String> {
    Binding(
      get: {
        template.variations.first { $0.id == selectedVariationID }?.name
          ?? template.baseVariationName ?? L10n.format("Вариант %@", "1", locale: locale)
      },
      set: { name in
        guard let index = template.variations.firstIndex(where: { $0.id == selectedVariationID })
        else {
          template.baseVariationName = name
          return
        }
        template.variations[index].name = name
      })
  }

  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("Название", locale: locale)) {
          TextField(L10n.text("Название плана", locale: locale), text: $template.name)
            .focused($focusedField, equals: .name)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityIdentifier("templateName")
        }
        Section {
          if !template.variations.isEmpty {
            TemplateVariationSelector(template: template, selection: $selectedVariationID)
          }
          TextField(L10n.text("Название вариации", locale: locale), text: variationName)
            .focused($focusedField, equals: .variationName)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityIdentifier("templateVariationName")
          if selectedVariationID != nil {
            Button(L10n.text("Удалить вариацию", locale: locale), role: .destructive) {
              focusedField = nil
              deletingVariation = true
            }.accessibilityIdentifier("deleteTemplateVariation")
          }
          Button(L10n.text("Добавить вариацию", locale: locale), systemImage: "square.on.square") {
            addVariation()
          }.accessibilityIdentifier("addTemplateVariation")
        } header: {
          Text(L10n.text("Вариации упражнений", locale: locale))
        } footer: {
          Text(
            L10n.text(
              "У каждой вариации свой список упражнений. Нужную можно выбрать перед началом тренировки.",
              locale: locale))
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
        Section {
          ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { index, item in
            TemplateExerciseCard(
              item: item, index: index, onTechnique: { technique = item.exercise },
              previousResult: previousResults[item.id], unit: unit,
              onRemove: { removeExercise(item.id) },
              onReplace: {
                focusedField = nil
                replacement = item
              }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .contentShape(.rect)
            .moveDisabled(false)
            .accessibilityHint(
              L10n.text("Удерживайте и перетащите, чтобы изменить порядок.", locale: locale)
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                removeExercise(item.id)
              } label: {
                Label(L10n.text("Убрать упражнение", locale: locale), systemImage: "minus.circle")
              }
              .tint(.red)
              .accessibilityIdentifier("swipeRemoveTemplateExercise_\(item.id)")
              Button {
                focusedField = nil
                replacement = item
              } label: {
                Label(
                  L10n.text("Заменить упражнение", locale: locale),
                  systemImage: "arrow.triangle.2.circlepath")
              }
              .tint(colorTheme.accent)
              .accessibilityIdentifier("swipeReplaceTemplateExercise_\(item.id)")
            }
          }
          .onMove(perform: moveExercises)
          // Refresh UIKit's drag snapshot after applying the new order.
          .id(reorderRevision)
        }
        Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
          focusedField = nil
          picking = true
        }.accessibilityIdentifier("addTemplateExercise")
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
            ForEach(exerciseBinding) { $exercise in
              VStack(alignment: .leading, spacing: 12) {
                Text(L10n.exerciseName(exercise.exercise, locale: locale)).font(.headline)
                TemplateExerciseParameters(exercise: $exercise)
              }.padding(.vertical, 4)
            }
          }
          .accessibilityIdentifier("templateExecutionParameters")
        }
      }
      .listStyle(.insetGrouped)
      .scrollDismissesKeyboard(.interactively)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("templateEditorList")
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
            focusedField = nil
            do {
              try Validation.template(template)
              if store.save(template: template) {
                dismiss()
              } else {
                validationMessage = store.error
              }
            } catch { validationMessage = error.localizedDescription }
          }.accessibilityIdentifier("saveTemplate")
        }
      }
      .sheet(isPresented: $picking) {
        ExercisePicker(
          initialGroups: template.muscleGroups, initialMuscles: template.muscles,
          initialRegions: template.muscleRegions
        ) {
          exerciseBinding.wrappedValue.append(TemplateExercise(exercise: $0))
        }
      }
      .sheet(item: $replacement) { item in
        ExercisePicker { exercise in
          var rows = selectedExercises
          guard let index = rows.firstIndex(where: { $0.id == item.id }) else { return }
          rows[index] = item.replacing(with: exercise)
          exerciseBinding.wrappedValue = rows
        }
      }
      .onChange(of: selectedExercises, initial: true) { refreshResults() }
      .onChange(of: store.workouts) { refreshResults() }
      .onChange(of: selectedVariationID) {
        focusedField = nil
      }
      .confirmationDialog(
        L10n.text("Удалить вариацию?", locale: locale), isPresented: $deletingVariation,
        titleVisibility: .visible
      ) {
        Button(L10n.text("Удалить", locale: locale), role: .destructive) {
          template.variations.removeAll { $0.id == selectedVariationID }
          selectedVariationID = nil
        }.accessibilityIdentifier("confirmDeleteTemplateVariation")
        Button(L10n.text("Отмена", locale: locale), role: .cancel) {}
      }
      .alert(
        "FitnessTracker",
        isPresented: Binding(
          get: { validationMessage != nil && !picking && replacement == nil && !deletingVariation },
          set: { if !$0 { dismissValidationMessage() } })
      ) {
        Button(L10n.text("Понятно", locale: locale)) { dismissValidationMessage() }
      } message: {
        Text(L10n.text(validationMessage ?? "", locale: locale))
      }
      .archiveTransferPresenter(
        when: store.showingTemplateEditor && !picking && !deletingVariation
          && replacement == nil && validationMessage == nil
      )
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    }
  }

  private func removeExercise(_ id: UUID) {
    focusedField = nil
    exerciseBinding.wrappedValue = TemplateExercise.normalizingSupersets(
      selectedExercises.filter { $0.id != id })
  }

  private func dismissValidationMessage() {
    if let validationMessage, store.error == validationMessage { store.error = nil }
    validationMessage = nil
  }

  private func addVariation() {
    focusedField = nil
    do {
      let name = L10n.format("Вариант %@", String(template.variations.count + 2), locale: locale)
      let variation = try template.makeVariation(name: name, copying: selectedVariationID)
      template.variations.append(variation)
      selectedVariationID = variation.id
      validationMessage = nil
    } catch {
      validationMessage = error.localizedDescription
    }
  }

  private func refreshResults() {
    previousResults = TemplateExercise.previousResults(
      for: selectedExercises, history: store.workouts)
  }

  private func moveExercises(from source: IndexSet, to destination: Int) {
    guard source.count == 1, let index = source.first,
      selectedExercises.indices.contains(index)
    else { return }
    focusedField = nil
    do {
      let rows = try TemplateExercise.moving(
        selectedExercises[index].id, to: destination, in: selectedExercises)
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
        exerciseBinding.wrappedValue = rows
        reorderRevision += 1
      }
    } catch {
      validationMessage = error.localizedDescription
    }
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
    Stepper(
      L10n.format("Подходы: %@", String(exercise.setCount), locale: locale),
      value: Binding(
        get: { exercise.setCount },
        set: { count in
          exercise.setCount = count
          if let plans = exercise.plannedSets {
            exercise.plannedSets =
              Array(plans.prefix(count))
              + (plans.count..<max(plans.count, count)).map { _ in WorkoutSet() }
          }
        }), in: 1...30
    )
    .accessibilityIdentifier("templateSetCount_\(exercise.id)")
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
