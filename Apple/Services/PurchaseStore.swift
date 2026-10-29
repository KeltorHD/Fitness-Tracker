import Foundation
import Observation
import StoreKit

@MainActor @Observable final class PurchaseStore {
  static let proID = "com.example.fitsession.pro.lifetime"
  private(set) var product: Product?
  private(set) var isPro = false
  private(set) var isBusy = false
  var message: String?
  @ObservationIgnored private var updates: Task<Void, Never>?
  func start() {
    guard updates == nil else { return }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard !Task.isCancelled else { return }
        if case .verified(let transaction) = result, transaction.productID == Self.proID {
          await self?.refreshEntitlements()
          await transaction.finish()
        }
      }
    }
    Task { await load() }
  }
  func load() async {
    do { product = try await Product.products(for: [Self.proID]).first } catch {
      message = error.localizedDescription
    }
    await refreshEntitlements()
  }
  func purchase() async {
    guard let product, !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      switch try await product.purchase() {
      case .success(let result):
        guard case .verified(let transaction) = result else {
          throw ServiceError.unavailable("Покупка не прошла проверку подписи.")
        }
        await refreshEntitlements()
        await transaction.finish()
      case .pending: message = "Покупка ожидает подтверждения."
      case .userCancelled: break
      @unknown default: break
      }
    } catch { message = error.localizedDescription }
  }
  func restore() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      try await StoreKit.AppStore.sync()
      await refreshEntitlements()
    } catch { message = error.localizedDescription }
  }
  private func refreshEntitlements() async {
    var unlocked = false
    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result, transaction.productID == Self.proID,
        transaction.revocationDate == nil, transaction.expirationDate.map({ $0 > Date() }) ?? true
      {
        unlocked = true
      }
    }
    isPro = unlocked
  }
  deinit { updates?.cancel() }
}
