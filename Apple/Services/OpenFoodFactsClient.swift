import FitLifeCore
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

protocol FoodSearching: Sendable {
  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct]
}

enum FoodSearchError: Error, LocalizedError {
  case unavailable, rateLimited, invalidResponse, invalidQuery
  var errorDescription: String? {
    switch self {
    case .unavailable: "Поиск недоступен. Проверьте интернет или добавьте продукт вручную."
    case .rateLimited: "Слишком много запросов. Подождите минуту и повторите поиск."
    case .invalidResponse: "База продуктов вернула некорректный ответ. Повторите позже."
    case .invalidQuery: "Введите название от 2 символов или штрихкод из 8–14 цифр."
    }
  }
}

actor OpenFoodFactsClient: FoodSearching {
  private let session: URLSession
  private var searches: [Date] = []
  init(session: URLSession = .shared) { self.session = session }
  func search(_ query: String, preferRussian: Bool) async throws -> [FoodProduct] {
    try Task.checkCancellation()
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...100).contains(query.count) else { throw FoodSearchError.invalidQuery }
    let barcode = query.allSatisfy { $0.isASCII && $0.isNumber }
    if barcode && !(8...14).contains(query.count) { throw FoodSearchError.invalidQuery }
    let now = Date()
    searches.removeAll { now.timeIntervalSince($0) >= 60 }
    guard searches.count < 8 else { throw FoodSearchError.rateLimited }
    searches.append(now)
    var components = URLComponents()
    components.scheme = "https"
    components.host = "world.openfoodfacts.org"
    components.path = barcode ? "/api/v2/product/\(query).json" : "/cgi/search.pl"
    let fields =
      "code,product_name,product_name_ru,brands,image_front_small_url,nutriments,nutrition_data_per,product_quantity_unit,serving_size"
    components.queryItems = [URLQueryItem(name: "fields", value: fields)]
    if !barcode {
      components.queryItems? += [
        URLQueryItem(name: "search_terms", value: query),
        URLQueryItem(name: "search_simple", value: "1"),
        URLQueryItem(name: "action", value: "process"),
        URLQueryItem(name: "json", value: "1"),
        URLQueryItem(name: "page_size", value: "24"),
      ]
    }
    guard let url = components.url else { throw FoodSearchError.invalidQuery }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("FitLife/1.0 (iOS; nutrition diary)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) } catch {
      if Task.isCancelled { throw CancellationError() }
      throw FoodSearchError.unavailable
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw FoodSearchError.invalidResponse }
    if http.statusCode == 429 { throw FoodSearchError.rateLimited }
    if http.statusCode == 404 && barcode { return [] }
    guard (200...299).contains(http.statusCode) else { throw FoodSearchError.unavailable }
    guard data.count <= 4_000_000 else { throw FoodSearchError.invalidResponse }
    struct Result: Decodable {
      let products: [LossyProduct]?
      let product: OpenFoodFactsProduct?
      let status: Int?
    }
    let decoded: Result
    do { decoded = try JSONDecoder().decode(Result.self, from: data) } catch {
      throw FoodSearchError.invalidResponse
    }
    let products =
      barcode ? decoded.product.map { [$0] } ?? [] : (decoded.products ?? []).compactMap(\.value)
    var seen = Set<String>()
    return products.compactMap { $0.product(preferRussian: preferRussian) }
      .filter { seen.insert($0.id).inserted }
  }
}

private struct LossyProduct: Decodable {
  let value: OpenFoodFactsProduct?
  init(from decoder: any Decoder) throws {
    // A malformed community product must not hide the other valid search results.
    value = try? OpenFoodFactsProduct(from: decoder)
  }
}
