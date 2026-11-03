import FitnessTrackerCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private enum Failure: Error { case expected }

@MainActor private final class FailingRepository: NutritionRepository {
  let memory = MemoryNutritionRepository()
  var fail = false
  func foodEntries() throws -> [FoodEntry] {
    if fail { throw Failure.expected }
    return try memory.foodEntries()
  }
  func saveFoodEntry(_ entry: FoodEntry) throws {
    if fail { throw Failure.expected }
    try memory.saveFoodEntry(entry)
  }
  func deleteFoodEntry(id: UUID) throws {
    if fail { throw Failure.expected }
    try memory.deleteFoodEntry(id: id)
  }
  func nutritionGoal() throws -> NutritionGoal? { try memory.nutritionGoal() }
  func saveNutritionGoal(_ goal: NutritionGoal?) throws {
    if fail { throw Failure.expected }
    try memory.saveNutritionGoal(goal)
  }
}

private actor SlowSearch: FoodSearching {
  private var didStart = false
  func started() -> Bool { didStart }
  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    if query == "slow" {
      didStart = true
      try await Task.sleep(for: .milliseconds(80))
    }
    return [FoodProduct(id: query, name: query, per100Units: Nutrients(calories: 10))]
  }
}

/// No shared mutable fixture state: every response depends only on its URL.
private final class FoodURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { preconditionFailure("Missing URL") }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let query = components?.queryItems?.first { $0.name == "search_terms" }?.value ?? ""
    let status = query == "limit" ? 429 : query == "server" ? 503 : 200
    precondition(
      request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("FitnessTracker/") == true)
    precondition(url.scheme == "https")
    let product =
      #"{"code":"12345678","product_name":"Food","nutriments":{"energy-kcal_100g":100,"proteins_100g":10,"fat_100g":2,"carbohydrates_100g":10}}"#
    let body: String
    if url.path.contains("/product/") {
      body = "{\"status\":1,\"product\":\(product)}"
    } else if query == "invalid" {
      body = "<html>Invalid</html>"
    } else {
      body = "{\"products\":[\(product),{\"nutriments\":\"broken\"},\(product)]}"
    }
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else {
      preconditionFailure("Invalid fixture")
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct NutritionChecks {
  @MainActor static func main() async throws {
    let repository = FailingRepository()
    let model = NutritionDiaryModel(repository: repository)
    let entry = FoodEntry(
      title: "Test",
      portions: [
        FoodPortion(product: FoodProduct(name: "Test", per100Units: Nutrients(calories: 50)))
      ])
    precondition(model.loaded && model.entries.isEmpty)
    precondition(model.save(entry))
    let goal = NutritionGoal(calories: 2300)
    precondition(model.saveGoal(goal))
    repository.fail = true
    precondition(!model.delete(entry))
    precondition(!model.saveGoal(NutritionGoal(calories: 2000)))
    precondition(model.entries == [entry] && model.goal == goal)
    model.reload()
    precondition(!model.loaded && model.error != nil && model.entries == [entry])
    repository.fail = false
    model.reload()
    let personalID = model.workspaceID
    model.switchWorkspace(isDemo: true)
    precondition(model.entries.isEmpty && model.goal == nil && model.workspaceID != personalID)
    precondition(model.save(entry.repeated(on: .now)))
    model.switchWorkspace(isDemo: false)
    precondition(model.entries == [entry] && model.goal == goal)
    precondition(model.recentProducts.count == 1)
    let decimal = try NutritionInput.number("12,5")
    precondition(decimal == 12.5)
    for invalid in ["NaN", "Infinity", "1e3", "-1", "1.2.3", ""] {
      do {
        _ = try NutritionInput.number(invalid)
        preconditionFailure("Accepted invalid input")
      } catch is NutritionError {}  // Expected invalid input.
    }

    let slowClient = SlowSearch()
    let search = FoodSearchModel(client: slowClient)
    search.query = "slow"
    let old = Task { await search.search(preferRussian: false) }
    while !(await slowClient.started()) { await Task.yield() }
    search.query = "new"
    await search.search(preferRussian: false)
    await old.value
    precondition(search.results.first?.id == "new" && !search.isLoading)
    search.query = "slow"
    let cancelled = Task { await search.search(preferRussian: false) }
    await Task.yield()
    cancelled.cancel()
    await cancelled.value
    precondition(!search.isLoading && search.error == nil)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FoodURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let client = OpenFoodFactsClient(session: session)
    let products = try await client.search("C++ & рис", preferRussian: true)
    precondition(products.count == 1 && products.first?.per100Units.calories == 100)
    let barcode = try await client.search("12345678", preferRussian: false)
    precondition(barcode.count == 1)
    for query in ["limit", "server", "invalid"] {
      do {
        _ = try await client.search(query, preferRussian: false)
        preconditionFailure("Accepted HTTP failure")
      } catch let error as FoodSearchError {
        switch (query, error) {
        case ("limit", .rateLimited), ("server", .unavailable), ("invalid", .invalidResponse): break
        default: preconditionFailure("Wrong error")
        }
      }
    }
    for _ in 0..<3 { _ = try await client.search("food", preferRussian: false) }
    do {
      _ = try await client.search("food", preferRussian: false)
      preconditionFailure("Missing rate limit")
    } catch FoodSearchError.rateLimited {}  // Expected local request budget exhaustion.
    print(
      "Nutrition: persistence failures, demo isolation, input, stale/cancelled search, HTTP fixtures and rate limit passed (no network)."
    )
  }
}
