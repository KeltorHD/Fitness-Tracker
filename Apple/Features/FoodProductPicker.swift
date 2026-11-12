import FitnessTrackerCore
import SwiftUI

private enum FoodPickerSource: Hashable { case search, recent, favorites }

struct FoodProductPicker: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var model: FoodSearchModel
  @State private var searchID: UUID?
  @State private var selected: FoodProduct?
  @State private var amount = "100"
  @State private var manual = false
  @State private var error: String?
  @State private var source = FoodPickerSource.search
  @State private var scanning = false
  @State private var scannedCode: String?
  @FocusState private var queryFocused: Bool
  let diary: NutritionDiaryModel
  let add: (FoodProduct, Double) throws -> Void
  init(
    diary: NutritionDiaryModel,
    add: @escaping (FoodProduct, Double) throws -> Void
  ) {
    self.diary = diary
    self.add = add
    _model = State(initialValue: FoodSearchModel(client: diary.foodSearch))
  }
  var body: some View {
    Form {
      Section {
        TextField(L10n.text("Название или штрихкод", locale: locale), text: $model.query)
          .focused($queryFocused).submitLabel(.search).onSubmit { beginSearch() }
          .accessibilityIdentifier("foodSearch")
        Button(L10n.text("Искать в базе продуктов", locale: locale)) {
          beginSearch()
        }
        .disabled(model.isLoading).accessibilityIdentifier("searchFoods")
        Button(L10n.text("Сканировать штрихкод", locale: locale), systemImage: "barcode.viewfinder")
        {
          queryFocused = false
          scanning = true
        }.accessibilityIdentifier("scanFoodBarcode")
        Button(L10n.text("Ввести продукт вручную", locale: locale)) { manual = true }
          .accessibilityIdentifier("manualFood")
      } footer: {
        Text(
          L10n.text(
            "Для поиска новых продуктов нужен интернет. Недавние, избранные и ручной ввод доступны без сети.",
            locale: locale))
      }
      if let selected {
        Section(L10n.text("Порция", locale: locale)) {
          productLabel(selected)
          let favorite = diary.favorites.contains { $0.id == selected.id }
          Button(
            L10n.text(favorite ? "Убрать из избранного" : "Добавить в избранное", locale: locale),
            systemImage: favorite ? "star.fill" : "star"
          ) { diary.toggleFavorite(selected) }.accessibilityIdentifier("favoriteSelectedFood")
          if let code = FoodBarcode.normalized(selected.barcode ?? selected.id) {
            LabeledContent(L10n.text("Штрихкод", locale: locale), value: code).font(.caption)
          }
          Picker(
            L10n.text("Единицы на упаковке", locale: locale),
            selection: Binding(
              get: { selected.unit }, set: { self.selected?.unit = $0 })
          ) {
            ForEach(FoodQuantityUnit.allCases, id: \.self) { unit in
              Text(L10n.text(unit.symbol, locale: locale)).tag(unit)
            }
          }
          NutrientValues(value: selected.per100Units)
          FoodProductSource(product: selected)
          Text(
            L10n.format(
              selected.unit == .grams ? "%@ ккал на 100 г" : "%@ ккал на 100 мл",
              selected.per100Units.calories.formatted(), locale: locale))
          TextField(
            L10n.text(selected.unit == .grams ? "Масса, г" : "Объём, мл", locale: locale),
            text: $amount
          ).keyboardType(.decimalPad)
            .accessibilityIdentifier("foodGrams")
          HStack {
            ForEach([50, 100, 150, 200], id: \.self) { value in
              Button(
                L10n.format(
                  selected.unit == .grams ? "%@ г" : "%@ мл", String(value), locale: locale)
              ) { amount = String(value) }
              .buttonStyle(.bordered).controlSize(.small)
            }
          }
          if let value = try? NutritionInput.number(amount), value > 0, value <= 10_000 {
            let nutrients = FoodPortion(product: selected, amount: value).nutrients
            Text(L10n.text("В выбранной порции", locale: locale)).font(.headline)
            Text(
              L10n.format(
                "%@ ккал", nutrients.calories.formatted(.number.precision(.fractionLength(0...1))),
                locale: locale))
            NutrientValues(value: nutrients)
          }
          Button(L10n.text("Добавить в блюдо", locale: locale)) { finish(selected) }
            .accessibilityIdentifier("confirmProduct")
          if let url = selected.sourceURL, !selected.id.hasPrefix("perek:") {
            Link(L10n.text("Источник продукта", locale: locale), destination: url)
          }
        }
      }
      Picker(L10n.text("Источник продуктов", locale: locale), selection: $source) {
        Text(L10n.text("Поиск", locale: locale)).tag(FoodPickerSource.search)
        Text(L10n.text("Недавние", locale: locale)).tag(FoodPickerSource.recent)
        Text(L10n.text("Избранное", locale: locale)).tag(FoodPickerSource.favorites)
      }.pickerStyle(.segmented).accessibilityIdentifier("foodPickerSource")
      if let error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
      if let error = diary.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
      if source == .search {
        if model.isLoading { ProgressView() }
        if let error = model.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
        if model.searched && model.results.isEmpty && model.error == nil && !model.isLoading {
          Section {
            Text(
              L10n.text(
                "Продукты с полными КБЖУ не найдены. Попробуйте другое название или ручной ввод.",
                locale: locale))
          }
        }
        if !model.results.isEmpty {
          Section(L10n.text("Результаты поиска", locale: locale)) {
            ForEach(model.results) { product in
              productRow(product)
            }
          }
        }
      }
      let local = source == .favorites ? diary.favorites : diary.recentProducts
      if source != .search && local.isEmpty {
        ContentUnavailableView(
          L10n.text(
            source == .favorites ? "Пока нет избранных продуктов" : "Пока нет недавних продуктов",
            locale: locale), systemImage: source == .favorites ? "star" : "clock")
      }
      if source != .search && !local.isEmpty {
        Section(
          L10n.text(
            source == .favorites ? "Избранные продукты" : "Недавние продукты", locale: locale)
        ) {
          ForEach(local) { product in
            productRow(product)
          }
        }
      }
      Section { FoodDatabaseAttribution() }
    }.scrollDismissesKeyboard(.interactively).navigationTitle(
      L10n.text("Добавить продукт", locale: locale)
    )
    .task(id: searchID) {
      if searchID != nil {
        await model.search(preferRussian: locale.identifier.hasPrefix("ru"))
        if !Task.isCancelled, FoodBarcode.normalized(model.query) != nil, model.results.count == 1 {
          selected = model.results.first
          amount = "100"
        }
      }
    }
    .sheet(
      isPresented: $scanning,
      onDismiss: {
        guard let code = scannedCode else { return }
        scannedCode = nil
        model.query = code
        beginSearch()
      }
    ) {
      FoodBarcodeScanner { code in
        scannedCode = code
        scanning = false
      }
    }
    .navigationDestination(isPresented: $manual) {
      ManualFoodEditor(barcode: FoodBarcode.normalized(model.query)) { product, amount in
        try add(product, amount)
        dismiss()
      }
    }
  }
  private func finish(_ product: FoodProduct) {
    do {
      try add(product, NutritionInput.number(amount))
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
  private func beginSearch() {
    queryFocused = false
    model.clearResults()
    source = .search
    selected = diary.localProduct(barcode: model.query)
    amount = "100"
    searchID = selected == nil ? UUID() : nil
  }
  private func productRow(_ product: FoodProduct) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Button {
          selected = product
          amount = "100"
        } label: {
          productLabel(product)
        }.buttonStyle(.plain)
        FoodProductSource(product: product)
      }
      Spacer(minLength: 0)
      let favorite = diary.favorites.contains { $0.id == product.id }
      Button {
        diary.toggleFavorite(product)
      } label: {
        Image(systemName: favorite ? "star.fill" : "star").frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(
        L10n.text(favorite ? "Убрать из избранного" : "Добавить в избранное", locale: locale)
      )
      .accessibilityIdentifier("favoriteFood_\(product.id)")
    }
  }
  private func productLabel(_ product: FoodProduct) -> some View {
    HStack(spacing: 12) {
      AsyncImage(url: product.imageURL) { image in
        image.resizable().scaledToFit()
      } placeholder: {
        Image(systemName: "fork.knife").foregroundStyle(.secondary)
      }.frame(width: 50, height: 50).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(product.name).foregroundStyle(.primary)
        if !product.brand.isEmpty { Text(product.brand).font(.caption).foregroundStyle(.secondary) }
      }
    }
  }
}

