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
          Picker(L10n.text("Раздел дневника", locale: locale), selection: $section) {
            Label(
              L10n.text("Тренировки", locale: locale),
              systemImage: "figure.strengthtraining.traditional"
            ).tag(DiarySection.workouts)
            Label(L10n.text("Питание", locale: locale), systemImage: "fork.knife")
              .tag(DiarySection.nutrition)
            Label(L10n.text("Сон", locale: locale), systemImage: "moon.zzz.fill")
              .tag(DiarySection.sleep)
          }.labelStyle(.iconOnly).pickerStyle(.segmented).frame(width: 168)
            .accessibilityIdentifier("diarySection")
        }
        .sharedBackgroundVisibility(.hidden)
        SettingsToolbar()
      }
    }
  }
}
