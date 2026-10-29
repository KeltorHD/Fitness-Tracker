import FitSessionCore
import Foundation
import Observation

struct ArchiveReadRequest: Identifiable {
  let id = UUID()
  let url: URL
}

struct ArchiveImportPreview {
  let archive: WorkoutArchive
  let fileName: String
  let summary: ArchiveImportSummary
}

@MainActor @Observable final class ArchiveTransferViewModel {
  var isPresented = false
  var showingImporter = false
  var showingExporter = false
  var format = ArchiveExportFormat.fitSession
  private(set) var workout: Workout?
  private(set) var request: ArchiveReadRequest?
  private(set) var commitRequestID: UUID?
  private(set) var preview: ArchiveImportPreview?
  private(set) var exportDocument: ArchiveDocument?
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var errorMessage: String?
  private(set) var notice: String?
  @ObservationIgnored private let files: any ArchiveFileHandling
  @ObservationIgnored private let snapshot: () throws -> WorkoutArchive
  @ObservationIgnored private let plan: (WorkoutArchive) throws -> ArchiveImportSummary
  @ObservationIgnored private let commit: (WorkoutArchive) throws -> ArchiveImportSummary
  @ObservationIgnored private var pendingOpenURL: URL?

  init(
    files: any ArchiveFileHandling,
    snapshot: @escaping () throws -> WorkoutArchive,
    plan: @escaping (WorkoutArchive) throws -> ArchiveImportSummary,
    commit: @escaping (WorkoutArchive) throws -> ArchiveImportSummary
  ) {
    self.files = files
    self.snapshot = snapshot
    self.plan = plan
    self.commit = commit
  }

  func present(workout: Workout? = nil, format: ArchiveExportFormat = .fitSession) {
    guard !isSaving else { return }
    cancelReading()
    self.workout = workout
    self.format = format
    notice = nil
    errorMessage = nil
    isPresented = true
  }

  func openFile(_ url: URL) {
    guard !isSaving else {
      pendingOpenURL = url
      return
    }
    workout = nil
    isPresented = true
    selectFile(url)
  }

  func selectFile(_ url: URL) {
    guard !isSaving else { return }
    preview = nil
    commitRequestID = nil
    notice = nil
    errorMessage = nil
    request = ArchiveReadRequest(url: url)
    isLoading = true
  }

  func cancelReading() {
    request = nil
    preview = nil
    isLoading = false
    commitRequestID = nil
    errorMessage = nil
  }

  func load(_ request: ArchiveReadRequest) async {
    guard self.request?.id == request.id else { return }
    isLoading = true
    defer { if self.request?.id == request.id { isLoading = false } }
    do {
      let archive = try await files.read(request.url)
      try Task.checkCancellation()
      guard self.request?.id == request.id else { return }
      let summary = try plan(archive)
      preview = ArchiveImportPreview(
        archive: archive, fileName: request.url.lastPathComponent, summary: summary)
    } catch {
      guard self.request?.id == request.id, !Task.isCancelled, !(error is CancellationError) else {
        return
      }
      fail(
        error, operation: "readArchive",
        fallback: "Не удалось прочитать файл. Попробуйте выбрать его ещё раз.")
    }
  }

  func requestImport() {
    if preview?.summary.hasChanges == true && !isSaving && !isLoading { commitRequestID = UUID() }
  }

  func confirmImport() async {
    guard let preview, let requestID = commitRequestID, !isSaving else { return }
    isSaving = true
    errorMessage = nil
    defer {
      isSaving = false
      if commitRequestID == requestID { commitRequestID = nil }
      if let url = pendingOpenURL {
        pendingOpenURL = nil
        openFile(url)
      }
    }
    await Task.yield()
    guard !Task.isCancelled, commitRequestID == requestID else { return }
    do {
      let result = try commit(preview.archive)
      self.preview = nil
      request = nil
      notice =
        "Добавлено тренировок: \(result.addedWorkouts), планов: \(result.addedTemplates). Пропущено: \(result.skippedExisting + result.skippedUnfinished)."
    } catch {
      fail(
        error, operation: "importArchive",
        fallback: "Не удалось сохранить импорт. Попробуйте ещё раз.")
    }
  }

  func prepareExport() {
    guard !isSaving, !isLoading else { return }
    errorMessage = nil
    notice = nil
    do {
      let archive = try workout.map { WorkoutArchive(workouts: [$0], templates: []) } ?? snapshot()
      try WorkoutArchiveCodec.validate(archive)
      exportDocument = ArchiveDocument(archive: archive, files: files, format: format)
      showingExporter = true
    } catch {
      fail(
        error, operation: "prepareArchiveExport",
        fallback: "Не удалось подготовить файл. Попробуйте ещё раз.")
    }
  }

  func exportCompleted(_ result: Result<URL, any Error>) {
    exportDocument = nil
    switch result {
    case .success: notice = "Файл сохранён."
    case .failure(let error):
      if (error as NSError).domain == NSCocoaErrorDomain
        && (error as NSError).code == NSUserCancelledError
      {
        return
      }
      fail(
        error, operation: "exportArchive",
        fallback: "Не удалось сохранить файл. Выберите другое место или повторите попытку.")
    }
  }

  func exportCancelled() { exportDocument = nil }

  func pickerFailed(_ error: any Error) {
    fail(
      error, operation: "selectArchive",
      fallback: "Не удалось открыть выбранный файл. Попробуйте ещё раз.")
  }

  private func fail(_ error: any Error, operation: String, fallback: String) {
    errorMessage = AppErrorReporter.message(for: error, operation: operation, fallback: fallback)
  }
}
