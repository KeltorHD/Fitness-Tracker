import FitLifeCore
import SwiftUI

struct PersonalExercisesView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @State private var exercises: [Exercise] = []
  var onSelect: ((Exercise) -> Void)? = nil

  init(onSelect: ((Exercise) -> Void)? = nil) { self.onSelect = onSelect }

  var body: some View {
    List {
      if exercises.isEmpty {
        ContentUnavailableView(
          L10n.text("Пока нет своих упражнений", locale: locale),
          systemImage: "figure.strengthtraining.traditional",
          description: Text(
            L10n.text(
              "Здесь появятся упражнения из импортированных тренировок и планов.", locale: locale)))
      } else {
        ForEach(exercises) { exercise in
          NavigationLink {
            PersonalExerciseDetail(exercise: exercise, onSelect: onSelect)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(exercise.name)
              if let linked = store.exerciseLinks.first(where: { $0.id == exercise.id }),
                let entry = ExerciseLibrary.entry(
                  for: linked.catalogID,
                  language: AppLanguage.system.resolved(preferredLanguages: [locale.identifier]))
              {
                Text(entry.name).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle(L10n.text("Мои упражнения", locale: locale))
    .onChange(of: store.workouts, initial: true) { refresh() }
    .onChange(of: store.templates) { refresh() }
  }

  private func refresh() {
    exercises = PersonalExercises.list(workouts: store.workouts, templates: store.templates)
  }
}

private struct PersonalExerciseDetail: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  let exercise: Exercise
  var onSelect: ((Exercise) -> Void)? = nil
  private var link: ExerciseLink? { store.exerciseLinks.first { $0.id == exercise.id } }
  private var catalogEntry: ExerciseLibraryEntry? {
    guard let link else { return nil }
    return ExerciseLibrary.entry(
      for: link.catalogID,
      language: AppLanguage.system.resolved(preferredLanguages: [locale.identifier]))
  }

  var body: some View {
    List {
      Section(L10n.text("Основной каталог", locale: locale)) {
        if let catalogEntry {
          NavigationLink {
            ExerciseDetailView(exercise: catalogEntry.exercise)
          } label: {
            Text(catalogEntry.name)
          }
          Button(L10n.text("Убрать связь", locale: locale)) {
            _ = store.removeExerciseLink(id: exercise.id)
          }
        } else {
          Text(L10n.text("Не связано с каталогом", locale: locale)).foregroundStyle(.secondary)
        }
        NavigationLink {
          PersonalExerciseCatalogPicker(exercise: exercise)
        } label: {
          Label(
            L10n.text(link == nil ? "Связать с каталогом" : "Изменить связь", locale: locale),
            systemImage: "link")
        }
      } footer: {
        Text(
          L10n.text(
            "История и статистика объединятся. Записи тренировок сохранят прежние названия и подходы.",
            locale: locale))
      }
      NavigationLink {
        ExerciseProgressScreen(exercise: exercise)
      } label: {
        Label(L10n.text("История и статистика", locale: locale), systemImage: "chart.xyaxis.line")
      }
    }
    .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if let onSelect {
        Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
          onSelect(catalogEntry?.exercise ?? exercise)
        }
        .buttonStyle(.glassProminent).controlSize(.large).padding()
      }
    }
  }
}

private struct PersonalExerciseCatalogPicker: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  let exercise: Exercise
  @State private var model = ExerciseLibraryViewModel()
  @State private var candidate: ExerciseLibraryEntry?
  @State private var confirming = false

  var body: some View {
    @Bindable var model = model
    List {
      if let error = model.loadingError {
        ContentUnavailableView(
          L10n.text("Библиотека недоступна", locale: locale),
          systemImage: "exclamationmark.triangle",
          description: Text(L10n.text(error, locale: locale)))
      } else if model.results.isEmpty {
        ContentUnavailableView(
          L10n.text("Ничего не найдено", locale: locale), systemImage: "magnifyingglass")
      } else {
        ForEach(model.results) { entry in
          Button {
            candidate = entry
            confirming = true
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.name).foregroundStyle(.primary)
              Text(entry.primaryMuscles.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle(L10n.text("Выберите упражнение", locale: locale))
    .searchable(
      text: $model.search, prompt: L10n.text("Название, мышца или инвентарь", locale: locale)
    )
    .onChange(of: locale, initial: true) {
      model.language = AppLanguage.system.resolved(preferredLanguages: [locale.identifier])
    }
    .confirmationDialog(
      L10n.text("Связать упражнения?", locale: locale), isPresented: $confirming,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Связать", locale: locale)) {
        guard let candidate else { return }
        if store.setExerciseLink(ExerciseLink(id: exercise.id, catalogID: candidate.id)) {
          dismiss()
        }
      }
    } message: {
      if let candidate {
        Text(exercise.name + " → " + candidate.name)
      }
    }
  }
}
