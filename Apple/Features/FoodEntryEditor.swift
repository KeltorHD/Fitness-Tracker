import FitLifeCore
import PhotosUI
import SwiftUI
import UIKit

struct FoodEntryEditor: View {
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Environment(\.fitnessColorTheme) private var colorTheme
  let diary: NutritionDiaryModel
  private let workspaceID: UUID
  @State private var model: FoodEntryEditorModel
  @State private var selection: PhotosPickerItem?
  @State private var isTransferringPhoto = false
  @State private var addingFood = false
  init(diary: NutritionDiaryModel, entry: FoodEntry) {
    self.diary = diary
    workspaceID = diary.workspaceID
    _model = State(initialValue: FoodEntryEditorModel(entry: entry))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(L10n.text("Название блюда", locale: locale), text: $model.entry.title)
            .accessibilityIdentifier("foodEntryTitle")
          Picker(L10n.text("Приём пищи", locale: locale), selection: $model.entry.meal) {
            ForEach(MealKind.allCases, id: \.self) { meal in
              Text(L10n.text(meal.title, locale: locale)).tag(meal)
            }
          }
          DatePicker(L10n.text("Дата и время", locale: locale), selection: $model.entry.date)
          Toggle(
            L10n.text("Сохранить блюдо для повтора", locale: locale), isOn: $model.entry.isSavedMeal
          )
        }
        Section(L10n.text("Состав", locale: locale)) {
          ForEach($model.entry.portions) { $portion in
            FoodPortionEditor(portion: $portion) {
              model.entry.portions.removeAll { $0.id == portion.id }
            }
          }
          Button(L10n.text("Добавить продукт", locale: locale), systemImage: "plus") {
            addingFood = true
          }
          .accessibilityIdentifier("addProduct")
          if !model.entry.portions.isEmpty
            && model.entry.portions.allSatisfy({ $0.amount.isFinite && $0.amount > 0 })
          {
            NutrientValues(value: model.entry.nutrients)
          }
        }
        Section {
          PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label(L10n.text("Выбрать фото еды", locale: locale), systemImage: "photo")
          }.disabled(model.isLoadingPhoto || isTransferringPhoto).accessibilityIdentifier(
            "pickMealPhoto")
          if model.isLoadingPhoto { ProgressView() }
          if let data = model.entry.photo, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 250)
              .accessibilityLabel(L10n.text("Фото еды", locale: locale))
            Button(L10n.text("Убрать фото", locale: locale), role: .destructive) {
              selection = nil
              model.entry.photo = nil
            }
          }
        } footer: {
          Text(
            L10n.text(
              "Фото хранится в вашем дневнике и не отправляется в базу продуктов. КБЖУ заполните по составу или упаковке.",
              locale: locale))
        }
        Section {
          TextField(L10n.text("Заметка", locale: locale), text: $model.entry.note, axis: .vertical)
        }
        if let error = model.error { Text(L10n.text(error, locale: locale)).foregroundStyle(.red) }
      }
      .navigationTitle(L10n.text("Запись питания", locale: locale)).navigationBarTitleDisplayMode(
        .inline
      )
      .navigationDestination(isPresented: $addingFood) {
        FoodProductPicker(recent: diary.recentProducts, client: diary.foodSearch) {
          product, amount in
          try model.add(product, amount: amount)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Сохранить", locale: locale)) { save() }
            .disabled(model.isLoadingPhoto || isTransferringPhoto).accessibilityIdentifier(
              "saveFoodEntry")
        }
      }
      .task(id: selection) {
        guard let selection else {
          isTransferringPhoto = false
          return
        }
        isTransferringPhoto = true
        defer { if self.selection == selection { isTransferringPhoto = false } }
        do {
          guard let data = try await selection.loadTransferable(type: Data.self) else {
            throw NutritionError.invalidPhoto
          }
          try Task.checkCancellation()
          await model.importPhoto(data)
        } catch {
          if !Task.isCancelled {
            model.error = "Не удалось обработать фото. Выберите другое изображение."
          }
        }
      }
    }.tint(colorTheme.accent).interactiveDismissDisabled(
      model.isLoadingPhoto || isTransferringPhoto)
  }
  private func save() {
    guard workspaceID == diary.workspaceID else {
      dismiss()
      return
    }
    do {
      if diary.save(try model.validatedEntry()) { dismiss() } else { model.error = diary.error }
    } catch { model.error = error.localizedDescription }
  }
}

private struct FoodPortionEditor: View {
  @Environment(\.locale) private var locale
  @Binding var portion: FoodPortion
  @State private var text: String
  let remove: () -> Void
  init(portion: Binding<FoodPortion>, remove: @escaping () -> Void) {
    _portion = portion
    self.remove = remove
    _text = State(initialValue: portion.wrappedValue.amount.formatted(.number.grouping(.never)))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(portion.product.name).font(.headline)
      HStack {
        let title = portion.product.unit == .grams ? "Масса, г" : "Объём, мл"
        Text(L10n.text(title, locale: locale))
        TextField(L10n.text(title, locale: locale), text: $text)
          .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
      }
      if !portion.amount.isFinite || portion.amount <= 0 || portion.amount > 10_000 {
        Text(L10n.text("Укажите размер порции больше нуля и не больше 10 000.", locale: locale))
          .font(.caption).foregroundStyle(.red)
      }
      Button(L10n.text("Убрать продукт", locale: locale), role: .destructive, action: remove).font(
        .caption)
    }.onChange(of: text) { portion.amount = (try? NutritionInput.number(text)) ?? .nan }
  }
}
