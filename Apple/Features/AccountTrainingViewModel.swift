import FitLifeCore
import Foundation
import Observation

enum AccountTrainingAction: Hashable {
  case signIn, manage, refresh, logout, deleteAccount, openAccountJournal
  case openLocalJournal(String)
  case resolve(
    TrainingRecordKey, revision: Int64, localFingerprint: String?, pulseFingerprint: String?,
    keepLocal: Bool)
}

@MainActor @Observable final class AccountTrainingViewModel {
  private(set) var profile: AccountProfile?
  private(set) var loaded = false
  private(set) var isBusy = false
  private(set) var errorMessage: String?
  private(set) var notice: String?
  private(set) var localAccounts: [LocalTrainingAccount] = []
  private(set) var expectedNamespace: String?
  let sync: TrainingSyncCoordinator
  @ObservationIgnored private let session: AccountSession
  @ObservationIgnored private let storage: any TrainingSyncStateStoring
  @ObservationIgnored private let cryptography: any ServerCryptography
  @ObservationIgnored private let activate: @MainActor (String) async throws -> Void
  @ObservationIgnored private let selection: @MainActor () -> TrainingAccountSelection?
  @ObservationIgnored private var resumeTask: Task<Void, Never>?

  init(
    session: AccountSession, sync: TrainingSyncCoordinator, storage: any TrainingSyncStateStoring,
    cryptography: any ServerCryptography,
    activate: @escaping @MainActor (String) async throws -> Void,
    selection: @escaping @MainActor () -> TrainingAccountSelection?
  ) {
    self.session = session
    self.sync = sync
    self.storage = storage
    self.cryptography = cryptography
    self.activate = activate
    self.selection = selection
  }

  var callbackHost: String { session.configuration.callbackHost }
  var callback: ServerCallback { session.configuration.callback }
  var isAccountJournalOpen: Bool {
    expectedNamespace != nil && selection()?.currentAccountID == expectedNamespace
  }
  var currentNamespace: String? { selection()?.currentAccountID }

  func load() async { await perform(.refresh) { _ in throw CancellationError() } }

  func perform(_ action: AccountTrainingAction, browser: @MainActor (URL) async throws -> URL) async
  {
    guard !isBusy else { return }
    resumeTask?.cancel()
    resumeTask = nil
    isBusy = true
    errorMessage = nil
    notice = nil
    defer {
      isBusy = false
      loaded = true
    }
    do {
      switch action {
      case .signIn, .manage:
        await sync.disconnect()
        let attempt = try cryptography.authorizationAttempt()
        let url = try attempt.authorizationURL(
          configuration: session.configuration, manageAccount: action == .manage)
        let callback = try await browser(url)
        profile = try await session.finishAuthorization(attempt, callback: callback)
        expectedNamespace = try profile.map(namespace)
        try await openAccountJournal()
      case .refresh:
        profile = try await session.profile()
        expectedNamespace = try profile.map(namespace)
        localAccounts = try await storage.accounts()
        if profile == nil {
          await sync.disconnect()
        } else if selection()?.firstAccountID == nil || isAccountJournalOpen {
          try await openAccountJournal()
        } else {
          await sync.disconnect()
          notice = "Открыт другой локальный журнал. Синхронизация приостановлена."
        }
      case .openAccountJournal:
        try await openAccountJournal()
      case .openLocalJournal(let namespace):
        guard localAccounts.contains(where: { $0.namespace == namespace }) else {
          throw TrainingSyncError.invalidData
        }
        await sync.disconnect()
        try await activate(namespace)
        if isAccountJournalOpen {
          try await openAccountJournal()
        } else {
          notice =
            "Открыт локальный журнал. Для его синхронизации войдите в соответствующий аккаунт."
        }
      case .logout:
        await sync.disconnect()
        try await session.logout()
        profile = nil
        expectedNamespace = nil
        notice = "Вы вышли из аккаунта. Журнал на устройстве сохранён."
      case .deleteAccount:
        await sync.disconnect()
        try await session.deleteAccount()
        profile = nil
        expectedNamespace = nil
        notice = "Аккаунт и серверный журнал удалены. Данные на устройстве сохранены."
      case .resolve(let key, let revision, let fingerprint, let pulseFingerprint, let keepLocal):
        guard
          let conflict = sync.conflicts.first(where: {
            $0.id == key && $0.remote.revision == revision
          })
        else {
          notice = "Серверная запись изменилась. Обновите предпросмотр."
          return
        }
        await sync.resolve(
          conflict, keepLocal: keepLocal, expectedFingerprint: fingerprint,
          expectedPulseFingerprint: pulseFingerprint)
      }
    } catch {
      if Task.isCancelled || error is CancellationError {
        // The account model outlives the browser view. Restore the matching journal after its task closes.
        resumeTask = Task { [weak self] in
          guard !Task.isCancelled else { return }
          await self?.foreground()
        }
        return
      }
      if error as? ServerError == .signInRequired {
        profile = nil
        expectedNamespace = nil
        await sync.disconnect()
      }
      if error as? ServerError == .authenticationCancelled {
        notice = ServerError.authenticationCancelled.errorDescription
      } else {
        errorMessage = message(error)
      }
      if isAccountJournalOpen, let expectedNamespace, !sync.isConnected(to: expectedNamespace) {
        do { try await sync.connect(expectedNamespace) } catch { errorMessage = message(error) }
      }
    }
  }

  func foreground() async {
    guard !Task.isCancelled, !isBusy else { return }
    if !loaded {
      await load()
    } else if isAccountJournalOpen && profile != nil {
      if let expectedNamespace, !sync.isConnected(to: expectedNamespace) {
        do { try await sync.connect(expectedNamespace) } catch { errorMessage = message(error) }
      } else {
        sync.requestSync(immediately: true)
      }
    }
  }
  func suspend() async { await sync.pause() }
  func resolutionAction(
    _ conflict: TrainingConflict, local: TrainingValue?, pulse: TrainingValue? = nil,
    keepLocal: Bool
  ) throws -> AccountTrainingAction {
    .resolve(
      conflict.id, revision: conflict.remote.revision,
      localFingerprint: try local.map { cryptography.sha256(try $0.canonicalData()) },
      pulseFingerprint: try pulse.map { cryptography.sha256(try $0.canonicalData()) },
      keepLocal: keepLocal)
  }

  private func openAccountJournal() async throws {
    guard let profile, let expectedNamespace else { throw ServerError.signInRequired }
    if !isAccountJournalOpen {
      await sync.disconnect()
      try await activate(expectedNamespace)
    }
    try await storage.register(
      LocalTrainingAccount(
        namespace: expectedNamespace, name: profile.name,
        server: session.configuration.authenticationURL.host ?? ""))
    localAccounts = try await storage.accounts()
    if !sync.isConnected(to: expectedNamespace) {
      try await sync.connect(expectedNamespace)
    } else {
      sync.requestSync(immediately: true)
    }
  }

  private func namespace(_ profile: AccountProfile) throws -> String {
    guard let id = UUID(uuidString: profile.id) else { throw ServerError.invalidResponse }
    let origin = cryptography.sha256(
      Data(session.configuration.authenticationURL.absoluteString.utf8))
    return origin + "-" + id.uuidString.lowercased()
  }
  private func message(_ error: any Error) -> String {
    if let error = error as? ServerError {
      return error.errorDescription ?? "Не удалось выполнить действие."
    }
    if error as? TrainingSyncError == .activeWorkout {
      return "Завершите текущую тренировку перед сменой журнала."
    }
    return "Не удалось открыть синхронизацию. Локальные данные сохранены; повторите попытку."
  }
}
