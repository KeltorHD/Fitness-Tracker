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
        Form {
          Section(L10n.text("Аккаунт", locale: locale)) {
            if let profile = model.profile {
              Text(profile.name).font(.headline)
              Text(profile.logins.joined(separator: ", ")).foregroundStyle(.secondary)
              Button(L10n.text("Способы входа", locale: locale)) { action = .manage }
              Button(L10n.text("Выйти из аккаунта", locale: locale)) { action = .logout }
            } else if model.loaded {
              Text(
                L10n.text("Войдите, чтобы сохранять резервные копии тренировок.", locale: locale))
              Button(L10n.text("Войти в аккаунт", locale: locale)) { action = .signIn }
                .accessibilityIdentifier("signInAccount")
            }
          }
          if model.profile != nil {
            Section {
              Button(
                L10n.text("Создать резервную копию", locale: locale),
                systemImage: "icloud.and.arrow.up"
              ) {
                confirmation = .upload
              }.accessibilityIdentifier("createServerBackup")
              Button(L10n.text("Обновить список", locale: locale)) { action = .refresh }
              if model.backups.isEmpty && !model.isBusy {
                Text(L10n.text("Серверных копий пока нет.", locale: locale)).foregroundStyle(
                  .secondary)
              }
              ForEach(model.backups) { backup in
                VStack(alignment: .leading, spacing: 8) {
                  Text(backup.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.headline)
                  Text(
                    ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file)
                  )
                  .font(.caption).foregroundStyle(.secondary)
                  Button(L10n.text("Восстановить…", locale: locale)) { action = .restore(backup) }
                  Button(L10n.text("Удалить копию", locale: locale), role: .destructive) {
                    confirmation = .delete(backup)
                  }
                }.padding(.vertical, 4)
              }
            } header: {
              Text(L10n.text("Резервные копии", locale: locale))
            } footer: {
              Text(
                L10n.text(
                  "До 10 копий по 20 МБ. В копию входят тренировки, планы и записи веса. Питание, фотографии и пульс не передаются. Восстановление добавляет новые записи после проверки.",
                  locale: locale))
            }
            Section {
              Button(L10n.text("Удалить аккаунт", locale: locale), role: .destructive) {
                confirmation = .deleteAccount
              }
            } footer: {
              Text(
                L10n.text(
                  "Выход и удаление аккаунта сохраняют историю на этом устройстве.", locale: locale)
              )
            }
          }
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
            Section { Label(L10n.text(notice, locale: locale), systemImage: "checkmark.circle") }
          }
        }
        .disabled(model.isBusy)
        .task { await model.load() }
        .task(id: action) {
          guard let requested = action else { return }
          await model.perform(requested) { url in
            do {
              return try await authentication.authenticate(
                using: url, callback: .customScheme("fitnesstracker"))
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin
            {
              throw CancellationError()
            }
          }
          if action == requested { action = nil }
        }
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
      isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
      titleVisibility: .visible, presenting: confirmation
    ) { pending in
      Button(
        L10n.text(pending == .upload ? "Отправить копию на сервер" : "Удалить", locale: locale),
        role: pending == .upload ? nil : .destructive
      ) {
        action = pending
        confirmation = nil
      }
      Button(L10n.text("Отменить", locale: locale), role: .cancel) { confirmation = nil }
    } message: { pending in
      Text(
        L10n.text(
          pending == .upload
            ? "Тренировки, планы и записи веса будут сохранены в вашем аккаунте на сервере."
            : pending == .deleteAccount
              ? "Аккаунт, привязанные способы входа и все серверные копии будут удалены. История на устройстве сохранится."
              : "Эта серверная копия будет удалена.", locale: locale))
    }
  }
}
