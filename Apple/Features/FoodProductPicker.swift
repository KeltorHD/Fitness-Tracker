import FitLifeCore
import SwiftUI

struct FoodProductPicker: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @State private var model: FoodSearchModel
  @State private var searchID: UUID?
  @State private var selected: FoodProduct?
  @State private var amount = "100"
  @State private var manual = false
  @State private var error: String?
  let recent: [FoodProduct]
  let add: (FoodProduct, Double) throws -> Void
  init(
    recent: [FoodProduct], client: any FoodSearching,
    add: @escaping (FoodProduct, Double) throws -> Void
  ) {
    self.recent = recent
    self.add = add
    _model = State(initialValue: FoodSearchModel(client: client))
  }
  var body: some View {
    Form {
      Section {
        TextField(L10n.text("Название или штрихкод", locale: locale), text: $model.query)
          .submitLabel(.search).onSubmit { searchID = UUID() }.accessibilityIdentifier("foodSearch")
        Button(L10n.text("Искать в базе продуктов", locale: locale)) { searchID = UUID() }
          .disabled(model.isLoading).accessibilityIdentifier("searchFoods")
        Button(L10n.text("Ввести продукт вручную", locale: locale)) { manual = true }
          .accessibilityIdentifier("manualFood")
      } footer: {
        Text(
          L10n.text(
            "Для поиска нужен интернет. Недавние продукты и ручной ввод доступны без сети.",
            locale: locale))
      }
      if let selected {
        Section(L10n.text("Порция", locale: locale)) {
          productLabel(selected)
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
          Text(
            L10n.format(
              selected.unit == .grams ? "%@ ккал на 100 г" : "%@ ккал на 100 мл",
              selected.per100Units.calories.formatted(), locale: locale))
          TextField(
            L10n.text(selected.unit == .grams ? "Масса, г" : "Объём, мл", locale: locale),
            text: $amount
          ).keyboardType(.decimalPad)
            .accessibilityIdentifier("foodGrams")
          Button(L10n.text("Добавить в блюдо", locale: locale)) { finish(selected) }
            .accessibilityIdentifier("confirmProduct")
          if let url = selected.sourceURL {
            Link(L10n.text("Источник продукта", locale: locale), destination: url)
          }
        }
      }
      if let error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
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
            Button {
              selected = product
              amount = "100"
            } label: {
              productLabel(product)
            }.buttonStyle(.plain)
          }
        }
      }
      if !recent.isEmpty {
        Section(L10n.text("Недавние продукты", locale: locale)) {
          ForEach(recent) { product in
            Button {
              selected = product
              amount = "100"
            } label: {
              productLabel(product)
            }.buttonStyle(.plain)
          }
        }
      }
      Section { FoodDatabaseAttribution() }
    }.navigationTitle(L10n.text("Добавить продукт", locale: locale))
      .task(id: searchID) {
        if searchID != nil { await model.search(preferRussian: locale.identifier.hasPrefix("ru")) }
      }
      .navigationDestination(isPresented: $manual) {
        ManualFoodEditor { product, amount in
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
  let add: (FoodProduct, Double) throws -> Void
  var body: some View {
    Form {
      Section {
        TextField(L10n.text("Название продукта", locale: locale), text: $name)
          .accessibilityIdentifier("manualFoodName")
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
    }.navigationTitle(L10n.text("Свой продукт", locale: locale))
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
      let product = FoodProduct(name: name, per100Units: values, unit: unit)
      let portion = try NutritionInput.number(amount)
      try FoodPortion(product: product, amount: portion).validate()
      try add(product, portion)
    } catch { self.error = error.localizedDescription }
  }
}
