import FitSessionCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveTransferView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: ArchiveTransferViewModel

  var body: some View {
    NavigationStack {
      Form {
        Section("Экспорт") {
          if let workout = model.workout {
            Text(workout.name).font(.headline)
          } else {
            Text("Вся история тренировок и планы")
          }
          Picker("Формат", selection: $model.format) {
            ForEach(ArchiveExportFormat.allCases) { format in
              Text(format.title).tag(format)
            }
          }
          Button("Сохранить файл", systemImage: "square.and.arrow.up") { model.prepareExport() }
            .disabled(model.isLoading || model.isSaving).accessibilityIdentifier("exportArchive")
        }
        Section {
          Button("Выбрать файл", systemImage: "square.and.arrow.down") {
            model.showingImporter = true
          }
          .disabled(model.isLoading || model.isSaving).accessibilityIdentifier("chooseArchive")
          if model.isLoading {
            ProgressView("Чтение файла…")
            Button("Отменить чтение") { model.cancelReading() }
          }
        } header: {
          Text("Импорт")
        } footer: {
          Text(
            "Поддерживаются .fitsession и .json. Можно выбрать архив или прежний JSON одной тренировки."
          )
        }
        if let preview = model.preview {
          Section {
            Text(preview.fileName).font(.headline)
            LabeledContent("Новых тренировок", value: "\(preview.summary.addedWorkouts)")
            LabeledContent("Новых планов", value: "\(preview.summary.addedTemplates)")
            LabeledContent("Уже есть в приложении", value: "\(preview.summary.skippedExisting)")
            if preview.summary.skippedUnfinished > 0 {
              Text(
                "Незавершённых тренировок пропущено: \(preview.summary.skippedUnfinished). Одновременно можно восстановить одну сессию. Остальные остаются в исходном файле."
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            if preview.summary.hasChanges {
              Button("Импортировать", systemImage: "square.and.arrow.down") {
                model.requestImport()
              }
              .buttonStyle(.glassProminent).disabled(model.isSaving)
              .accessibilityIdentifier("confirmArchiveImport")
            } else {
              Text("Нет новых записей для импорта.").foregroundStyle(.secondary)
            }
            Button("Отменить") { model.cancelReading() }.disabled(model.isSaving)
          } header: {
            Text("Перед импортом")
          } footer: {
            Text(
              "Существующие записи сохранятся. Повторные UUID пропускаются, даже если содержимое отличается."
            )
          }
        }
        if model.isSaving { Section { ProgressView("Сохранение…") } }
        if let message = model.errorMessage {
          Section {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            if let request = model.request, model.preview == nil, !model.isLoading {
              Button("Повторить чтение") { model.selectFile(request.url) }
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
      .navigationTitle("Импорт и экспорт").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Готово") { dismiss() }.disabled(model.isSaving)
        }
      }
      .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.fitSession, .json])
      { result in
        switch result {
        case .success(let url): model.selectFile(url)
        case .failure(let error): model.pickerFailed(error)
        }
      }
      .fileExporter(
        isPresented: $model.showingExporter, item: model.exportDocument,
        contentTypes: [(model.exportDocument?.format ?? model.format).contentType],
        defaultFilename: model.workout == nil ? "FitSession-Archive" : "FitSession-Workout",
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
