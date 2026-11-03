import AVFoundation
import FitnessTrackerCore
import SwiftUI
import UIKit
import Vision
import VisionKit

/// VisionKit has no SwiftUI camera scanner. This bridge owns its native controller lifecycle.
struct FoodBarcodeScanner: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var phase
  @State private var ready = false
  @State private var message: String?
  @State private var denied = false
  let onRead: (String) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if ready && message == nil && phase == .active {
          BarcodeScannerCamera(isActive: phase == .active, onRead: onRead) {
            ready = false
            message =
              "Камера временно недоступна. Закройте сканер и повторите или введите код вручную."
          }
          .safeAreaInset(edge: .bottom) {
            Text(
              L10n.text(
                "Наведите камеру на штрихкод упаковки. Кадры не сохраняются и не отправляются в сеть.",
                locale: locale)
            )
            .font(.footnote).padding().frame(maxWidth: .infinity).background(FitTheme.paper)
          }
        } else if let message {
          VStack(spacing: 16) {
            ContentUnavailableView(
              L10n.text("Сканер недоступен", locale: locale), systemImage: "barcode.viewfinder",
              description: Text(L10n.text(message, locale: locale)))
            if denied, let url = URL(string: UIApplication.openSettingsURLString) {
              Link(L10n.text("Открыть настройки iOS", locale: locale), destination: url)
                .buttonStyle(.bordered)
            }
            Button(L10n.text("Ввести штрихкод вручную", locale: locale)) { dismiss() }.buttonStyle(
              .borderedProminent)
          }.padding()
        } else {
          ProgressView()
        }
      }
      .navigationTitle(L10n.text("Сканировать штрихкод", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale)) { dismiss() }
        }
      }
      .task(id: phase) { await prepare() }
      .onChange(of: phase) { if phase != .active { ready = false } }
    }
  }

  private func prepare() async {
    guard phase == .active else { return }
    guard DataScannerViewController.isSupported else {
      message = "На этом устройстве сканирование недоступно. Введите номер штрихкода вручную."
      return
    }
    var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
      authorized = await AVCaptureDevice.requestAccess(for: .video)
    }
    guard !Task.isCancelled, phase == .active else { return }
    denied = !authorized
    guard authorized else {
      message = "Разрешите доступ к камере в настройках iOS или введите номер штрихкода вручную."
      return
    }
    guard DataScannerViewController.isAvailable else {
      message = "Камера временно недоступна. Закройте сканер и повторите или введите код вручную."
      return
    }
    message = nil
    ready = true
  }
}

@MainActor private struct BarcodeScannerCamera: UIViewControllerRepresentable {
  var isActive: Bool
  let onRead: (String) -> Void
  let onFailure: () -> Void
  func makeUIViewController(context: Context) -> BarcodeScannerController {
    let controller = BarcodeScannerController(onRead: onRead, onFailure: onFailure)
    controller.isActive = isActive
    return controller
  }
  func updateUIViewController(_ controller: BarcodeScannerController, context: Context) {
    controller.isActive = isActive
  }
  static func dismantleUIViewController(_ controller: BarcodeScannerController, coordinator: ()) {
    controller.stop()
  }
}

@MainActor
private final class BarcodeScannerController: UIViewController, DataScannerViewControllerDelegate {
  private let scanner = DataScannerViewController(
    recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13])], qualityLevel: .balanced,
    recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
    isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
  private let onRead: (String) -> Void
  private let onFailure: () -> Void
  private var completed = false
  // Controller-owned failure delivery avoids changing SwiftUI state during a representable update.
  private var failureTask: Task<Void, Never>?
  var isActive = false { didSet { updateScanning() } }

  init(onRead: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
    self.onRead = onRead
    self.onFailure = onFailure
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    scanner.delegate = self
    addChild(scanner)
    view.addSubview(scanner.view)
    scanner.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
      scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    scanner.didMove(toParent: self)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateScanning()
  }
  override func viewWillDisappear(_ animated: Bool) {
    stop()
    super.viewWillDisappear(animated)
  }
  func stop() {
    scanner.stopScanning()
    failureTask?.cancel()
  }
  private func updateScanning() {
    guard isActive, !completed, viewIfLoaded?.window != nil else {
      scanner.stopScanning()
      return
    }
    guard !scanner.isScanning else { return }
    do { try scanner.startScanning() } catch { reportFailure() }
  }
  func dataScanner(
    _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
    allItems: [RecognizedItem]
  ) {
    for item in addedItems { accept(item) }
  }
  func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
    accept(item)
  }
  func dataScanner(
    _ dataScanner: DataScannerViewController,
    becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
  ) {
    if isActive && !completed {
      scanner.stopScanning()
      reportFailure()
    }
  }
  private func reportFailure() {
    guard !completed else { return }
    completed = true
    failureTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled else { return }
      self?.onFailure()
    }
  }
  private func accept(_ item: RecognizedItem) {
    guard !completed, isActive, case .barcode(let barcode) = item,
      let raw = barcode.payloadStringValue, let code = FoodBarcode.normalized(raw)
    else { return }
    completed = true
    scanner.stopScanning()
    onRead(code)
  }
}
