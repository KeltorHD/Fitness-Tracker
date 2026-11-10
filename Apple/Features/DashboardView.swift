import SwiftUI

private enum DiarySection: Int, Hashable { case workouts, nutrition, sleep }

struct DashboardView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @State private var section = DiarySection.workouts
  @State private var date = Date()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: 8) {
          Picker(L10n.text("Раздел дневника", locale: locale), selection: $section) {
            Text(L10n.text("Тренировки", locale: locale)).tag(DiarySection.workouts)
            Text(L10n.text("Питание", locale: locale)).tag(DiarySection.nutrition)
            Text(L10n.text("Сон", locale: locale)).tag(DiarySection.sleep)
          }.pickerStyle(.segmented).accessibilityIdentifier("diarySection")
          HStack {
            Button(L10n.text("Предыдущий день", locale: locale), systemImage: "chevron.left") {
              moveDay(-1)
            }
            .labelStyle(.iconOnly).accessibilityIdentifier("previousDiaryDay")
            Spacer(minLength: 8)
            DatePicker(
              L10n.text("Дата", locale: locale), selection: $date, displayedComponents: .date
            )
            .labelsHidden().accessibilityIdentifier("diaryDate")
            Spacer(minLength: 8)
            Button(L10n.text("Следующий день", locale: locale), systemImage: "chevron.right") {
              moveDay(1)
            }
            .labelStyle(.iconOnly).accessibilityIdentifier("nextDiaryDay")
            if !calendar.isDateInToday(date) {
              Button(L10n.text("Сегодня", locale: locale), systemImage: "arrow.uturn.backward") {
                date = .now
              }
              .labelStyle(.iconOnly).accessibilityIdentifier("diaryToday")
            }
          }.buttonStyle(.bordered).controlSize(.small)
        }.padding(.horizontal, 16).padding(.vertical, 8)
        TabView(selection: $section) {
          HistoryView(date: $date, isSelected: section == .workouts).tag(DiarySection.workouts)
          Group {
            if let nutrition = store.nutrition {
              NutritionDiaryView(model: nutrition, date: $date, isSelected: section == .nutrition)
                .id(nutrition.workspaceID)
            } else {
              ContentUnavailableView(
                L10n.text("Питание недоступно", locale: locale), systemImage: "fork.knife")
            }
          }.tag(DiarySection.nutrition)
          Group {
            if store.isDemoMode {
              ContentUnavailableView(
                L10n.text("Данные сна недоступны в демо-режиме", locale: locale),
                systemImage: "bed.double")
            } else {
              SleepDiaryView(date: $date, isSelected: section == .sleep, alarms: store.sleepAlarms)
            }
          }.tag(DiarySection.sleep)
        }.tabViewStyle(.page(indexDisplayMode: .never))
      }
      .background(FitTheme.paper).navigationTitle(L10n.text("Дневник", locale: locale))
      .toolbar { SettingsToolbar() }
    }
  }
  private func moveDay(_ value: Int) {
    if let next = calendar.date(byAdding: .day, value: value, to: date) { date = next }
  }
}
