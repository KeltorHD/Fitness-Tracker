import FitnessTrackerCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveTransferView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: ArchiveTransferViewModel

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("Экспорт", locale: locale)) {
          if let workout = model.workout {
            Text(workout.name).font(.headline)
          } else {
            Text(L10n.text("Вся история тренировок, планы и записи веса", locale: locale))
          }
          Picker(L10n.text("Формат", locale: locale), selection: $model.format) {
            ForEach(ArchiveExportFormat.allCases) { format in
              Text(format.title).tag(format)
            }
          }
          Button(L10n.text("Сохранить файл", locale: locale), systemImage: "square.and.arrow.up") {
            model.prepareExport()
          }
          .disabled(model.isLoading || model.isSaving).accessibilityIdentifier("exportArchive")
        }
        Section {
          Button(L10n.text("Выбрать файл", locale: locale), systemImage: "square.and.arrow.down") {
            model.showingImporter = true
          }
          .disabled(model.isLoading || model.isSaving).accessibilityIdentifier("chooseArchive")
          if model.isLoading {
            ProgressView(L10n.text("Чтение файла…", locale: locale))
            Button(L10n.text("Отменить чтение", locale: locale)) { model.cancelReading() }
          }
        } header: {
          Text(L10n.text("Импорт", locale: locale))
        } footer: {
          Text(
            L10n.text(
              "Поддерживаются .fitnesstracker, .json и CSV-журнал тренировок. Можно выбрать файл из другого приложения.",
              locale: locale)
          )
        }
        if let preview = model.preview {
          Section {
            Text(preview.fileName).font(.headline)
            if preview.fileName.lowercased().hasSuffix(".csv") {
              Text(
                L10n.format(
                  "Даты CSV прочитаны в часовом поясе %@.", TimeZone.current.identifier,
                  locale: locale)
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            if preview.unknownDurationCount > 0 {
              Text(
                L10n.format(
                  "Без длительности: %@. В истории будет «—».",
                  String(preview.unknownDurationCount), locale: locale)
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            if preview.cancelledCount > 0 {
              Text(
                L10n.format(
                  "Без выполненных подходов: %@. Сессии сохранятся как отменённые.",
                  String(preview.cancelledCount), locale: locale)
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent(
              L10n.text("Новых тренировок", locale: locale),
              value: "\(preview.summary.addedWorkouts)")
            LabeledContent(
              L10n.text("Новых планов", locale: locale), value: "\(preview.summary.addedTemplates)")
            LabeledContent(
              L10n.text("Новых записей веса", locale: locale),
              value: "\(preview.summary.addedBodyWeights)")
            LabeledContent(
              L10n.text("Уже есть в приложении", locale: locale),
              value: "\(preview.summary.skippedExisting)")
            if preview.summary.skippedUnfinished > 0 {
              Text(
                L10n.format(
                  "Незавершённых тренировок пропущено: %@. Одновременно можно восстановить одну сессию. Остальные остаются в исходном файле.",
                  String(preview.summary.skippedUnfinished), locale: locale)
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            if preview.summary.hasChanges {
              Button(
                L10n.text("Импортировать", locale: locale), systemImage: "square.and.arrow.down"
              ) {
                model.requestImport()
              }
              .buttonStyle(.glassProminent).disabled(model.isSaving)
              .accessibilityIdentifier("confirmArchiveImport")
            } else {
              Text(L10n.text("Нет новых записей для импорта.", locale: locale)).foregroundStyle(
                .secondary)
            }
            Button(L10n.text("Отменить", locale: locale)) { model.cancelReading() }.disabled(
              model.isSaving)
          } header: {
            Text(L10n.text("Перед импортом", locale: locale))
          } footer: {
            Text(
              L10n.text(
                "Существующие записи сохранятся. Повторные UUID пропускаются, даже если содержимое отличается.",
                locale: locale)
            )
          }
        }
        if model.isSaving { Section { ProgressView(L10n.text("Сохранение…", locale: locale)) } }
        if let message = model.errorMessage {
          Section {
            Label(L10n.text(message, locale: locale), systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
            if let request = model.request, model.preview == nil, !model.isLoading {
              Button(L10n.text("Повторить чтение", locale: locale)) {
                model.selectFile(request.url)
              }
            }
          }
        }
        if let notice = model.notice {
          Section {
            Label(notice, systemImage: "checkmark.circle").accessibilityIdentifier(
              "archiveTransferResult")
          }
        }
      }
      .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
      .navigationTitle(L10n.text("Импорт и экспорт", locale: locale)).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Готово", locale: locale)) { dismiss() }.disabled(model.isSaving)
        }
      }
      .fileImporter(
        isPresented: $model.showingImporter,
        allowedContentTypes: [.fitnessTracker, .legacyWorkoutArchive, .json, .commaSeparatedText]
      ) { result in
        switch result {
        case .success(let url): model.selectFile(url)
        case .failure(let error): model.pickerFailed(error)
        }
      }
      .fileExporter(
        isPresented: $model.showingExporter, item: model.exportDocument,
        contentTypes: [(model.exportDocument?.format ?? model.format).contentType],
        defaultFilename: model.workout == nil ? "FitnessTracker-Archive" : "FitnessTracker-Workout",
        onCompletion: model.exportCompleted, onCancellation: model.exportCancelled
      )
      .task(id: model.request?.id) { if let request = model.request { await model.load(request) } }
      .task(id: model.commitRequestID) {
        if model.commitRequestID != nil { await model.confirmImport() }
      }
      .interactiveDismissDisabled(model.isSaving)
    }
  }
}

private struct ArchiveTransferPresenter: ViewModifier {
  @Environment(AppStore.self) private var store
  let eligible: Bool

  func body(content: Content) -> some View {
    let model = store.archiveTransfer
    content.sheet(
      isPresented: Binding(
        get: { eligible && model.isPresented },
        set: { if eligible { model.isPresented = $0 } })
    ) {
      ArchiveTransferView(model: model).tint(FitTheme.accent)
    }
  }
}

extension View {
  func archiveTransferPresenter(when eligible: Bool) -> some View {
    modifier(ArchiveTransferPresenter(eligible: eligible))
  }
}
