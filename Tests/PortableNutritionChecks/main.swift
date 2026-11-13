import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private enum Failure: Error { case expected }

private func expectSupplement(_ value: Bool) { precondition(value) }

@MainActor private final class FailingRepository: NutritionRepository {
  let memory = MemoryNutritionRepository()
  var fail = false
  var failSupplementReads = false
  func foodEntries() throws -> [FoodEntry] {
    if fail { throw Failure.expected }
    return try memory.foodEntries()
  }
  func saveFoodEntry(_ entry: FoodEntry) throws {
    if fail { throw Failure.expected }
    try memory.saveFoodEntry(entry)
  }
  func saveFoodEntries(_ entries: [FoodEntry]) throws {
    if fail { throw Failure.expected }
    try memory.saveFoodEntries(entries)
  }
  func waterEntries() throws -> [WaterEntry] { try memory.waterEntries() }
  func saveWaterEntry(_ entry: WaterEntry) throws {
    if fail { throw Failure.expected }
    try memory.saveWaterEntry(entry)
  }
  func deleteWaterEntry(id: UUID) throws {
    if fail { throw Failure.expected }
    try memory.deleteWaterEntry(id: id)
  }
  func supplementEntries() throws -> [SupplementEntry] {
    if fail || failSupplementReads { throw Failure.expected }
    return try memory.supplementEntries()
  }
  func saveSupplementEntry(_ entry: SupplementEntry) throws {
    if fail { throw Failure.expected }
    try memory.saveSupplementEntry(entry)
  }
  func deleteSupplementEntry(id: UUID) throws {
    if fail { throw Failure.expected }
    try memory.deleteSupplementEntry(id: id)
  }
  func favoriteFoodProducts() throws -> [FoodProduct] { try memory.favoriteFoodProducts() }
  func setFavoriteFoodProduct(_ product: FoodProduct, isFavorite: Bool) throws {
    if fail { throw Failure.expected }
    try memory.setFavoriteFoodProduct(product, isFavorite: isFavorite)
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

private actor CatalogStub: FoodSearching {
  let products: [FoodProduct]
  let failure: FoodSearchError?
  private(set) var calls = 0
  init(_ products: [FoodProduct] = [], failure: FoodSearchError? = nil) {
    self.products = products
    self.failure = failure
  }
  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    calls += 1
    try Task.checkCancellation()
    if let failure { throw failure }
    return products
  }
}

private struct CancelledCatalog: FoodSearching {
  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    throw CancellationError()
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
    if url.host == "api.test" {
      precondition(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
      let product = FoodProduct(
        id: "perek:sample", name: "Oreo", brand: "Oreo",
        per100Units: Nutrients(calories: 480, protein: 5, fat: 20, carbohydrates: 70),
        sourceURL: URL(string: "https://perek.us/food/test/oreo"), barcode: "7622210769459")
      let body = try! JSONEncoder().encode(["products": [product]])
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
      return
    }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let query = components?.queryItems?.first { $0.name == "search_terms" }?.value ?? ""
    let status = query == "limit" ? 429 : query == "server" ? 503 : 200
    precondition(
      request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("FitLife/") == true)
    precondition(url.scheme == "https")
    let product =
      #"{"code":"12345678","product_name":"Food","nutriments":{"energy-kcal_100g":100,"proteins_100g":10,"fat_100g":2,"carbohydrates_100g":10}}"#
    let body: String
    if url.path.contains("/product/7622210769459") {
      // OFF returned this minimal successful response for the reported Oreo barcode.
      body = #"{"status":1,"product":{"code":"7622210769459","ecoscore_tags":["unknown"]}}"#
    } else if url.path.contains("/product/00000000") {
      body = #"{"status":0,"status_verbose":"product not found"}"#
    } else if url.path.contains("/product/11111111") {
      body = #"{"status":1}"#
    } else if url.path.contains("/product/") {
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
  @MainActor static func supplements() throws {
    let repository = FailingRepository()
    let model = NutritionDiaryModel(repository: repository)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    model.selectDay(date, calendar: calendar)
    let food = FoodEntry(
      date: date, title: "Food",
      portions: [
        FoodPortion(product: FoodProduct(name: "Food", per100Units: Nutrients(calories: 50)))
      ])
    precondition(model.save(food))
    let creatine = SupplementEntry(date: date, kind: .creatine, amount: 5)
    var protein = SupplementEntry(
      date: date, kind: .protein, amount: 30,
      nutritionPerBasis: Nutrients(calories: 400, protein: 80, fat: 5, carbohydrates: 10))
    precondition(model.saveSupplement(creatine) && model.saveSupplement(protein))
    precondition(model.entries == [food] && model.supplements.count == 2)
    precondition(model.day.total.calories == 170 && model.day.total.protein == 24)
    precondition(model.week.last?.total.calories == 170)
    protein.amount = 60
    precondition(model.saveSupplement(protein) && model.supplements.count == 2)
    precondition(model.day.total.calories == 290)
    let editor = SupplementEntryEditorModel(entry: protein)
    editor.amount = "12,5"
    editor.note = " Updated "
    let edited = try editor.validatedEntry()
    precondition(
      edited.id == protein.id && edited.amount == 12.5 && edited.nutrients?.calories == 50)
    precondition(edited.note == "Updated")
    expectSupplement(try repository.supplementEntries().first { $0.id == protein.id }?.amount == 60)
    for input in ["0", "-1", "NaN", "1e3", "", "1.2.3"] {
      editor.amount = input
      do {
        _ = try editor.validatedEntry()
        preconditionFailure("Invalid supplement amount accepted")
      } catch is NutritionError {}
    }
    editor.amount = "2"
    editor.changeUnit(.servings)
    precondition(editor.calories.isEmpty && editor.protein.isEmpty)
    expectSupplement(try editor.validatedEntry().needsNutrition)
    editor.calories = "400"
    do {
      _ = try editor.validatedEntry()
      preconditionFailure("Partial nutrition was completed with invented zeros")
    } catch is NutritionError {}
    editor.includesNutrition = false
    expectSupplement(try editor.validatedEntry().nutritionPerBasis == nil)
    var precise = protein
    precise.amount = 12.123456789012345
    let preciseEditor = SupplementEntryEditorModel(entry: precise)
    preciseEditor.note = "No numeric edit"
    expectSupplement(try preciseEditor.validatedEntry().amount == precise.amount)
    let other = SupplementEntryEditorModel(
      entry: SupplementEntry(
        date: date, kind: .other, amount: 1, unit: .capsules))
    do {
      _ = try other.validatedEntry()
      preconditionFailure("Missing custom name accepted")
    } catch is NutritionError {}
    other.name = "Custom"
    expectSupplement(try other.validatedEntry().name == "Custom")
    let previous = model.supplements
    repository.fail = true
    precondition(!model.deleteSupplement(protein) && model.supplements == previous)
    precondition(!model.saveSupplement(edited) && model.day.total.calories == 290)
    repository.fail = false
    let secondFood = food.repeated(on: date)
    try repository.memory.saveFoodEntry(secondFood)
    repository.failSupplementReads = true
    model.reload()
    precondition(!model.loaded && model.entries == [food] && model.supplements == previous)
    repository.failSupplementReads = false
    model.reload()
    precondition(model.loaded && model.entries.count == 2 && model.supplements.count == 2)
    model.switchWorkspace(isDemo: true)
    precondition(model.supplements.isEmpty)
    precondition(model.saveSupplement(creatine.repeated(on: date)))
    model.switchWorkspace(isDemo: false)
    precondition(Set(model.supplements.map(\.id)) == Set(previous.map(\.id)))
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
    model.selectDay(tomorrow, calendar: calendar)
    precondition(model.day.supplements.isEmpty)
    precondition(model.saveSupplement(protein.repeated(on: tomorrow)))
    precondition(model.day.supplements.count == 1 && model.day.total.calories == 240)
    precondition(model.deleteSupplement(model.day.supplements[0]))
    precondition(model.day.supplements.isEmpty)
    print(
      "Supplements: dose/units, packaging nutrition, unknown values, editing/cancellation, failures, atomic reload, day/week totals and demo isolation passed (no Apple SDK)."
    )
  }
  @MainActor static func main() async throws {
    try supplements()
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
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    model.selectDay(entry.date, calendar: calendar)
    var favorite = entry.portions[0].product
    favorite = FoodProduct(id: "12345678", name: favorite.name, per100Units: favorite.per100Units)
    precondition(model.toggleFavorite(favorite))
    precondition(model.localProduct(barcode: " 12345678 ") == favorite)
    precondition(model.addWater(250, on: entry.date, calendar: calendar))
    precondition(model.waterToday.reduce(0) { $0 + $1.milliliters } == 250)
    let initialWater = model.water
    repository.fail = true
    precondition(!model.addWater(500, on: entry.date, calendar: calendar))
    precondition(!model.toggleFavorite(favorite) && model.favorites == [favorite])
    precondition(model.water == initialWater)
    let target = calendar.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
    precondition(!model.copyMeals(from: entry.date, meal: nil, to: target, calendar: calendar))
    precondition(model.entries == [entry])
    repository.fail = false
    precondition(model.copyMeals(from: entry.date, meal: .snack, to: target, calendar: calendar))
    precondition(model.entries.count == 2)
    let copy = model.entries.first { $0.id != entry.id }
    precondition(
      copy?.portions.first?.id != entry.portions.first?.id && copy?.nutrients == entry.nutrients)
    precondition(copy.map { calendar.isDate($0.date, inSameDayAs: target) } == true)
    model.selectDay(target, calendar: calendar)
    precondition(model.day.entries.count == 1 && model.waterToday.isEmpty)
    model.switchWorkspace(isDemo: true)
    precondition(model.water.isEmpty && model.favorites.isEmpty && model.entries.isEmpty)
    model.switchWorkspace(isDemo: false)
    precondition(model.water == initialWater && model.favorites == [favorite])
    precondition(model.deleteWater(initialWater[0]) && model.water.isEmpty)
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
    let barcodeClient = OpenFoodFactsClient(session: session)
    do {
      _ = try await barcodeClient.search("7622210769459", preferRussian: true)
      preconditionFailure("An existing empty card was reported as an absent product")
    } catch FoodSearchError.incompleteProduct {}
    let absent = try await barcodeClient.search("00000000", preferRussian: true)
    precondition(absent.isEmpty)
    do {
      _ = try await barcodeClient.search("11111111", preferRussian: true)
      preconditionFailure("Accepted a successful status without a product")
    } catch FoodSearchError.invalidResponse {}
    let errorModel = FoodSearchModel(client: barcodeClient)
    errorModel.query = "7622210769459"
    await errorModel.search(preferRussian: true)
    precondition(
      errorModel.error == FoodSearchError.incompleteProduct.errorDescription
        && !errorModel.searched && !errorModel.isLoading)
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
    try await checkCatalogRouting(session: session)
    print(
      "Nutrition: persistence failures, demo isolation, input, stale/cancelled search, HTTP fixtures and rate limit passed (no network)."
    )
  }
  @MainActor private static func checkCatalogRouting(session: URLSession) async throws {
    let backend = BackendFoodSearchClient(
      baseURL: URL(string: "https://api.test")!, session: session)
    let primary = try await backend.search("7622210769459", preferRussian: true)
    precondition(primary.first?.barcode == "7622210769459" && primary.first?.unit == .grams)
    let skipped = CatalogStub([], failure: .unavailable)
    let routed = try await FoodSearchClient(primary: backend, fallback: skipped).search(
      "7622210769459", preferRussian: true)
    let skippedCalls = await skipped.calls
    precondition(routed == primary && skippedCalls == 0)
    for failure in [nil, FoodSearchError.unavailable, .rateLimited, .invalidResponse] {
      let fallback = CatalogStub(primary)
      let combined = FoodSearchClient(
        primary: CatalogStub([], failure: failure), fallback: fallback)
      let results = try await combined.search("oreo", preferRussian: true)
      let calls = await fallback.calls
      precondition(results == primary && calls == 1)
    }
    let cancelledFallback = CatalogStub(primary)
    do {
      _ = try await FoodSearchClient(primary: CancelledCatalog(), fallback: cancelledFallback)
        .search("oreo", preferRussian: true)
      preconditionFailure("Cancellation started a fallback request")
    } catch is CancellationError {}
    let calls = await cancelledFallback.calls
    precondition(calls == 0)
    let product = primary[0]
    let data = try JSONEncoder().encode(product)
    let restored = try JSONDecoder().decode(FoodProduct.self, from: data)
    precondition(restored == product)
    let memory = MemoryNutritionRepository()
    let diary = NutritionDiaryModel(repository: memory)
    diary.toggleFavorite(product)
    precondition(diary.localProduct(barcode: "7622210769459") == product)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "barcode")
    let decoded = try JSONDecoder().decode(
      FoodProduct.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(decoded.barcode == nil && decoded.name == product.name)
  }

}
