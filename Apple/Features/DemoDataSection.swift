import SwiftUI

struct DemoDataSection: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(AppStore.self) private var store
  @State private var confirmation: Action?
  @State private var request: Action?
  private enum Action: Hashable { case load, leave }

  var body: some View {
    Section {
      if store.isDemoMode {
        Label(L10n.text("Демо-профиль открыт", locale: locale), systemImage: "sparkles")
      }
      Button {
        confirmation = .load
      } label: {
        Label(
          L10n.text(
            store.isDemoMode ? "Перезагрузить демо-данные" : "Открыть демо-профиль", locale: locale),
          systemImage: "tray.and.arrow.down")
      }.disabled(store.switchingDemo || (!store.isDemoMode && store.active != nil))
        .accessibilityIdentifier("loadDemoData")
      if store.isDemoMode {
        Button(L10n.text("Вернуться к моим данным", locale: locale)) { confirmation = .leave }
          .disabled(store.switchingDemo).accessibilityIdentifier("leaveDemoData")
      } else if store.active != nil {
        Text(
          L10n.text("Завершите текущую тренировку перед открытием демо-профиля.", locale: locale)
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      if store.switchingDemo { ProgressView(L10n.text("Подготовка данных…", locale: locale)) }
    } header: {
      Text(L10n.text("Демонстрационные данные", locale: locale))
    } footer: {
      Text(
        L10n.text(
          "24 тренировки за 8 недель и 3 плана. Демо открывается отдельно от личной истории и не синхронизируется. Настройки приложения общие для обоих профилей.",
          locale: locale))
    }
    .confirmationDialog(
      L10n.text("Демонстрационные данные", locale: locale),
      isPresented: Binding(
        get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
      titleVisibility: .visible
    ) {
      if confirmation == .load {
        Button(
          L10n.text(
            store.isDemoMode ? "Перезагрузить демо-данные" : "Открыть демо-профиль", locale: locale)
        ) {
          request = .load
        }.accessibilityIdentifier("confirmLoadDemoData")
      } else if confirmation == .leave {
        Button(L10n.text("Вернуться к моим данным", locale: locale)) { request = .leave }
          .accessibilityIdentifier("confirmLeaveDemoData")
      }
      Button(L10n.text("Отмена", locale: locale), role: .cancel) { confirmation = nil }
    } message: {
      Text(
        L10n.text(
          store.isDemoMode
            ? "Изменения в демо-профиле будут сброшены. Ваша личная история останется без изменений."
            : "Демо-тренировки откроются отдельно. Ваша личная история останется без изменений.",
          locale: locale))
    }
    .task(id: request) {
      switch request {
      case .load: await store.loadDemoData(calendar: calendar)
      case .leave: await store.leaveDemoMode()
      case nil: break
      }
      request = nil
    }
  }
}

struct DemoModeBanner: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  var body: some View {
    Label(L10n.text("Демо-режим · данные вымышлены", locale: locale), systemImage: "sparkles")
      .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(8)
      .background(colorTheme.accent.opacity(0.12)).accessibilityIdentifier("demoModeBanner")
  }
}
