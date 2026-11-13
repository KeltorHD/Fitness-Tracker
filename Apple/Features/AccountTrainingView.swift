import AuthenticationServices
import FitLifeCore
import SwiftUI

struct AccountTrainingView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.webAuthenticationSession) private var authentication
  @State private var action: AccountTrainingAction?
  @State private var deletingAccount = false

  var body: some View {
    Group {
      if let model = store.account {
        Form {
          accountSection(model)
          syncSection(model)
          if !model.sync.conflicts.isEmpty {
            Section(L10n.text("Расхождения данных", locale: locale)) {
              ForEach(model.sync.conflicts) { conflict in
                NavigationLink {
                  TrainingConflictView(model: model, conflict: conflict)
                } label: {
                  Label(
                    conflictTitle(conflict),
                    systemImage: "arrow.triangle.branch")
                }
              }
            }
          }
          if model.localAccounts.count > 1
            || !model.isAccountJournalOpen && !model.localAccounts.isEmpty
          {
            Section(L10n.text("Журналы на устройстве", locale: locale)) {
              ForEach(model.localAccounts) { account in
                Button {
                  action = .openLocalJournal(account.namespace)
                } label: {
                  HStack {
                    VStack(alignment: .leading) {
                      Text(account.name)
                      Text(account.server).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.currentNamespace == account.namespace {
                      Spacer()
                      Image(systemName: "checkmark").accessibilityLabel(
                        L10n.text("Текущий журнал", locale: locale))
                    }
                  }
                }.disabled(model.currentNamespace == account.namespace)
              }
            }
          }
          if let error = model.errorMessage {
            Section {
              Label(L10n.text(error, locale: locale), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red).accessibilityIdentifier("serverAccountError")
              Button(L10n.text("Повторить", locale: locale)) { action = .refresh }
            }
          }
          if let notice = model.notice {
            Section { Text(L10n.text(notice, locale: locale)) }
          }
          if model.profile != nil {
            Section {
              Button(L10n.text("Удалить аккаунт", locale: locale), role: .destructive) {
                deletingAccount = true
              }
              .accessibilityIdentifier("deleteServerAccount")
            } footer: {
              Text(
                L10n.text(
                  "Выход и удаление аккаунта сохраняют историю на этом устройстве.", locale: locale)
              )
            }
          }
        }
        .disabled(model.isBusy || store.isDemoMode)
        .task { await model.load() }
        .task(id: action) { await performAction(using: model) }
      } else {
        ContentUnavailableView(
          L10n.text("Синхронизация с сервером пока недоступна.", locale: locale),
          systemImage: "icloud.slash",
          description: Text(
            L10n.text("Для переноса истории используйте импорт и экспорт файлов.", locale: locale)))
      }
    }
    .navigationTitle(L10n.text("Аккаунт и синхронизация", locale: locale))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      L10n.text("Удалить аккаунт", locale: locale), isPresented: $deletingAccount,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Удалить", locale: locale), role: .destructive) { action = .deleteAccount }
      Button(L10n.text("Отменить", locale: locale), role: .cancel) {}
    } message: {
      Text(
        L10n.text(
          "Аккаунт, способы входа и весь серверный журнал, включая пульс, будут удалены. Данные на устройстве сохранятся.",
          locale: locale))
    }
  }

  private func conflictTitle(_ conflict: TrainingConflict) -> String {
    if let title = conflict.remote.value?.title { return title }
    let kind: String
    switch conflict.id.kind {
    case .workout: kind = "Тренировка"
    case .template: kind = "Шаблоны"
    case .bodyWeight: kind = "Вес тела"
    case .heartRate: kind = "Пульс"
    case .foodEntry: kind = "Питание"
    case .waterEntry: kind = "Вода"
    case .supplementEntry: kind = "Приём добавки"
    case .supplementPlan: kind = "Расписание добавки"
    case .nutritionProfile: kind = "Цели и избранные продукты"
    }
    return L10n.text(kind, locale: locale)
  }

  private func accountSection(_ model: AccountTrainingViewModel) -> some View {
    Section(L10n.text("Аккаунт", locale: locale)) {
      if let profile = model.profile {
        Text(profile.name).font(.headline)
        Text(profile.logins.joined(separator: ", ")).foregroundStyle(.secondary)
        Button(L10n.text("Способы входа", locale: locale)) { action = .manage }
        Button(L10n.text("Выйти из аккаунта", locale: locale)) { action = .logout }
          .accessibilityIdentifier("signOutAccount")
        if !model.isAccountJournalOpen {
          Button(L10n.text("Открыть журнал аккаунта", locale: locale)) {
            action = .openAccountJournal
          }
        }
      } else if model.loaded {
        Text(
          L10n.text(
            "Войдите для автоматической синхронизации тренировок и питания между устройствами.",
            locale: locale))
        Button(L10n.text("Войти в аккаунт", locale: locale)) { action = .signIn }
          .accessibilityIdentifier("signInAccount")
      } else {
        ProgressView(L10n.text("Загрузка…", locale: locale))
      }
    }
  }

  private func syncSection(_ model: AccountTrainingViewModel) -> some View {
    Section {
      if model.sync.isSyncing {
        ProgressView(L10n.text("Синхронизация…", locale: locale))
      } else if model.isAccountJournalOpen && model.profile != nil {
        Label(
          L10n.text("Изменения сохраняются автоматически", locale: locale),
          systemImage: "arrow.triangle.2.circlepath"
        )
        .accessibilityIdentifier("automaticTrainingSync")
      } else {
        Label(L10n.text("Журнал доступен офлайн", locale: locale), systemImage: "iphone")
      }
      if let date = model.sync.lastSyncedAt {
        LabeledContent(L10n.text("Последняя синхронизация", locale: locale)) {
          Text(date, format: .dateTime.day().month().hour().minute())
        }
      }
      if let error = model.sync.errorMessage {
        Text(L10n.text(error, locale: locale)).foregroundStyle(.red)
          .accessibilityIdentifier("trainingSyncError")
      }
      if model.isAccountJournalOpen && model.profile != nil {
        Button(L10n.text("Синхронизировать сейчас", locale: locale)) {
          if model.sync.needsSignIn {
            action = .signIn
          } else {
            model.sync.requestSync(immediately: true)
          }
        }.disabled(model.sync.isSyncing).accessibilityIdentifier("syncTrainingNow")
      }
    } header: {
      Text(L10n.text("Синхронизация", locale: locale))
    } footer: {
      Text(
        L10n.text(
          "Тренировки, планы, вес, сохранённый пульс, питание с фотографиями, вода, цели, избранные продукты, добавки и расписания автоматически передаются в ваш аккаунт. Изменения офлайн отправятся при подключении. Источники здоровья подключаются отдельно.",
          locale: locale))
    }
  }

  private func performAction(using model: AccountTrainingViewModel) async {
    guard let requested = action else { return }
    await model.perform(requested) { url in
      do {
        let callback: ASWebAuthenticationSession.Callback
        switch model.callback {
        case .https:
          callback = .https(host: model.callbackHost, path: ServerConfiguration.callbackPath)
        case .customScheme(let scheme): callback = .customScheme(scheme)
        }
        return try await authentication.authenticate(
          using: url, callback: callback, additionalHeaderFields: [:])
      } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        throw ServerError.authenticationCancelled
      }
    }
    if action == requested { action = nil }
  }
}
