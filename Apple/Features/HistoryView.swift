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
  @State private var showWeekStats = true
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 26) {
          weekStrip
          if let active = store.active {
            Button {
              store.start()
            } label: {
              HStack {
                Image(systemName: "play.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                  Text(active.name).font(.headline)
                  Text(
                    active.status == .paused
                      ? L10n.text("На паузе · продолжить", locale: locale)
                      : L10n.text("Продолжить тренировку", locale: locale)
                  )
                  .font(.subheadline)
                }
                Spacer()
                Image(systemName: "chevron.right")
              }.foregroundStyle(colorTheme.accent).padding(18)
                .background(
                  colorTheme.accent.opacity(0.08), in: .rect(cornerRadius: FitTheme.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("resumeWorkout")
          }
          if let date = model.filterDate {
            HStack {
              Text(date, format: .dateTime.day().month(.wide)).font(.headline)
              Spacer()
              Button(L10n.text("Вся история", locale: locale)) { model.filterDate = nil }
            }
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
            } actions: {
              Button(L10n.text("Начать тренировку", locale: locale), systemImage: "plus") {
                store.start()
              }
              .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier(
                "startEmptyWorkout")
            }
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
                }
              }
              ForEach(week.workouts) { workout in
                HistoryWorkoutRow(
                  workout: workout, unit: unit,
                  onSelect: { selected = workout },
                  onRepeat: { store.repeatWorkout(workout) },
                  onDelete: { pendingDelete = workout })
              }
            }
          }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
      }
      .refreshable { store.reload() }
      .background(FitTheme.paper).navigationTitle(L10n.text("Дневник", locale: locale))
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Toggle(L10n.text("Статистика за неделю", locale: locale), isOn: $showWeekStats)
            Button(L10n.text("Вся история", locale: locale)) { model.filterDate = nil }
          } label: {
            Image(systemName: "ellipsis").foregroundStyle(.primary)
          }
          Button(L10n.text("Начать тренировку", locale: locale), systemImage: "plus") {
            store.start()
          }
          .foregroundStyle(.primary).accessibilityIdentifier("startWorkout")
        }
      }
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
      .onChange(of: calendar) { refresh() }
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
      }
    }
  }

  private func refresh() { model.refresh(workouts: store.workouts, calendar: calendar) }

  private var weekStrip: some View {
    HStack(spacing: 0) {
      ForEach(model.days) { item in
        let day = item.date
        let trained = item.hasWorkout
        let highlighted = calendar.isDate(day, inSameDayAs: model.filterDate ?? .now)
        Button {
          model.filterDate = day
        } label: {
          VStack(spacing: 8) {
            Text(day, format: .dateTime.weekday(.narrow)).font(.caption).textCase(.uppercase)
            ZStack {
              Circle().stroke(trained ? .clear : Color.gray.opacity(0.2), lineWidth: 1.5)
              if trained {
                Circle().fill(colorTheme.accent)
                Image(systemName: "checkmark").font(.headline).foregroundStyle(
                  FitTheme.accentForeground)
              } else {
                Text(day, format: .dateTime.day()).font(.subheadline)
              }
            }.frame(width: 34, height: 34)
          }.foregroundStyle(highlighted ? colorTheme.accent : FitTheme.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(highlighted ? colorTheme.accent.opacity(0.12) : .clear, in: .capsule)
        }.buttonStyle(.plain).accessibilityLabel(
          day.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide).year()))
      }
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
