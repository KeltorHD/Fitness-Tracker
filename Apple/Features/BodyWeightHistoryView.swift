import FitnessTrackerCore
import SwiftUI

struct BodyWeightHistoryView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var model = BodyWeightViewModel()
  @State private var editing: EditRequest?
  @State private var deleting: BodyWeightPoint?

  private struct EditRequest: Identifiable {
    let id = UUID()
    var entry: BodyWeightEntry? = nil
    var workout: Workout? = nil
  }

  var body: some View {
    List {
      if model.items.isEmpty {
        ContentUnavailableView(
          L10n.text("Пока нет записей веса", locale: locale), systemImage: "scalemass",
          description: Text(L10n.text("Запишите вес здесь или в тренировке.", locale: locale)))
      }
      ForEach(model.items) { item in
        Button {
          edit(item.point)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "\(unit.display(item.point.weightKG).formatted(.number.locale(L10n.numberLocale).precision(.fractionLength(0...2)))) \(L10n.text(unit.rawValue, locale: locale))"
            )
            .font(.headline).foregroundStyle(.primary)
            Text(item.point.date, format: .dateTime.day().month().year().hour().minute())
              .font(.subheadline).foregroundStyle(.secondary)
            Text(item.workoutName ?? L10n.text("Взвешивание", locale: locale))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .swipeActions(allowsFullSwipe: false) {
          Button(L10n.text("Удалить", locale: locale), role: .destructive) { deleting = item.point }
        }
      }
    }
    .navigationTitle(L10n.text("История веса", locale: locale))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(L10n.text("Записать вес", locale: locale), systemImage: "plus") {
          editing = EditRequest()
        }
      }
    }
    .sheet(item: $editing) { BodyWeightEditor(entry: $0.entry, workout: $0.workout, unit: unit) }
    .confirmationDialog(
      L10n.text("Удалить запись веса?", locale: locale),
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button(L10n.text("Удалить", locale: locale), role: .destructive) {
        let point = deleting
        deleting = nil
        if let point { store.deleteBodyWeight(point) }
      }
    } message: {
      Text(
        L10n.text(
          "Если вес относится к тренировке, будет убрано только её значение веса тела.",
          locale: locale))
    }
    .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    .onChange(of: store.bodyWeights, initial: true) { refresh() }
    .onChange(of: store.workouts) { refresh() }
  }
  private func refresh() { model.refresh(entries: store.bodyWeights, workouts: store.workouts) }
  private func edit(_ point: BodyWeightPoint) {
    switch point.source {
    case .measurement(let id):
      if let entry = store.bodyWeights.first(where: { $0.id == id }) {
        editing = EditRequest(entry: entry)
      } else {
        store.error = "Запись веса больше недоступна."
      }
    case .workout(let id):
      if let workout = store.workouts.first(where: { $0.id == id }) {
        editing = EditRequest(workout: workout)
      } else {
        store.error = "Запись веса больше недоступна."
      }
    }
  }
}
