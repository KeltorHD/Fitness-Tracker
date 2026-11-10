import Foundation

/// Open Food Facts read DTO. Only complete nutrition can be logged; mass and volume remain distinct.
public struct OpenFoodFactsProduct: Decodable, Sendable {
  private let code: String?
  private let productName: String?
  private let productNameRU: String?
  private let brands: String?
  private let imageFrontSmallURL: String?
  private let nutritionDataPer: String?
  private let productQuantityUnit: String?
  private let servingSize: String?
  private let nutriments: Values?
  private struct Values: Decodable, Sendable {
    let energyKcal: Double?
    let energyKJ: Double?
    let proteins: Double?
    let fat: Double?
    let carbohydrates: Double?
    enum CodingKeys: String, CodingKey {
      case energyKcal = "energy-kcal_100g"
      case energyKJ = "energy_100g"
      case proteins = "proteins_100g"
      case fat = "fat_100g"
      case carbohydrates = "carbohydrates_100g"
    }
  }
  enum CodingKeys: String, CodingKey {
    case code, brands, nutriments
    case productName = "product_name"
    case productNameRU = "product_name_ru"
    case imageFrontSmallURL = "image_front_small_url"
    case nutritionDataPer = "nutrition_data_per"
    case productQuantityUnit = "product_quantity_unit"
    case servingSize = "serving_size"
  }
  public func product(preferRussian: Bool = true) -> FoodProduct? {
    guard let code, !code.isEmpty, code.allSatisfy({ $0.isASCII && $0.isNumber }),
      let values = nutriments, let protein = values.proteins, let fat = values.fat,
      let carbs = values.carbohydrates,
      let calories = values.energyKcal ?? values.energyKJ.map({ $0 / 4.184 })
    else { return nil }
    // OFF uses *_100g field names for both 100 g and 100 ml.
    let quantityUnit = (productQuantityUnit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    let massUnit = ["g", "kg", "г", "кг"].contains(quantityUnit)
    let usesVolume =
      ["ml", "l", "cl", "dl", "fl oz", "мл", "л"].contains(quantityUnit)
      || (!massUnit
        && (nutritionDataPer == "100ml" || (servingSize ?? "").lowercased().contains("ml")))
    let basis: FoodQuantityUnit = usesVolume ? .milliliters : .grams
    let name =
      (preferRussian ? productNameRU : nil).flatMap { $0.isEmpty ? nil : $0 } ?? productName ?? ""
    let image = imageFrontSmallURL.flatMap(URL.init(string:)).flatMap { url -> URL? in
      guard url.scheme == "https", url.host == "images.openfoodfacts.org" else { return nil }
      return url
    }
    let product = FoodProduct(
      id: "off:\(code)", name: name, brand: brands ?? "",
      per100Units: Nutrients(calories: calories, protein: protein, fat: fat, carbohydrates: carbs),
      unit: basis, imageURL: image,
      sourceURL: URL(string: "https://world.openfoodfacts.org/product/\(code)"), barcode: code)
    guard (try? product.validate()) != nil else { return nil }
    return product
  }
}
