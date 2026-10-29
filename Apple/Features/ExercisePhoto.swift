import SwiftUI
import UIKit

private struct ExerciseImageLoaderKey: EnvironmentKey {
  static let defaultValue: (any ExerciseImageLoading)? = nil
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
