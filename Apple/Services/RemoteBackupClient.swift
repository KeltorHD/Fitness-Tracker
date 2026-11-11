import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct RemoteBackupClient: Sendable {
  let session: AccountSession
  let cryptography: any ServerCryptography

  func list() async throws -> [RemoteBackup] {
    let request = URLRequest(
      url: session.configuration.backendURL.appendingPathComponent("v1/backups"))
    let result = try ServerJSON.decode(
      [RemoteBackup].self, from: await session.authorizedData(request))
    guard result.count <= 10, Set(result.map(\.id)).count == result.count else {
      throw ServerError.invalidResponse
    }
    for backup in result { try validate(backup) }
    return result
  }

  func upload(_ data: Data, id: UUID) async throws -> RemoteBackup {
    guard !data.isEmpty, data.count <= WorkoutArchiveCodec.maximumBytes else {
      throw WorkoutArchiveError.tooLarge
    }
    var request = URLRequest(url: endpoint(id))
    request.httpMethod = "PUT"
    request.httpBody = data
    request.setValue("application/vnd.fitlife+json", forHTTPHeaderField: "Content-Type")
    let result = try ServerJSON.decode(
      RemoteBackup.self, from: await session.authorizedData(request))
    try validate(result)
    guard result.id == id, result.size == data.count, result.sha256 == cryptography.sha256(data)
    else {
      throw ServerError.invalidResponse
    }
    return result
  }

  func download(_ backup: RemoteBackup) async throws -> Data {
    try validate(backup)
    let data = try await session.authorizedData(
      URLRequest(url: endpoint(backup.id)), maximumBytes: WorkoutArchiveCodec.maximumBytes)
    guard data.count == backup.size, cryptography.sha256(data) == backup.sha256 else {
      throw ServerError.invalidResponse
    }
    return data
  }

  func delete(_ backup: RemoteBackup) async throws {
    var request = URLRequest(url: endpoint(backup.id))
    request.httpMethod = "DELETE"
    _ = try await session.authorizedData(request)
  }

  private func endpoint(_ id: UUID) -> URL {
    session.configuration.backendURL.appendingPathComponent(
      "v1/backups/\(id.uuidString.lowercased())")
  }

  private func validate(_ backup: RemoteBackup) throws {
    guard backup.size > 0, backup.size <= WorkoutArchiveCodec.maximumBytes,
      (1...WorkoutArchive.currentVersion).contains(backup.archiveVersion),
      backup.sha256.count == 64,
      backup.sha256.allSatisfy({ "0123456789abcdef".contains($0) })
    else { throw ServerError.invalidResponse }
  }
}

actor ServerArchiveCodec {
  func encode(_ archive: WorkoutArchive) throws -> Data { try WorkoutArchiveCodec.encode(archive) }
  func decode(_ data: Data) throws -> WorkoutArchive { try WorkoutArchiveCodec.decode(data) }
}