private struct ManualFoodEditor: View {
  @Environment(\.locale) private var locale
  @State private var unit: FoodQuantityUnit = .grams
  @State private var name = ""
  @State private var calories = ""
  @State private var protein = ""
  @State private var fat = ""
  @State private var carbs = ""
  @State private var amount = "100"
  @State private var error: String?
  @State private var barcode: String
  let add: (FoodProduct, Double) throws -> Void
  init(barcode: String?, add: @escaping (FoodProduct, Double) throws -> Void) {
    _barcode = State(initialValue: barcode ?? "")
    self.add = add
  }
  var body: some View {
    Form {
      Section {
        TextField(L10n.text("Название продукта", locale: locale), text: $name)
          .accessibilityIdentifier("manualFoodName")
        TextField(L10n.text("Штрихкод (необязательно)", locale: locale), text: $barcode)
          .keyboardType(.numberPad).accessibilityIdentifier("manualFoodBarcode")
        Picker(L10n.text("Единицы на упаковке", locale: locale), selection: $unit) {
          ForEach(FoodQuantityUnit.allCases, id: \.self) { unit in
            Text(L10n.text(unit.symbol, locale: locale)).tag(unit)
          }
        }
      }
      Section(
        L10n.text(unit == .grams ? "На 100 г продукта" : "На 100 мл продукта", locale: locale)
      ) {
        numberField("Калории, ккал", $calories, "manualCalories")
        numberField("Белки, г", $protein, "manualProtein")
        numberField("Жиры, г", $fat, "manualFat")
        numberField("Углеводы, г", $carbs, "manualCarbs")
      }
      Section {
        numberField(unit == .grams ? "Масса, г" : "Объём, мл", $amount, "manualGrams")
        Button(L10n.text("Добавить в блюдо", locale: locale)) { save() }.accessibilityIdentifier(
          "saveManualFood")
      }
      if let error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
    }.scrollDismissesKeyboard(.interactively).navigationTitle(
      L10n.text("Свой продукт", locale: locale))
  }
  private func numberField(_ title: String, _ binding: Binding<String>, _ identifier: String)
    -> some View
  {
    HStack {
      Text(L10n.text(title, locale: locale))
      TextField(L10n.text(title, locale: locale), text: binding).keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
    }
  }
  private func save() {
    do {
      let values = try Nutrients(
        calories: NutritionInput.number(calories), protein: NutritionInput.number(protein),
        fat: NutritionInput.number(fat), carbohydrates: NutritionInput.number(carbs))
      let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
      guard code.isEmpty || FoodBarcode.normalized(code) != nil else {
        throw FoodSearchError.invalidQuery
      }
      let product = FoodProduct(
        id: code.isEmpty ? UUID().uuidString : code, name: name, per100Units: values, unit: unit)
      let portion = try NutritionInput.number(amount)
      try FoodPortion(product: product, amount: portion).validate()
      try add(product, portion)
    } catch { self.error = error.localizedDescription }
  }
}
