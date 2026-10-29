import Foundation

protocol ExerciseImageLoading: Sendable {
  func data(for path: String) async throws -> Data
}

enum ExerciseImageError: Error {
  case invalidPath, missingResource, invalidImage, missingLoader
}

/// File I/O and the bounded cache live on this actor, never in SwiftUI body or MainActor.
actor ExerciseImageLoader: ExerciseImageLoading {
  private let directory: URL?
  private let cache = NSCache<NSString, NSData>()

  init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("ExerciseMedia")) {
    self.directory = directory
    cache.countLimit = 40
    cache.totalCostLimit = 32 * 1024 * 1024
  }

  func data(for path: String) async throws -> Data {
    try Task.checkCancellation()
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(".."), !path.contains(":") else {
      throw ExerciseImageError.invalidPath
    }
    if let cached = cache.object(forKey: path as NSString) { return cached as Data }
    guard let root = directory else { throw ExerciseImageError.missingResource }
    let directory = root.standardizedFileURL.resolvingSymlinksInPath()
    let url = directory.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(directory.path + "/") else { throw ExerciseImageError.invalidPath }
    let data = try Data(contentsOf: url)
    try Task.checkCancellation()
    cache.setObject(data as NSData, forKey: path as NSString, cost: data.count)
    return data
  }
}
