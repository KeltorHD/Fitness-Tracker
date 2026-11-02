import FitnessTrackerCore
import SwiftUI

struct ExerciseLibraryView: View {
  @Environment(\.locale) private var locale
  var onSelect: ((Exercise) -> Void)? = nil
  @State private var model: ExerciseLibraryViewModel

  init(
    initialGroups: Set<MuscleGroup> = [], initialMuscles: Set<ExerciseMuscle> = [],
    onSelect: ((Exercise) -> Void)? = nil
  ) {
    self.onSelect = onSelect
    _model = State(
      initialValue: ExerciseLibraryViewModel(groups: initialGroups, muscles: initialMuscles))
  }

  var body: some View {
    @Bindable var model = model
    List {
      Section {
        NavigationLink {
          MuscleSelectionView(selection: $model.muscleSelection, showsDoneButton: true)
        } label: {
          Label(
            MuscleSelectionText.compactSummary(model.muscleSelection, locale: locale),
            systemImage: "figure.strengthtraining.traditional")
        }
        .font(.subheadline)
        .accessibilityIdentifier("chooseExerciseMuscles")
        .accessibilityValue(MuscleSelectionText.summary(model.muscleSelection, locale: locale))
        Menu {
          Button(L10n.text("Весь инвентарь", locale: locale)) { model.equipment = [] }
          ForEach(ExerciseEquipment.allCases, id: \.self) { value in
            Toggle(
              L10n.text(value.title, locale: locale),
              isOn: Binding(
                get: { model.equipment.contains(value) },
                set: { selected in
                  if selected {
                    model.equipment.insert(value)
                  } else {
                    model.equipment.remove(value)
                  }
                }))
          }
        } label: {
          Label(
            model.equipment.isEmpty
              ? L10n.text("Весь инвентарь", locale: locale)
              : ExerciseEquipment.allCases.filter { model.equipment.contains($0) }
                .map { L10n.text($0.title, locale: locale) }.joined(separator: ", "),
            systemImage: "line.3.horizontal.decrease"
          )
        }
        .font(.subheadline)
      } footer: {
        Text(
          L10n.format(
            "Найдено: %@ · Фото и инструкции доступны без интернета",
            String(model.results.count), locale: locale))
      }
      Section {
        DisclosureGroup(L10n.text("Выбрать на схеме тела", locale: locale)) {
          ExerciseBodyPicker(selection: $model.muscleSelection)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("exerciseBodyPicker")
      }
      if let error = model.loadingError {
        ContentUnavailableView(
          L10n.text("Библиотека недоступна", locale: locale),
          systemImage: "exclamationmark.triangle",
          description: Text(L10n.text(error, locale: locale))
        )
      } else if model.results.isEmpty {
        ContentUnavailableView.search(text: model.search)
        Button(L10n.text("Сбросить поиск и фильтры", locale: locale)) {
          model.reset()
        }
      }
      ForEach(model.results) { entry in
        NavigationLink {
          ExerciseDetailView(exercise: entry.exercise, onSelect: onSelect)
        } label: {
          HStack(spacing: 12) {
            if let path = entry.generatedMedia?.poster ?? entry.images.first {
              ExercisePhoto(path: path).frame(width: 76, height: 60)
                .clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
            } else {
              Image(systemName: "dumbbell").frame(width: 76, height: 60).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
              Text(entry.name).font(.headline).foregroundStyle(.primary)
              Text(
                "\(entry.primaryMuscles.joined(separator: ", ")) · \(L10n.text(entry.equipment.title, locale: locale))"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }
      }
      Section {
        NavigationLink {
          ExerciseCreditsView()
        } label: {
          Label(
            L10n.text("Источник данных и фотографии", locale: locale), systemImage: "info.circle")
        }
      }
    }
    .navigationTitle(L10n.text("Упражнения", locale: locale))
    .searchable(
      text: $model.search, prompt: L10n.text("Название, мышца или инвентарь", locale: locale)
    )
    .accessibilityIdentifier("exerciseLibrary")
    .onChange(of: locale, initial: true) {
      model.language = AppLanguage.system.resolved(preferredLanguages: [locale.identifier])
    }
  }
}

struct ExerciseDetailView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  let exercise: Exercise
  var onSelect: ((Exercise) -> Void)? = nil
  @State private var photo = 0
  private var entry: ExerciseLibraryEntry? {
    ExerciseLibrary.entry(
      for: exercise.id,
      language: AppLanguage.system.resolved(preferredLanguages: [locale.identifier]))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let entry {
          if let generated = entry.generatedMedia {
            ExerciseAnimation(media: generated)
          } else if !entry.images.isEmpty {
            VStack(spacing: 8) {
              TabView(selection: $photo) {
                ForEach(Array(entry.images.enumerated()), id: \.offset) { index, path in
                  ExercisePhoto(path: path).tag(index)
                    .accessibilityLabel(
                      L10n.format(
                        "Фото %@ из %@: %@", String(index + 1),
                        String(entry.images.count), String(entry.name),
                        locale: locale))
                }
              }
              .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 270)
              .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
              HStack {
                Button(L10n.text("Предыдущее фото", locale: locale), systemImage: "chevron.left") {
                  photo = max(0, photo - 1)
                }
                .labelStyle(.iconOnly).disabled(photo == 0)
                Spacer()
                Text(
                  L10n.format(
                    "Положение %@ из %@", String(photo + 1),
                    String(entry.images.count), locale: locale)
                ).font(.caption)
                  .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Следующее фото", locale: locale), systemImage: "chevron.right") {
                  photo = min(entry.images.count - 1, photo + 1)
                }
                .labelStyle(.iconOnly).disabled(photo == entry.images.count - 1)
              }.buttonStyle(.glass)
            }
          } else {
            Text(L10n.text("В исходном каталоге нет изображений этого упражнения.", locale: locale))
              .foregroundStyle(.secondary)
          }
          HStack(alignment: .top, spacing: 12) {
            MetricView(
              value: L10n.text(entry.equipment.title, locale: locale),
              title: L10n.text("инвентарь", locale: locale), symbol: "dumbbell")
            MetricView(
              value: L10n.text(entry.level.title, locale: locale),
              title: L10n.text("уровень", locale: locale), symbol: "chart.bar")
          }
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Работающие мышцы", locale: locale)).font(.title2.bold())
            Text(entry.primaryMuscles.joined(separator: ", "))
            if !entry.secondaryMuscles.isEmpty {
              Text(
                L10n.text("Дополнительно: ", locale: locale)
                  + entry.secondaryMuscles.joined(separator: ", ")
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          Text(L10n.text("Техника выполнения", locale: locale)).font(.title2.bold())
          if entry.translationAutomatic == true && !entry.steps.isEmpty {
            Text(
              L10n.text("Описание переведено автоматически из открытого источника.", locale: locale)
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          if entry.steps.isEmpty {
            Text(
              L10n.text(
                "В исходном каталоге нет подробной техники этого упражнения.", locale: locale)
            )
            .foregroundStyle(.secondary)
          }
          ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, text in
            HStack(alignment: .top, spacing: 12) {
              Text("\(index + 1)").font(.headline).foregroundStyle(.tint)
                .frame(width: 30, height: 30).background(
                  colorTheme.accent.opacity(0.12), in: .circle)
              Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityElement(children: .combine)
          }
          Text(
            L10n.text(
              entry.generatedMedia == nil
                ? "Техника из free-exercise-db. Показаны фотографии отдельных положений, а не видеозапись движения."
                : "Техника из free-exercise-db. Иллюстрация движения создана ИИ.",
              locale: locale)
          )
          .font(.caption).foregroundStyle(.secondary)
          NavigationLink {
            ExerciseCreditsView()
          } label: {
            Label(L10n.text("Источник и лицензия", locale: locale), systemImage: "info.circle")
          }
        } else {
          Label(
            L10n.text(exercise.muscle.title, locale: locale),
            systemImage: "figure.strengthtraining.traditional")
          Text(
            exercise.instructions.isEmpty
              ? L10n.text(
                "Для собственного упражнения можно сохранить технику в заметках тренировки.",
                locale: locale)
              : exercise.instructions)
        }
      }.padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(entry?.name ?? exercise.name).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if let onSelect {
        Button(L10n.text("Добавить упражнение", locale: locale), systemImage: "plus") {
          onSelect(entry?.exercise ?? exercise)
        }
        .buttonStyle(.glassProminent).controlSize(.large).padding()
        .accessibilityIdentifier("selectLibraryExercise")
      }
    }
  }
}

struct ExerciseCreditsView: View {
  @Environment(\.locale) private var locale
  var body: some View {
    List {
      Section(L10n.text("Библиотека FitnessTracker", locale: locale)) {
        Text(
          L10n.text(
            "876 упражнений и 1746 фотографий, встроенных в приложение.", locale: locale))
        Text(
          L10n.text(
            "Каталог переведён на русский язык. Новые описания преимущественно переведены автоматически; такие карточки отмечены.",
            locale: locale)
        )
      }
      if let source = ExerciseLibrary.document?.source {
        Section(L10n.text("Источник", locale: locale)) {
          if let url = URL(string: source.repositoryURL) { Link(source.name, destination: url) }
          Text(
            L10n.text(
              "Исходная база: yuhonas/free-exercise-db; первоначальные данные — Ollie Jennings / exercises.json.",
              locale: locale)
          )
          LabeledContent(L10n.text("Лицензия", locale: locale), value: source.licenseName)
        }
        Section(L10n.text("Текст лицензии источника", locale: locale)) {
          Text(source.licenseText).font(.footnote).textSelection(.enabled)
        }
      }
    }.navigationTitle(L10n.text("Источники", locale: locale)).navigationBarTitleDisplayMode(.inline)
  }
}
