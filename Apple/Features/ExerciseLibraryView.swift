import FitSessionCore
import SwiftUI
import UIKit

struct ExerciseLibraryView: View {
  var onSelect: ((Exercise) -> Void)? = nil
  @State private var search = ""
  @State private var group: MuscleGroup?
  @State private var equipment: ExerciseEquipment?

  private var results: [ExerciseLibraryEntry] {
    ExerciseLibrary.search(search, group: group, equipment: equipment)
  }
  var body: some View {
    List {
      Section {
        HStack {
          Menu {
            Button("Все мышцы") { group = nil }
            ForEach(MuscleGroup.allCases, id: \.self) { value in
              Button(value.title) { group = value }
            }
          } label: {
            Label(group?.title ?? "Все мышцы", systemImage: "figure.strengthtraining.traditional")
          }
          Spacer()
          Menu {
            Button("Весь инвентарь") { equipment = nil }
            ForEach(ExerciseEquipment.allCases, id: \.self) { value in
              Button(value.title) { equipment = value }
            }
          } label: {
            Label(equipment?.title ?? "Инвентарь", systemImage: "line.3.horizontal.decrease")
          }
        }.font(.subheadline)
      } footer: {
        Text("Найдено: \(results.count) · Фото и инструкции доступны без интернета")
      }
      if let error = ExerciseLibrary.loadingError {
        ContentUnavailableView(
          "Библиотека недоступна", systemImage: "exclamationmark.triangle", description: Text(error)
        )
      } else if results.isEmpty {
        ContentUnavailableView.search(text: search)
        Button("Сбросить поиск и фильтры") {
          search = ""
          group = nil
          equipment = nil
        }
      }
      ForEach(results) { entry in
        NavigationLink {
          ExerciseDetailView(exercise: entry.exercise, onSelect: onSelect)
        } label: {
          HStack(spacing: 12) {
            ExercisePhoto(path: entry.images[0]).frame(width: 76, height: 60)
              .clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
              Text(entry.name).font(.headline).foregroundStyle(.primary)
              Text("\(entry.group.title) · \(entry.equipment.title)")
                .font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }
      }
      Section {
        NavigationLink {
          ExerciseCreditsView()
        } label: {
          Label("Источник данных и фотографии", systemImage: "info.circle")
        }
      }
    }
    .navigationTitle("Упражнения")
    .searchable(text: $search, prompt: "Название, мышца или инвентарь")
    .accessibilityIdentifier("exerciseLibrary")
  }
}

struct ExerciseDetailView: View {
  let exercise: Exercise
  var onSelect: ((Exercise) -> Void)? = nil
  @State private var photo = 0
  private var entry: ExerciseLibraryEntry? { ExerciseLibrary.entry(for: exercise.id) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let entry {
          VStack(spacing: 8) {
            TabView(selection: $photo) {
              ForEach(Array(entry.images.enumerated()), id: \.offset) { index, path in
                ExercisePhoto(path: path).tag(index)
                  .accessibilityLabel("Фото \(index + 1) из \(entry.images.count): \(entry.name)")
              }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 270)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            HStack {
              Button("Предыдущее фото", systemImage: "chevron.left") { photo = max(0, photo - 1) }
                .labelStyle(.iconOnly).disabled(photo == 0)
              Spacer()
              Text("Положение \(photo + 1) из \(entry.images.count)").font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Следующее фото", systemImage: "chevron.right") {
                photo = min(entry.images.count - 1, photo + 1)
              }
              .labelStyle(.iconOnly).disabled(photo == entry.images.count - 1)
            }.buttonStyle(.glass)
          }
          HStack(alignment: .top, spacing: 12) {
            MetricView(value: entry.equipment.title, title: "инвентарь", symbol: "dumbbell")
            MetricView(value: entry.level.title, title: "уровень", symbol: "chart.bar")
          }
          VStack(alignment: .leading, spacing: 8) {
            Text("Работающие мышцы").font(.title2.bold())
            Text(entry.primaryMuscles.joined(separator: ", "))
            if !entry.secondaryMuscles.isEmpty {
              Text("Дополнительно: " + entry.secondaryMuscles.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          Text("Техника выполнения").font(.title2.bold())
          ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, text in
            HStack(alignment: .top, spacing: 12) {
              Text("\(index + 1)").font(.headline).foregroundStyle(.tint)
                .frame(width: 30, height: 30).background(
                  Color.accentColor.opacity(0.12), in: .circle)
              Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityElement(children: .combine)
          }
          Text(
            "Русская адаптация инструкций free-exercise-db. Показаны фотографии отдельных положений, а не видеозапись движения."
          )
          .font(.caption).foregroundStyle(.secondary)
          NavigationLink {
            ExerciseCreditsView()
          } label: {
            Label("Источник и лицензия", systemImage: "info.circle")
          }
        } else {
          Label(exercise.muscle.title, systemImage: "figure.strengthtraining.traditional")
          Text(
            exercise.instructions.isEmpty
              ? "Для собственного упражнения можно сохранить технику в заметках тренировки."
              : exercise.instructions)
        }
      }.padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(entry?.name ?? exercise.name).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if let onSelect {
        Button("Добавить упражнение", systemImage: "plus") { onSelect(entry?.exercise ?? exercise) }
          .buttonStyle(.glassProminent).controlSize(.large).padding()
          .accessibilityIdentifier("selectLibraryExercise")
      }
    }
  }
}

struct ExercisePhoto: View {
  let path: String
  var body: some View {
    if let image = ExercisePhotoCache.image(path: path) {
      Image(uiImage: image).resizable().scaledToFit()
    } else {
      ContentUnavailableView("Фото недоступно", systemImage: "photo")
    }
  }
}

@MainActor private enum ExercisePhotoCache {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 40
    cache.totalCostLimit = 32 * 1024 * 1024
    return cache
  }()
  static func image(path: String) -> UIImage? {
    if let image = cache.object(forKey: path as NSString) { return image }
    guard !path.contains(".."), !path.hasPrefix("/"),
      let url = Bundle.main.resourceURL?.appendingPathComponent("ExerciseMedia")
        .appendingPathComponent(path),
      let image = UIImage(contentsOfFile: url.path)
    else { return nil }
    cache.setObject(
      image, forKey: path as NSString, cost: Int(image.size.width * image.size.height * 4))
    return image
  }
}

struct ExerciseCreditsView: View {
  var body: some View {
    List {
      Section("Библиотека FitSession") {
        Text("100 силовых упражнений и 200 фотографий, встроенных в приложение.")
        Text(
          "Названия, мышцы, оборудование и сокращённые пошаговые инструкции переведены и адаптированы на русский язык для FitSession."
        )
      }
      if let source = ExerciseLibrary.document?.source {
        Section("Источник") {
          if let url = URL(string: source.repositoryURL) { Link(source.name, destination: url) }
          Text(
            "Исходная база: yuhonas/free-exercise-db; первоначальные данные — Ollie Jennings / exercises.json."
          )
          LabeledContent("Лицензия", value: source.licenseName)
        }
        Section("Текст лицензии источника") {
          Text(source.licenseText).font(.footnote).textSelection(.enabled)
        }
      }
    }.navigationTitle("Источники").navigationBarTitleDisplayMode(.inline)
  }
}
