import AuthenticationServices
import SwiftUI

struct AccountBackupView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.webAuthenticationSession) private var authentication
  @State private var action: AccountBackupAction?
  @State private var confirmation: AccountBackupAction?

  var body: some View {
    Group {
      if let model = store.accountBackups {
        accountForm(model)
      } else {
        ContentUnavailableView(
          L10n.text("Резервные копии пока недоступны", locale: locale),
          systemImage: "externaldrive.badge.icloud",
          description: Text(
            L10n.text("Для переноса истории используйте импорт и экспорт файлов.", locale: locale)))
      }
    }
    .navigationTitle(L10n.text("Аккаунт и копии", locale: locale))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      L10n.text("Подтвердите действие", locale: locale),
      isPresented: confirmationPresented,
      titleVisibility: .visible, presenting: confirmation
    ) { pending in
      confirmationButtons(for: pending)
    } message: { pending in
      Text(confirmationMessage(for: pending))
    }
  }

  private var confirmationPresented: Binding<Bool> {
    Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
  }

  private func accountForm(_ model: AccountBackupViewModel) -> some View {
    Form {
      accountSection(model)
      if model.profile != nil {
        backupsSection(model)
        deleteAccountSection
      }
      statusSections(model)
    }
    .disabled(model.isBusy)
    .task { await model.load() }
    .task(id: action) { await performAction(using: model) }
  }

  private func accountSection(_ model: AccountBackupViewModel) -> some View {
    Section(L10n.text("Аккаунт", locale: locale)) {
      if let profile = model.profile {
        Text(profile.name).font(.headline)
        Text(profile.logins.joined(separator: ", ")).foregroundStyle(.secondary)
        Button(L10n.text("Способы входа", locale: locale)) { action = .manage }
        Button(L10n.text("Выйти из аккаунта", locale: locale)) { action = .logout }
      } else if model.loaded {
        Text(L10n.text("Войдите, чтобы сохранять резервные копии тренировок.", locale: locale))
        Button(L10n.text("Войти в аккаунт", locale: locale)) { action = .signIn }
          .accessibilityIdentifier("signInAccount")
      }
    }
  }

  private func backupsSection(_ model: AccountBackupViewModel) -> some View {
    Section {
      Button(
        L10n.text("Создать резервную копию", locale: locale), systemImage: "icloud.and.arrow.up"
      ) {
        confirmation = .upload
      }.accessibilityIdentifier("createServerBackup")
      Button(L10n.text("Обновить список", locale: locale)) { action = .refresh }
      if model.backups.isEmpty && !model.isBusy {
        Text(L10n.text("Серверных копий пока нет.", locale: locale)).foregroundStyle(.secondary)
      }
      ForEach(model.backups) { backup in
        backupRow(backup)
      }
    } header: {
      Text(L10n.text("Резервные копии", locale: locale))
    } footer: {
      Text(
        L10n.text(
          "До 10 копий по 30 МБ. В копию входят тренировки, планы и записи веса. Питание, фотографии и пульс не передаются. Восстановление добавляет новые записи после проверки.",
          locale: locale))
    }
  }

  private func backupRow(_ backup: RemoteBackup) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(backup.createdAt, format: .dateTime.day().month().year().hour().minute())
        .font(.headline)
      Text(ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
        .font(.caption).foregroundStyle(.secondary)
      Button(L10n.text("Восстановить…", locale: locale)) { action = .restore(backup) }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("restoreServerBackup_\(backup.id)")
      Button(L10n.text("Удалить копию", locale: locale), role: .destructive) {
        confirmation = .delete(backup)
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("deleteServerBackup_\(backup.id)")
    }.padding(.vertical, 4)
  }

  private var deleteAccountSection: some View {
    Section {
      Button(L10n.text("Удалить аккаунт", locale: locale), role: .destructive) {
        confirmation = .deleteAccount
      }
    } footer: {
      Text(
        L10n.text("Выход и удаление аккаунта сохраняют историю на этом устройстве.", locale: locale)
      )
    }
  }

  @ViewBuilder
  private func statusSections(_ model: AccountBackupViewModel) -> some View {
    if model.isBusy { Section { ProgressView(L10n.text("Загрузка…", locale: locale)) } }
    if let error = model.errorMessage {
      Section {
        Label(L10n.text(error, locale: locale), systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red).accessibilityIdentifier("serverAccountError")
        Button(L10n.text("Повторить", locale: locale)) {
          action = model.retryAction ?? .refresh
        }
      }
    }
    if let notice = model.notice {
      Section {
        Label(
          L10n.text(notice, locale: locale),
          systemImage: model.noticeIsSuccess ? "checkmark.circle" : "info.circle")
      }
    }
  }

  @ViewBuilder
  private func confirmationButtons(for pending: AccountBackupAction) -> some View {
    let title = L10n.text(
      pending == .upload ? "Отправить копию на сервер" : "Удалить", locale: locale)
    let role: ButtonRole? = pending == .upload ? nil : .destructive
    Button(title, role: role) {
      action = pending
      confirmation = nil
    }
    Button(L10n.text("Отменить", locale: locale), role: .cancel) { confirmation = nil }
  }

  private func confirmationMessage(for pending: AccountBackupAction) -> String {
    let message: String
    switch pending {
    case .upload:
      message = "Тренировки, планы и записи веса будут сохранены в вашем аккаунте на сервере."
    case .deleteAccount:
      message =
        "Аккаунт, привязанные способы входа и все серверные копии будут удалены. История на устройстве сохранится."
    default:
      message = "Эта серверная копия будет удалена."
    }
    return L10n.text(message, locale: locale)
  }

  private func performAction(using model: AccountBackupViewModel) async {
    guard let requested = action else { return }
    await model.perform(requested) { url in
      do {
        let callback: ASWebAuthenticationSession.Callback
        switch model.callback {
        case .https:
          callback = .https(host: model.callbackHost, path: ServerConfiguration.callbackPath)
        case .customScheme(let scheme):
          callback = .customScheme(scheme)
        }
        return try await authentication.authenticate(
          using: url,
          callback: callback,
          additionalHeaderFields: [:])
      } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        throw ServerError.authenticationCancelled
      }
    }
    if action == requested { action = nil }
  }
}
