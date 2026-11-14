import FitLifeCore
import SwiftUI
import UIKit

private struct ExerciseImageLoaderKey: EnvironmentKey {
  static let defaultValue: (any ExerciseImageLoading)? = nil
}

struct ExerciseAnimation: View {
  @Environment(\.exerciseImageLoader) private var loader
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.locale) private var locale
  let media: ExerciseGeneratedMedia
  var fillsAvailableSpace = false
  @State private var frames: [UIImage] = []
  @State private var failed = false
  @State private var playing = true
  @State private var pausedFrame = 0
  @State private var start = Date()
  @State private var attempt = 0

  var body: some View {
    VStack(spacing: 12) {
      Group {
        if failed {
          VStack(spacing: 12) {
            Label(
              L10n.text("Фото недоступно", locale: locale),
              systemImage: "photo.badge.exclamationmark")
            Button(L10n.text("Повторить загрузку фото", locale: locale)) { attempt += 1 }
          }
        } else if frames.isEmpty {
          ProgressView(L10n.text("Загрузка фото", locale: locale))
        } else if playing && !reduceMotion {
          TimelineView(.periodic(from: start, by: media.frameDuration)) { timeline in
            Image(uiImage: frames[index(at: timeline.date)]).resizable().scaledToFit()
          }
        } else {
          Image(uiImage: frames[reduceMotion ? 0 : pausedFrame % frames.count]).resizable()
            .scaledToFit()
        }
      }
      .frame(height: fillsAvailableSpace ? nil : 270)
      .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
      .frame(maxWidth: .infinity)
      .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
      .accessibilityLabel(L10n.text("Иллюстрация движения, созданная ИИ.", locale: locale))
      if !reduceMotion && !frames.isEmpty {
        Button {
          if playing {
            pausedFrame = index(at: .now)
          } else {
            start = Date().addingTimeInterval(-Double(pausedFrame) * media.frameDuration)
          }
          playing.toggle()
        } label: {
          Label(
            L10n.text(playing ? "Остановить анимацию" : "Воспроизвести анимацию", locale: locale),
            systemImage: playing ? "pause.fill" : "play.fill")
        }.buttonStyle(.glass).accessibilityIdentifier("exerciseAnimationPlayback")
      }
    }
    .task(id: "\(media.poster)-\(reduceMotion)-\(attempt)") {
      frames = []
      failed = false
      do {
        guard let loader else { throw ExerciseImageError.missingLoader }
        var images: [UIImage] = []
        for path in reduceMotion ? Array(media.frames.prefix(1)) : media.frames {
          let data = try await loader.data(for: path)
          try Task.checkCancellation()
          guard let image = UIImage(data: data) else { throw ExerciseImageError.invalidImage }
          images.append(image)
        }
        try Task.checkCancellation()
        pausedFrame = 0
        start = .now
        frames = images
      } catch {
        if !Task.isCancelled { failed = true }
      }
    }
  }

  private func index(at date: Date) -> Int {
    Int(max(0, date.timeIntervalSince(start)) / media.frameDuration) % max(1, frames.count)
  }
}

extension EnvironmentValues {
  var exerciseImageLoader: (any ExerciseImageLoading)? {
    get { self[ExerciseImageLoaderKey.self] }
    set { self[ExerciseImageLoaderKey.self] = newValue }
  }
}

struct ExercisePhoto: View {
  @Environment(\.locale) private var locale
  let path: String
  @Environment(\.exerciseImageLoader) private var loader
  @State private var model: ExercisePhotoViewModel?
  @State private var attempt = 0

  private struct Request: Hashable {
    let path: String
    let attempt: Int
  }
  var body: some View {
    Group {
      if let image = model?.image {
        Image(uiImage: image).resizable().scaledToFit()
      } else if model?.failed == true {
        VStack(spacing: 8) {
          Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
          Button(
            L10n.text("Повторить загрузку фото", locale: locale), systemImage: "arrow.clockwise"
          ) { attempt += 1 }
          .labelStyle(.iconOnly)
        }.accessibilityLabel(L10n.text("Фото недоступно", locale: locale))
      } else {
        ProgressView().accessibilityLabel(L10n.text("Загрузка фото", locale: locale))
      }
    }
    .task(id: Request(path: path, attempt: attempt)) {
      let model = ExercisePhotoViewModel(loader: loader)
      self.model = model
      await model.load(path: path)
    }
  }
}

struct ExerciseImageCreditView: View {
  @Environment(\.locale) private var locale
  let credit: ExerciseImageCredit

  var body: some View {
    if let sourceURL = URL(string: credit.sourceURL),
      let licenseURL = URL(string: credit.licenseURL)
    {
      HStack {
        Text(credit.author)
        Link(L10n.text("Источник", locale: locale), destination: sourceURL)
        Link(credit.licenseName, destination: licenseURL)
      }
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct ExerciseGeneratedIllustration: View {
  @Environment(\.locale) private var locale
  let path: String
  var fillsAvailableSpace = false

  var body: some View {
    VStack(spacing: 8) {
      ExercisePhoto(path: path)
        .frame(height: fillsAvailableSpace ? nil : 270)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityLabel(L10n.text("Иллюстрация движения, созданная ИИ.", locale: locale))
      Text(L10n.text("Иллюстрация движения создана ИИ.", locale: locale))
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

/// Visual-only presentation; workout data and technique text stay on their own screens.
struct ExerciseMediaViewer: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  let exercise: Exercise
  @State private var photo = 0
  private var entry: ExerciseLibraryEntry? {
    ExerciseLibrary.entry(
      for: PersonalExercises.catalogID(for: exercise.id, links: store.exerciseLinks))
  }

  var body: some View {
    NavigationStack {
      Group {
        if let generated = entry?.generatedMedia {
          ExerciseAnimation(media: generated, fillsAvailableSpace: true).padding(12)
        } else if let illustration = entry?.generatedIllustration {
          ExerciseGeneratedIllustration(path: illustration, fillsAvailableSpace: true).padding(12)
        } else if let images = entry?.images, !images.isEmpty {
          VStack(spacing: 12) {
            TabView(selection: $photo) {
              ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                ExercisePhoto(path: path).padding(12).tag(index)
                  .accessibilityLabel(
                    L10n.format(
                      "Фото %@ из %@: %@", String(index + 1), String(images.count),
                      L10n.exerciseName(exercise, locale: locale), locale: locale))
              }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            if images.count > 1 {
              HStack {
                Button {
                  photo = max(0, photo - 1)
                } label: {
                  Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.disabled(photo == 0)
                  .accessibilityLabel(L10n.text("Предыдущее фото", locale: locale))
                Spacer()
                Text(
                  L10n.format(
                    "Положение %@ из %@", String(photo + 1), String(images.count), locale: locale)
                )
                .font(.caption).monospacedDigit()
                Spacer()
                Button {
                  photo = min(images.count - 1, photo + 1)
                } label: {
                  Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.disabled(photo == images.count - 1)
                  .accessibilityLabel(L10n.text("Следующее фото", locale: locale))
              }.buttonStyle(.glass).padding(16)
            }
            if let credit = entry?.imageCredit { ExerciseImageCreditView(credit: credit) }
          }
        } else {
          ContentUnavailableView(
            L10n.text("Фото недоступно", locale: locale), systemImage: "photo.badge.exclamationmark"
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(FitTheme.paper)
      .navigationTitle(L10n.exerciseName(exercise, locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale), systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly).accessibilityIdentifier("closeExerciseMedia")
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("exerciseMediaViewer")
    }
  }
}
