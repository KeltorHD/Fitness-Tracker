import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Uses the Russian catalog first; the public global catalog also works without a backend.
struct FoodSearchClient: FoodSearching {
  let primary: (any FoodSearching)?
  let fallback: any FoodSearching

  init(primary: (any FoodSearching)?, fallback: any FoodSearching = OpenFoodFactsClient()) {
    self.primary = primary
    self.fallback = fallback
  }

  static func configured(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Self {
    let address = info["FitLifeBackendURL"] as? String ?? ""
    let url = URL(string: address)
    let valid =
      url.map {
        $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil
          && $0.query == nil && $0.fragment == nil && ($0.path.isEmpty || $0.path == "/")
      } ?? false
    return Self(primary: valid ? url.map { BackendFoodSearchClient(baseURL: $0) } : nil)
  }

  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    var primaryIncomplete = false
    if let primary {
      do {
        let products = try await primary.search(query, preferRussian: preferRussian)
        try Task.checkCancellation()
        if !products.isEmpty { return products }
      } catch is CancellationError { throw CancellationError() } catch FoodSearchError.invalidQuery
      { throw FoodSearchError.invalidQuery } catch {
        try Task.checkCancellation()
        primaryIncomplete = (error as? FoodSearchError) == .incompleteProduct
      }
    }
    let products = try await fallback.search(query, preferRussian: preferRussian)
    try Task.checkCancellation()
    if products.isEmpty && primaryIncomplete { throw FoodSearchError.incompleteProduct }
    return products
  }
}

struct BackendFoodSearchClient: FoodSearching {
  let baseURL: URL
  var session: URLSession = .shared

  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    try Task.checkCancellation()
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...100).contains(query.count) else { throw FoodSearchError.invalidQuery }
    if query.allSatisfy({ $0.isASCII && $0.isNumber }), !(8...14).contains(query.count) {
      throw FoodSearchError.invalidQuery
    }
    guard
      var parts = URLComponents(
        url: baseURL.appendingPathComponent("v1/foods/search"), resolvingAgainstBaseURL: false)
    else { throw FoodSearchError.invalidQuery }
    parts.queryItems = [URLQueryItem(name: "q", value: query)]
    guard let url = parts.url else { throw FoodSearchError.invalidQuery }
    var request = URLRequest(url: url, timeoutInterval: 12)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
      throw FoodSearchError.unavailable
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, data.count <= 1_000_000 else {
      throw FoodSearchError.invalidResponse
    }
    if http.statusCode == 429 { throw FoodSearchError.rateLimited }
    guard http.statusCode == 200 else { throw FoodSearchError.unavailable }
    struct Payload: Decodable { let products: [FoodProduct] }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
      throw FoodSearchError.invalidResponse
    }
    return try payload.products.map { product in
      try product.validate()
      guard product.id.hasPrefix("perek:"), let source = product.sourceURL,
        source.scheme == "https", source.host == "perek.us", source.user == nil,
        source.password == nil, product.imageURL == nil
      else { throw FoodSearchError.invalidResponse }
      return product
    }
  }
}
