import FitnessTrackerCore
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
      .frame(height: 270)
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
