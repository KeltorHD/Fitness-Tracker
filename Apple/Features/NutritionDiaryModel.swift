import FitLifeCore
import Foundation
import Observation

@MainActor @Observable final class NutritionDiaryModel {
  private(set) var entries: [FoodEntry] = []
  private(set) var goal: NutritionGoal?
  private(set) var water: [WaterEntry] = []
  private(set) var supplements: [SupplementEntry] = []
  private(set) var favorites: [FoodProduct] = []
  var notice: String?
  private(set) var day = NutritionDay(entries: [], date: .now)
  private(set) var meals: [MealKind: [FoodEntry]] = [:]
  private(set) var waterToday: [WaterEntry] = []
  private(set) var week: [NutritionDaySummary] = []
  @ObservationIgnored private var selectedDate = Date()
  @ObservationIgnored private var calendar = Calendar.current
  private(set) var loaded = false
  var error: String?
  var isPresenting = false
  private(set) var workspaceID = UUID()
  @ObservationIgnored let foodSearch: any FoodSearching
  @ObservationIgnored private let personal: any NutritionRepository
  @ObservationIgnored private var demo: MemoryNutritionRepository?
  private var repository: any NutritionRepository { demo ?? personal }
  init(
    repository: any NutritionRepository,
    foodSearch: any FoodSearching = FoodSearchClient.configured()
  ) {
    self.foodSearch = foodSearch
    personal = repository
    reload()
  }
  private(set) var recentProducts: [FoodProduct] = []
  private(set) var savedMeals: [FoodEntry] = []
  func localProduct(barcode: String) -> FoodProduct? {
    guard let code = FoodBarcode.normalized(barcode) else { return nil }
    return (favorites + recentProducts).first {
      let legacy = $0.id.hasPrefix("off:") ? String($0.id.dropFirst(4)) : $0.id
      return FoodBarcode.normalized($0.barcode ?? legacy) == code
    }
  }
  func reload() {
    do {
      let entries = try repository.foodEntries()
      let goal = try repository.nutritionGoal()
      let water = try repository.waterEntries()
      let supplements = try repository.supplementEntries()
      let favorites = try repository.favoriteFoodProducts()
      self.entries = entries
      self.goal = goal
      self.water = water.sorted { $0.date > $1.date }
      self.supplements = supplements
      self.favorites = favorites.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      rebuild()
      loaded = true
      error = nil
    } catch {
      loaded = false
      self.error = "Не удалось прочитать дневник питания. Повторите загрузку."
    }
  }
  @discardableResult func save(_ entry: FoodEntry) -> Bool {
    notice = nil
    do {
      try repository.saveFoodEntry(entry)
      entries.removeAll { $0.id == entry.id }
      entries.append(entry)
      rebuild()
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
    notice = nil
    do {
      try repository.deleteFoodEntry(id: entry.id)
      entries.removeAll { $0.id == entry.id }
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось удалить запись питания. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func saveGoal(_ goal: NutritionGoal?) -> Bool {
    notice = nil
    do {
      try repository.saveNutritionGoal(goal)
      self.goal = goal
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось сохранить цель. Проверьте значения и повторите."
      return false
    }
  }
  @discardableResult func toggleFavorite(_ product: FoodProduct) -> Bool {
    notice = nil
    let selected = !favorites.contains { $0.id == product.id }
    do {
      try repository.setFavoriteFoodProduct(product, isFavorite: selected)
      favorites.removeAll { $0.id == product.id }
      if selected { favorites.append(product) }
      favorites.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось изменить избранное. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func addWater(_ amount: Double, on date: Date, calendar: Calendar) -> Bool {
    notice = nil
    let entry = WaterEntry(
      date: NutritionCalendar.date(on: date, timeOf: .now, calendar: calendar), milliliters: amount)
    do {
      try repository.saveWaterEntry(entry)
      water.insert(entry, at: 0)
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось записать воду. Проверьте объём и повторите."
      return false
    }
  }
  @discardableResult func deleteWater(_ entry: WaterEntry) -> Bool {
    notice = nil
    do {
      try repository.deleteWaterEntry(id: entry.id)
      water.removeAll { $0.id == entry.id }
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось удалить запись воды. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func saveSupplement(_ entry: SupplementEntry) -> Bool {
    notice = nil
    do {
      try repository.saveSupplementEntry(entry)
      supplements.removeAll { $0.id == entry.id }
      supplements.append(entry)
      rebuild()
      error = nil
      return true
    } catch {
      self.error =
        (error as? NutritionError)?.errorDescription
        ?? "Не удалось сохранить приём добавки. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func deleteSupplement(_ entry: SupplementEntry) -> Bool {
    notice = nil
    do {
      try repository.deleteSupplementEntry(id: entry.id)
      supplements.removeAll { $0.id == entry.id }
      rebuild()
      error = nil
      return true
    } catch {
      self.error = "Не удалось удалить приём добавки. Попробуйте ещё раз."
      return false
    }
  }
  @discardableResult func copyMeals(
    from date: Date, meal: MealKind?, to target: Date, calendar: Calendar
  ) -> Bool {
    notice = nil
    let source = NutritionDay(entries: entries, date: date, calendar: calendar).entries
      .filter { meal == nil || $0.meal == meal }
    guard !source.isEmpty else {
      error = "Нет записей для копирования."
      return false
    }
    let copies = source.map { entry in
      entry.repeated(on: NutritionCalendar.date(on: target, timeOf: entry.date, calendar: calendar))
    }
    do {
      try repository.saveFoodEntries(copies)
      entries.append(contentsOf: copies)
      rebuild()
      error = nil
      notice = "Записи питания скопированы."
      return true
    } catch {
      self.error = "Не удалось скопировать питание. Исходные записи сохранены."
      return false
    }
  }
  func selectDay(_ date: Date, calendar: Calendar) {
    selectedDate = date
    self.calendar = calendar
    rebuild()
  }
  private func rebuild() {
    var seen = Set<String>()
    recentProducts = entries.sorted {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
    }
    .flatMap(\.portions).map(\.product).filter { seen.insert($0.id).inserted }.prefix(50).map { $0 }
    savedMeals = entries.filter(\.isSavedMeal).sorted {
      $0.title == $1.title
        ? $0.id.uuidString < $1.id.uuidString
        : $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
    day = NutritionDay(
      entries: entries, date: selectedDate, calendar: calendar, supplements: supplements)
    meals = Dictionary(grouping: day.entries, by: \.meal)
    waterToday = water.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
      .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    week = NutritionDaySummary.week(
      ending: selectedDate, entries: entries, water: water, calendar: calendar,
      supplements: supplements)
  }
  func switchWorkspace(isDemo: Bool) {
    demo = isDemo ? MemoryNutritionRepository() : nil
    entries = []
    goal = nil
    water = []
    supplements = []
    favorites = []
    notice = nil
    isPresenting = false
    workspaceID = UUID()
    rebuild()
    reload()
  }
}

@MainActor @Observable final class FoodSearchModel {
  var query = "" {
    didSet {
      guard query != oldValue else { return }
      clearResults()
    }
  }
  private(set) var results: [FoodProduct] = []
  private(set) var isLoading = false
  private(set) var searched = false
  var error: String?
  @ObservationIgnored private let client: any FoodSearching
  @ObservationIgnored private var generation = UUID()
  init(client: any FoodSearching = FoodSearchClient.configured()) { self.client = client }
  func clearResults() {
    generation = UUID()
    results = []
    searched = false
    isLoading = false
    error = nil
  }
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
