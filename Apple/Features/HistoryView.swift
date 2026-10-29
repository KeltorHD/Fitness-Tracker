import FitSessionCore
import SwiftUI

struct HistoryView: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var selected: Workout?
  @State private var repeatAfterDismiss: Workout?
  @State private var filterDate: Date?
  @State private var pendingDelete: Workout?
  @State private var showWeekStats = true
  private var weeks: [JournalWeek] {
    let sessions =
      filterDate.map { date in
        store.completed.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
      } ?? store.completed
    return TrainingJournal.weeks(in: sessions)
  }
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
          if let filterDate {
            HStack {
              Text(filterDate, format: .dateTime.day().month(.wide)).font(.headline)
              Spacer()
              Button("Вся история") { self.filterDate = nil }
            }
          }
          if weeks.isEmpty {
            ContentUnavailableView {
              Label(
                filterDate == nil ? "Начните свой дневник" : "В этот день нет тренировок",
                systemImage: "book.closed")
            } description: {
              Text("Завершённые тренировки появятся здесь по неделям.")
            } actions: {
              Button("Начать тренировку", systemImage: "plus") { store.start() }
                .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier(
                  "startEmptyWorkout")
            }
          }
          ForEach(weeks) { week in
            VStack(alignment: .leading, spacing: 14) {
              Text(weekTitle(week.start)).font(.title2.bold())
              if showWeekStats {
                HStack {
                  SummaryChip(text: "\(week.personalRecords) ЛР", symbol: "trophy")
                  SummaryChip(text: workoutCount(week.workouts.count))
                }
              }
              ForEach(week.workouts) { workout in
                HStack(alignment: .top, spacing: 12) {
                  VStack(spacing: 6) {
                    Circle().fill(.gray.opacity(0.55)).frame(width: 7, height: 7)
                    Rectangle().fill(FitTheme.card).frame(width: 3, height: 14)
                    Image(systemName: "figure.strengthtraining.traditional").font(.title3)
                      .foregroundStyle(FitTheme.accent)
                    Rectangle().fill(FitTheme.card).frame(width: 3).frame(minHeight: 30)
                  }.frame(width: 26)
                  VStack(alignment: .leading, spacing: 8) {
                    Text(workout.startedAt.formatted(.dateTime.weekday(.wide)).localizedCapitalized)
                      .font(.subheadline)
                    Button {
                      selected = workout
                    } label: {
                      VStack(alignment: .leading, spacing: 7) {
                        Text(workout.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Text(
                          "\(workout.duration().workoutDuration)  \(unit.display(workout.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)  · \(workout.completedSets) подх."
                        )
                        .font(.subheadline).foregroundStyle(.primary)
                      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
                    }.buttonStyle(.plain)
                      .contextMenu {
                        Button("Повторить", systemImage: "arrow.counterclockwise") {
                          store.repeatWorkout(workout)
                        }
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                          pendingDelete = workout
                        }
                      }
                  }
                }.fixedSize(horizontal: false, vertical: true)
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
            Button("Вся история") { filterDate = nil }
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
        }
      }
      .refreshable { store.reload() }
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

  private var weekStrip: some View {
    HStack(spacing: 0) {
      ForEach(TrainingJournal.weekDays(containing: .now), id: \.self) { day in
        let trained = store.completed.contains {
          Calendar.current.isDate($0.startedAt, inSameDayAs: day)
        }
        let highlighted = Calendar.current.isDate(day, inSameDayAs: filterDate ?? .now)
        Button {
          filterDate = day
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
    if Calendar.current.isDate(start, equalTo: .now, toGranularity: .weekOfYear) {
      return "На этой неделе"
    }
    let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
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

extension TimeInterval {
  var workoutDuration: String {
    let minutes = Int(max(0, self)) / 60
    return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
  }
}
