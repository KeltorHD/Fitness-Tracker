import SwiftUI

private enum DiarySection: Int, Hashable { case workouts, nutrition, sleep }

struct DashboardView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @State private var section = DiarySection.workouts
  @State private var date = Date()
  @State private var showAllHistory = false
  @State private var showWeekStats = true

  private var selectedDate: Binding<Date> {
    Binding(
      get: { date },
      set: {
        date = $0
        showAllHistory = false
      })
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        DiaryCalendarView(date: selectedDate, workouts: store.workouts) {
          if section == .workouts {
            Menu {
              Toggle(L10n.text("Статистика за неделю", locale: locale), isOn: $showWeekStats)
                .accessibilityIdentifier("calendarWeekStatistics")
              Toggle(L10n.text("Вся история", locale: locale), isOn: $showAllHistory)
                .accessibilityIdentifier("calendarAllHistory")
            } label: {
              Image(systemName: "line.3.horizontal.decrease").frame(width: 36, height: 44)
            }
            .accessibilityLabel(L10n.text("Фильтры", locale: locale))
            .accessibilityIdentifier("diaryWorkoutFilters")
          }
        }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        TabView(selection: $section) {
          HistoryView(
            date: selectedDate, showAllHistory: $showAllHistory, showWeekStats: $showWeekStats
          ).tag(DiarySection.workouts)
          Group {
            if let nutrition = store.nutrition {
              NutritionDiaryView(
                model: nutrition, date: selectedDate, isSelected: section == .nutrition
              )
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
                date: selectedDate, isSelected: section == .sleep, alarms: store.sleepAlarms,
                reader: SleepUITestFixture.reader())
            }
          }.tag(DiarySection.sleep)
        }.tabViewStyle(.page(indexDisplayMode: .never))
      }
      .background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: 8) {
            Text(L10n.text("Дневник", locale: locale)).font(.title2.bold())
              .lineLimit(1).fixedSize(horizontal: true, vertical: false)
              .accessibilityAddTraits(.isHeader).accessibilityIdentifier("diaryHeaderTitle")
            Picker(L10n.text("Раздел дневника", locale: locale), selection: $section) {
              Label(
                L10n.text("Тренировки", locale: locale),
                systemImage: "figure.strengthtraining.traditional"
              ).tag(DiarySection.workouts)
              Label(L10n.text("Питание", locale: locale), systemImage: "fork.knife")
                .tag(DiarySection.nutrition)
              Label(L10n.text("Сон", locale: locale), systemImage: "moon.zzz.fill")
                .tag(DiarySection.sleep)
            }.labelStyle(.iconOnly).pickerStyle(.segmented).frame(width: 156)
              .accessibilityIdentifier("diarySection")
          }
        }
        .sharedBackgroundVisibility(.hidden)
        SettingsToolbar()
      }
    }
  }
}
