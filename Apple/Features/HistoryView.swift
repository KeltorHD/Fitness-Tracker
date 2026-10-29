import FitSessionCore
import SwiftUI

struct HistoryView: View {
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
                  Text(active.status == .paused ? "На паузе · продолжить" : "Продолжить тренировку")
                    .font(.subheadline)
                }
                Spacer()
                Image(systemName: "chevron.right")
              }.foregroundStyle(FitTheme.accent).padding(18)
                .background(FitTheme.accent.opacity(0.08), in: .rect(cornerRadius: FitTheme.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("resumeWorkout")
          }
          if let date = model.filterDate {
            HStack {
              Text(date, format: .dateTime.day().month(.wide)).font(.headline)
              Spacer()
              Button("Вся история") { model.filterDate = nil }
            }
          }
          if model.weeks.isEmpty {
            ContentUnavailableView {
              Label(
                model.filterDate == nil ? "Начните свой дневник" : "В этот день нет тренировок",
                systemImage: "book.closed")
            } description: {
              Text("Завершённые тренировки появятся здесь по неделям.")
            } actions: {
              Button("Начать тренировку", systemImage: "plus") { store.start() }
                .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier(
                  "startEmptyWorkout")
            }
          }
          ForEach(model.weeks) { week in
            VStack(alignment: .leading, spacing: 14) {
              Text(weekTitle(week.start)).font(.title2.bold())
              if showWeekStats {
                HStack {
                  SummaryChip(text: "\(week.personalRecords) ЛР", symbol: "trophy")
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
      .background(FitTheme.paper).navigationTitle("Дневник")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Toggle("Статистика за неделю", isOn: $showWeekStats)
            Button("Вся история") { model.filterDate = nil }
          } label: {
            Image(systemName: "ellipsis").foregroundStyle(.primary)
          }
          Button("Начать тренировку", systemImage: "plus") { store.start() }
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
          ).tint(FitTheme.accent)
            .onAppear { store.showingWorkoutDetail = true }
        }
      }
      .refreshable { store.reload() }
      .onChange(of: store.workouts, initial: true) { refresh() }
      .onChange(of: calendar) { refresh() }
      .onChange(of: phase) { if phase == .active { refresh() } }
      .confirmationDialog(
        "Удалить тренировку?",
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible
      ) {
        Button("Удалить", role: .destructive) {
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
                Circle().fill(FitTheme.accent)
                Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
              } else {
                Text(day, format: .dateTime.day()).font(.subheadline)
              }
            }.frame(width: 34, height: 34)
          }.foregroundStyle(highlighted ? FitTheme.accent : FitTheme.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(highlighted ? FitTheme.accent.opacity(0.12) : .clear, in: .capsule)
        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
      }
    }
  }
  private func weekTitle(_ start: Date) -> String {
    if calendar.isDate(start, equalTo: .now, toGranularity: .weekOfYear) {
      return "На этой неделе"
    }
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    return "\(start.formatted(.dateTime.day()))–\(end.formatted(.dateTime.day().month(.wide)))"
  }
  private func workoutCount(_ value: Int) -> String {
    let suffix =
      value % 10 == 1 && value % 100 != 11
      ? "тренировка"
      : (2...4).contains(value % 10) && !(12...14).contains(value % 100)
        ? "тренировки" : "тренировок"
    return "\(value) \(suffix)"
  }
}
