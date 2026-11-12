import SwiftUI

private enum DiarySection: Int, Hashable { case workouts, nutrition, sleep }

struct DashboardView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @State private var section = DiarySection.workouts
  @State private var date = Date()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        DiaryCalendarView(date: $date, workouts: store.workouts)
          .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        Picker(L10n.text("Раздел дневника", locale: locale), selection: $section) {
          Text(L10n.text("Тренировки", locale: locale)).tag(DiarySection.workouts)
          Text(L10n.text("Питание", locale: locale)).tag(DiarySection.nutrition)
          Text(L10n.text("Сон", locale: locale)).tag(DiarySection.sleep)
        }.pickerStyle(.segmented).accessibilityIdentifier("diarySection")
          .padding(.horizontal, 16).padding(.bottom, 8)
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
              SleepDiaryView(
                date: $date, isSelected: section == .sleep, alarms: store.sleepAlarms,
                reader: SleepUITestFixture.reader())
            }
          }.tag(DiarySection.sleep)
        }.tabViewStyle(.page(indexDisplayMode: .never))
      }
      .background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Text(L10n.text("Дневник", locale: locale)).font(.title2.bold())
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("diaryHeaderTitle")
        }
        .sharedBackgroundVisibility(.hidden)
        SettingsToolbar()
      }
    }
  }
}
