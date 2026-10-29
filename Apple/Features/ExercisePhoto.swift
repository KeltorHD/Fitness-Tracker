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
          Button("Повторить загрузку фото", systemImage: "arrow.clockwise") { attempt += 1 }
            .labelStyle(.iconOnly)
        }.accessibilityLabel("Фото недоступно")
      } else {
        ProgressView().accessibilityLabel("Загрузка фото")
      }
    }
    .task(id: Request(path: path, attempt: attempt)) {
      let model = ExercisePhotoViewModel(loader: loader)
      self.model = model
      await model.load(path: path)
    }
  }
}
