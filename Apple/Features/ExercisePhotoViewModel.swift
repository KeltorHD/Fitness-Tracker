import Foundation
import Observation
import UIKit

@MainActor @Observable final class ExercisePhotoViewModel {
  private(set) var image: UIImage?
  private(set) var failed = false
  @ObservationIgnored private let loader: (any ExerciseImageLoading)?

  init(loader: (any ExerciseImageLoading)?) { self.loader = loader }

  func load(path: String) async {
    image = nil
    failed = false
    do {
      guard let loader else { throw ExerciseImageError.missingLoader }
      let data = try await loader.data(for: path)
      try Task.checkCancellation()
      guard let image = UIImage(data: data) else { throw ExerciseImageError.invalidImage }
      self.image = image
    } catch {
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      AppErrorReporter.record(error, operation: "loadExercisePhoto")
      failed = true
    }
  }
}
