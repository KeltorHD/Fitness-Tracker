import FitnessTrackerCore
import SwiftUI

struct HistoryView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var selected: Workout?
  @State private var repeatAfterDismiss: Workout?
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @State private var model = HistoryViewModel()
  @State private var pendingDelete: Workout?
  @State private var templateDraft: WorkoutTemplate?
  @Binding var date: Date
  @Binding var showAllHistory: Bool
  @Binding var showWeekStats: Bool
  var body: some View {
    List {
      if let active = store.active {
        Button {
          store.presentWorkoutStart()
        } label: {
          HStack {
            Image(systemName: "play.circle.fill").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
              Text(active.name).font(.headline)
              Text(
                active.status == .paused
                  ? L10n.text("На паузе · продолжить", locale: locale)
                  : L10n.text("Продолжить тренировку", locale: locale)
              ).font(.subheadline)
            }
            Spacer()
            Image(systemName: "chevron.right")
          }.foregroundStyle(colorTheme.accent).padding(18)
            .background(colorTheme.accent.opacity(0.08), in: .rect(cornerRadius: FitTheme.radius))
            .themeGlow(in: RoundedRectangle(cornerRadius: FitTheme.radius), emphasized: true)
        }.buttonStyle(.plain).accessibilityIdentifier("resumeWorkout").cardListRow()
      }
      if let summary = model.diarySummary {
        TrainingDiaryInsightsView(summary: summary).cardListRow()
      }
      if let date = model.filterDate {
        HStack {
          Text(date, format: .dateTime.day().month(.wide)).font(.headline)
            .accessibilityIdentifier("historyScope")
          Spacer()
          Button(L10n.text("Вся история", locale: locale)) { showAllHistory = true }
        }.cardListRow()
      } else {
        HStack {
          Text(L10n.text("Все тренировки", locale: locale)).font(.headline)
            .accessibilityIdentifier("historyScope")
          Spacer()
          Button(L10n.text("Выбранный день", locale: locale)) { showAllHistory = false }
        }.cardListRow()
      }
      if model.weeks.isEmpty {
        ContentUnavailableView {
          Label(
            model.filterDate == nil
              ? L10n.text("Начните свой дневник", locale: locale)
              : L10n.text("В этот день нет тренировок", locale: locale),
            systemImage: "book.closed")
        } description: {
          Text(L10n.text("Завершённые тренировки появятся здесь по неделям.", locale: locale))
        }.cardListRow()
      }
      ForEach(model.weeks) { week in
        VStack(alignment: .leading, spacing: 14) {
          Text(weekTitle(week.start)).font(.title2.bold())
          if showWeekStats {
            HStack {
              SummaryChip(
                text: L10n.countText(week.personalRecords, kind: "record", locale: locale),
                symbol: "trophy")
              SummaryChip(text: workoutCount(week.workouts.count))
            }.accessibilityElement(children: .contain)
              .accessibilityIdentifier("historyWeekStatistics_\(week.start.timeIntervalSince1970)")
          }
        }.padding(.top, 12).cardListRow()
        ForEach(week.workouts) { workout in
          HistoryWorkoutRow(
            workout: workout, unit: unit,
            onSelect: { selected = workout },
            onRepeat: { store.repeatWorkout(workout) },
            onCreateTemplate: { createTemplate(from: workout) },
            onDelete: { pendingDelete = workout }
          )
          .cardListRow()
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
              pendingDelete = workout
            } label: {
              Label(L10n.text("Удалить", locale: locale), systemImage: "trash")
            }.tint(.red)
              .accessibilityIdentifier("swipeDeleteWorkout_\(workout.id)")
            Button {
              createTemplate(from: workout)
            } label: {
              Label(L10n.text("Создать шаблон", locale: locale), systemImage: "list.clipboard")
            }.tint(colorTheme.accent)
              .accessibilityIdentifier("swipeCreateTemplateFromHistory_\(workout.id)")
          }
        }
      }
    }
    .listStyle(.plain).scrollContentBackground(.hidden)
    .refreshable { store.reload() }
    .background(FitTheme.paper)
    .sheet(
      item: $selected,
      onDismiss: {
        store.showingWorkoutDetail = false
        if let workout = repeatAfterDismiss {
          repeatAfterDismiss = nil
          store.repeatWorkout(workout)
        }
      }
    ) { workout in
      NavigationStack {
        WorkoutDetailView(
          workout: workout,
          onRepeat: {
            repeatAfterDismiss = $0
            selected = nil
          }
        ).tint(colorTheme.accent)
          .onAppear { store.showingWorkoutDetail = true }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .onChange(of: store.workouts, initial: true) { refresh() }
    .sheet(item: $templateDraft, onDismiss: { store.showingTemplateEditor = false }) { draft in
      TemplateEditor(template: draft).onAppear { store.showingTemplateEditor = true }
    }
    .onChange(of: calendar) { refresh() }
    .onChange(of: date, initial: true) {
      model.filterDate = showAllHistory ? nil : date
      refresh()
    }
    .onChange(of: showAllHistory) { model.filterDate = showAllHistory ? nil : date }
    .onChange(of: phase) { if phase == .active { refresh() } }
    .confirmationDialog(
      L10n.text("Удалить тренировку?", locale: locale),
      isPresented: Binding(
        get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button(L10n.text("Удалить", locale: locale), role: .destructive) {
        if let pendingDelete { store.delete(workout: pendingDelete) }
        pendingDelete = nil
      }
      .accessibilityIdentifier("confirmDeleteWorkout")
      Button(L10n.text("Отмена", locale: locale), role: .cancel) { pendingDelete = nil }
    }
  }

  private func refresh() { model.refresh(workouts: store.workouts, calendar: calendar, day: date) }

  private func createTemplate(from workout: Workout) {
    do {
      templateDraft = try WorkoutEngine.makeTemplate(from: workout)
    } catch {
      store.error = error.localizedDescription
    }
  }

  private func weekTitle(_ start: Date) -> String {
    if calendar.isDate(start, equalTo: .now, toGranularity: .weekOfYear) {
      return L10n.text("На этой неделе", locale: locale)
    }
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    return
      "\(start.formatted(.dateTime.locale(locale).day()))–\(end.formatted(.dateTime.locale(locale).day().month(.wide)))"
  }
  private func workoutCount(_ value: Int) -> String { L10n.workoutCount(value, locale: locale) }
}
