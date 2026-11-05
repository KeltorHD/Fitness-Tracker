import FitnessTrackerCore
import Foundation
import Observation

enum AccountBackupAction: Hashable {
  case signIn, manage, upload, refresh, logout, deleteAccount
  case restore(RemoteBackup)
  case delete(RemoteBackup)
}

@MainActor @Observable final class AccountBackupViewModel {
  private(set) var profile: AccountProfile?
  private(set) var backups: [RemoteBackup] = []
  private(set) var isBusy = false
  private(set) var loaded = false
  private(set) var errorMessage: String?
  private(set) var notice: String?
  private(set) var noticeIsSuccess = true
  private(set) var retryAction: AccountBackupAction?
  @ObservationIgnored private let session: AccountSession
  @ObservationIgnored private let client: RemoteBackupClient
  @ObservationIgnored private let codec = ServerArchiveCodec()
  @ObservationIgnored private let snapshot: () throws -> WorkoutArchive
  @ObservationIgnored private let preview: (WorkoutArchive) throws -> Void
  @ObservationIgnored private var pendingUpload: (id: UUID, data: Data)?

  init(
    session: AccountSession, client: RemoteBackupClient,
    snapshot: @escaping () throws -> WorkoutArchive,
    preview: @escaping (WorkoutArchive) throws -> Void
  ) {
    self.session = session
    self.client = client
    self.snapshot = snapshot
    self.preview = preview
  }

  var callbackHost: String { session.configuration.callbackHost }
  var callback: ServerCallback { session.configuration.callback }

  func load() async {
    await perform(.refresh) { _ in throw CancellationError() }
  }

  func perform(
    _ action: AccountBackupAction,
    browser: @MainActor (URL) async throws -> URL
  ) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    notice = nil
    noticeIsSuccess = true
    retryAction = nil
    defer {
      isBusy = false
      loaded = true
    }
    do {
      switch action {
      case .signIn, .manage:
        let attempt = try client.cryptography.authorizationAttempt()
        let url = try attempt.authorizationURL(
          configuration: session.configuration, manageAccount: action == .manage)
        let callback = try await browser(url)
        let previous = profile?.id
        profile = try await session.finishAuthorization(attempt, callback: callback)
        if previous != profile?.id { pendingUpload = nil }
        backups = []
        backups = try await client.list()
      case .refresh:
        profile = try await session.profile()
        if profile != nil { backups = try await client.list() } else { backups = [] }
      case .upload:
        if pendingUpload == nil {
          let archive = try snapshot()
          pendingUpload = (UUID(), try await codec.encode(archive))
        }
        guard let pendingUpload else { return }
        _ = try await client.upload(pendingUpload.data, id: pendingUpload.id)
        self.pendingUpload = nil
        notice = "Резервная копия сохранена."
        retryAction = .refresh
        backups = try await client.list()
        retryAction = nil
      case .restore(let backup):
        let data = try await client.download(backup)
        let archive = try await codec.decode(data)
        try Task.checkCancellation()
        try preview(archive)
      case .delete(let backup):
        try await client.delete(backup)
        backups.removeAll { $0.id == backup.id }
        notice = "Резервная копия удалена."
      case .logout:
        try await session.logout()
        clearAccount()
      case .deleteAccount:
        try await session.deleteAccount()
        clearAccount()
        notice = "Аккаунт и серверные копии удалены. История на устройстве сохранена."
      }
    } catch {
      if error as? ServerError == .signInRequired { clearAccount() }
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      if error as? ServerError == .authenticationCancelled {
        noticeIsSuccess = false
        notice = ServerError.authenticationCancelled.errorDescription
        return
      }
      retryAction = error as? ServerError == .signInRequired ? .signIn : (retryAction ?? action)
      errorMessage =
        (error as? ServerError)?.errorDescription
        ?? (error as? WorkoutArchiveError)?.errorDescription
        ?? "Не удалось выполнить действие. Повторите попытку."
    }
  }

  private func clearAccount() {
    profile = nil
    backups = []
    pendingUpload = nil
  }
}
