import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

protocol TrainingRemoteServing: Sendable {
  func changes(after: Int64) async throws -> TrainingPage
  func apply(_ mutations: [TrainingMutation]) async throws -> [TrainingChange]
}

struct RemoteTrainingClient: TrainingRemoteServing {
  let session: AccountSession
  static let maximumRequestBytes = 30 * 1024 * 1024
  private static let maximumResponseBytes = 32 * 1024 * 1024

  func changes(after cursor: Int64) async throws -> TrainingPage {
    let endpoint = session.configuration.backendURL.appendingPathComponent("v1/training/changes")
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      throw ServerError.invalidConfiguration
    }
    components.queryItems = [
      URLQueryItem(name: "after", value: String(cursor)), URLQueryItem(name: "limit", value: "50"),
      URLQueryItem(
        name: "kinds", value: TrainingKind.allCases.map(\.rawValue).joined(separator: ",")),
    ]
    guard let url = components.url else { throw ServerError.invalidConfiguration }
    let page: TrainingPage
    do {
      page = try decode(from: await send(URLRequest(url: url)))
    } catch let error as ServerTrainingError where error.code == "invalid_training_kind" {
      throw ServerTrainingError(code: "server_update_required", current: nil)
    }
    try page.validate(after: cursor)
    return page
  }

  func apply(_ mutations: [TrainingMutation]) async throws -> [TrainingChange] {
    guard !mutations.isEmpty, mutations.count <= 100,
      Set(mutations.map(\.key)).count == mutations.count
    else { throw TrainingSyncError.invalidData }
    let data = try TrainingCoding.encoder().encode(mutations)
    guard data.count <= Self.maximumRequestBytes else { throw WorkoutArchiveError.tooLarge }
    var request = URLRequest(
      url: session.configuration.backendURL.appendingPathComponent("v1/training/changes"))
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let response: Data
    do { response = try await send(request) } catch let error as ServerTrainingError
      where error.code == "training_conflict"
    {
      guard error.current == nil || mutations.contains(where: { $0.key == error.current?.key })
      else {
        throw ServerError.invalidResponse
      }
      throw error
    } catch let error as ServerTrainingError
      where ["invalid_training_mutation", "invalid_training_kind"].contains(error.code)
      && mutations.contains(where: { $0.key.kind.isNutrition || $0.key.kind == .exerciseLink })
    {
      throw ServerTrainingError(code: "server_update_required", current: nil)
    }
    let changes: [TrainingChange] = try decode(from: response)
    guard changes.count == mutations.count else { throw ServerError.invalidResponse }
    for (mutation, change) in zip(mutations, changes) {
      guard mutation.key == change.key,
        try mutation.value?.canonicalData() == change.value?.canonicalData(),
        change.revision >= mutation.baseRevision
      else { throw ServerError.invalidResponse }
    }
    return changes
  }

  private func send(_ request: URLRequest) async throws -> Data {
    do {
      return try await session.authorizedData(request, maximumBytes: Self.maximumResponseBytes)
    } catch ServerError.rejected(404) {
      throw ServerTrainingError(code: "server_update_required", current: nil)
    }
  }

  private func decode<T: Decodable>(from data: Data) throws -> T {
    do { return try TrainingCoding.decoder().decode(T.self, from: data) } catch {
      throw ServerError.invalidResponse
    }
  }
}
