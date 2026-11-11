import FitLifeCore
import Foundation
import Observation

@MainActor @Observable final class NutritionDiaryModel {
  private(set) var entries: [FoodEntry] = []
  private(set) var goal: NutritionGoal?
  private(set) var loaded = false
  var error: String?
  var isPresenting = false
  private(set) var workspaceID = UUID()
  @ObservationIgnored let foodSearch: any FoodSearching
  @ObservationIgnored private let personal: any NutritionRepository
  @ObservationIgnored private var demo: MemoryNutritionRepository?
  private var repository: any NutritionRepository { demo ?? personal }
  init(repository: any NutritionRepository, foodSearch: any FoodSearching = OpenFoodFactsClient()) {
    self.foodSearch = foodSearch
    personal = repository
    reload()
  }
  var recentProducts: [FoodProduct] {
    var seen = Set<String>()
    return entries.sorted { $0.date > $1.date }.flatMap(\.portions).map(\.product)
      .filter { seen.insert($0.id).inserted }.prefix(50).map { $0 }
  }
  var savedMeals: [FoodEntry] { entries.filter(\.isSavedMeal).sorted { $0.title < $1.title } }
  func reload() {
    do {
      let entries = try repository.foodEntries()
      let goal = try repository.nutritionGoal()
      self.entries = entries
      self.goal = goal
      loaded = true
      error = nil
    } catch {
      loaded = false
      self.error = "Не удалось прочитать дневник питания. Повторите загрузку."
    }
  }
  @discardableResult func save(_ entry: FoodEntry) -> Bool {
    do {
      try repository.saveFoodEntry(entry)
      entries.removeAll { $0.id == entry.id }
      entries.append(entry)
      error = nil
      return true
    } catch {
      self.error =
        (error as? NutritionError)?.errorDescription
        ?? "Не удалось сохранить питание. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func delete(_ entry: FoodEntry) -> Bool {
    do {
      try repository.deleteFoodEntry(id: entry.id)
      entries.removeAll { $0.id == entry.id }
      error = nil
      return true
    } catch {
      self.error = "Не удалось удалить запись питания. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func saveGoal(_ goal: NutritionGoal?) -> Bool {
    do {
      try repository.saveNutritionGoal(goal)
      self.goal = goal
      error = nil
      return true
    } catch {
      self.error = "Не удалось сохранить цель. Проверьте значения и повторите."
      return false
    }
  }
  func switchWorkspace(isDemo: Bool) {
    demo = isDemo ? MemoryNutritionRepository() : nil
    entries = []
    goal = nil
    isPresenting = false
    workspaceID = UUID()
    reload()
  }
}

@MainActor @Observable final class FoodSearchModel {
  var query = ""
  private(set) var results: [FoodProduct] = []
  private(set) var isLoading = false
  private(set) var searched = false
  var error: String?
  @ObservationIgnored private let client: any FoodSearching
  @ObservationIgnored private var generation = UUID()
  init(client: any FoodSearching = OpenFoodFactsClient()) { self.client = client }
  func search(preferRussian: Bool) async {
    let token = UUID()
    generation = token
    let query = query
    isLoading = true
    error = nil
    results = []
    defer { if generation == token { isLoading = false } }
    do {
      let products = try await client.search(query, preferRussian: preferRussian)
      guard generation == token, !Task.isCancelled else { return }
      results = products
      searched = true
    } catch {
      guard generation == token, !Task.isCancelled else { return }
      self.error =
        (error as? FoodSearchError)?.errorDescription
        ?? "Поиск недоступен. Проверьте интернет или добавьте продукт вручную."
    }
  }
}

/// Locale-friendly numeric input, without accepting NaN, Infinity, signs or exponent notation.
enum NutritionInput {
  static func number(_ text: String) throws -> Double {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 20,
      text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
      let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0
    else { throw NutritionError.invalidValues }
    return value
  }
}
