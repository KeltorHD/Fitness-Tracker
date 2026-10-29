import Charts
import FitSessionCore
import SwiftUI

struct ProgressScreen: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var month = Date()
  @State private var selectedExerciseID: UUID?
  private var records: [PersonalRecord] {
    TrainingStatistics.records(in: store.completed.filter { $0.startedAt <= .now })
  }
  private var selectedRecord: PersonalRecord? {
    records.first { $0.id == selectedExerciseID } ?? records.first
  }
  private var yearSessions: [Workout] {
    store.completed.filter {
      Calendar.current.isDate($0.startedAt, equalTo: month, toGranularity: .year)
        && $0.startedAt <= .now
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(spacing: 14) {
            SectionHeading(title: "История", symbol: "clock")
            TrainingMonthCard(date: $month, workouts: store.completed)
          }
          if let record = selectedRecord {
            VStack(spacing: 14) {
              HStack {
                SectionHeading(title: record.exercise.name, symbol: "dumbbell")
                Menu {
                  ForEach(records) { item in
                    Button(item.exercise.name) { selectedExerciseID = item.id }
                  }
                } label: {
                  Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
              }
              VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                  Text("Объём за тренировку, \(unit.rawValue)").font(.subheadline).foregroundStyle(
                    .secondary)
                  Spacer()
                  Label(
                    "\(unit.display(record.weightKG).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)",
                    systemImage: "trophy.fill"
                  )
                  .font(.headline).foregroundStyle(FitTheme.accent)
                }
                Chart(points(for: record.id)) { point in
                  BarMark(
                    x: .value("Дата", point.date),
                    y: .value("Объём", unit.display(point.volume))
                  )
                  .foregroundStyle(FitTheme.accent).cornerRadius(3)
                }.frame(height: 215).chartYAxis { AxisMarks(position: .trailing) }
                  .accessibilityLabel("Объём упражнения по тренировкам")
              }.padding(16).background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
            }
          }
          VStack(spacing: 14) {
            SectionHeading(title: "Общий объём", symbol: "chart.bar")
            VStack(alignment: .leading, spacing: 16) {
              Text("За 26 недель, \(unit.rawValue)").font(.subheadline).foregroundStyle(.secondary)
              Chart(TrainingStatistics.weeks(in: store.completed, count: 26)) { week in
                BarMark(
                  x: .value("Неделя", week.week, unit: .weekOfYear),
                  y: .value("Объём", unit.display(week.volume))
                )
                .foregroundStyle(FitTheme.accent).cornerRadius(3)
              }.frame(height: 180).chartYAxis { AxisMarks(position: .trailing) }
            }.padding(16).background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
          }
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Личные рекорды", symbol: "trophy")
            if records.isEmpty {
              ContentUnavailableView(
                "Пока нет рекордов", systemImage: "trophy",
                description: Text("Они появятся после рабочих подходов с добавленным весом."))
            }
            ForEach(records) { record in
              VStack(spacing: 10) {
                Text(record.exercise.name).font(.headline).frame(
                  maxWidth: .infinity, alignment: .leading)
                LabeledContent(
                  "Максимальный вес",
                  value:
                    "\(unit.display(record.weightKG).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
                )
                if record.estimatedOneRepMax > 0 {
                  LabeledContent(
                    "Расчётный 1ПМ",
                    value:
                      "\(unit.display(record.estimatedOneRepMax).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
                  )
                }
              }.padding(16).background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
            }
            Text(
              "1ПМ — оценка по формуле Эпли для 1–12 повторений. Собственный вес не включается в объём внешнего отягощения."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
      }.background(FitTheme.paper).navigationTitle("Результаты")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              ForEach(
                Array(
                  Set(
                    store.completed.map { Calendar.current.component(.year, from: $0.startedAt) }
                      + [Calendar.current.component(.year, from: .now)])
                ).sorted(by: >), id: \.self
              ) { year in
                Button(String(year)) {
                  var parts = Calendar.current.dateComponents([.month, .day], from: month)
                  parts.year = year
                  parts.day = 1
                  month = Calendar.current.date(from: parts) ?? month
                }
              }
            } label: {
              Text(String(Calendar.current.component(.year, from: month))).foregroundStyle(.primary)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Начать тренировку", systemImage: "plus") { store.start() }.foregroundStyle(
              .primary)
          }
        }
    }
  }
  private func points(for exerciseID: UUID) -> [ExerciseVolumePoint] {
    yearSessions.compactMap { workout in
      let matches = workout.exercises.filter { $0.exercise.id == exerciseID }
      guard !matches.isEmpty else { return nil }
      return ExerciseVolumePoint(
        id: workout.id, date: workout.startedAt,
        volume: matches.flatMap(\.sets).reduce(0) { $0 + $1.volume })
    }.sorted { $0.date < $1.date }
  }
}

private struct ExerciseVolumePoint: Identifiable {
  let id: UUID
  let date: Date
  let volume: Double
}

struct TrainingMonthCard: View {
  @Binding var date: Date
  let workouts: [Workout]
  private var days: [TrainingCalendarDay] {
    TrainingJournal.monthDays(containing: date, workouts: workouts)
  }
  private var count: Int {
    workouts.filter {
      $0.status == .completed
        && Calendar.current.isDate($0.startedAt, equalTo: date, toGranularity: .month)
        && $0.startedAt <= .now
    }.count
  }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 12) {
        HStack {
          Button("Предыдущий месяц", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
          Text(date, format: .dateTime.month(.wide)).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Следующий месяц", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly)
        }.font(.caption).foregroundStyle(.secondary)
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 6
        ) {
          ForEach(days) { day in
            Text(day.date, format: .dateTime.day()).font(.caption)
              .fontWeight(day.hasWorkout ? .semibold : .regular)
              .foregroundStyle(
                day.hasWorkout
                  ? Color.white : day.isInMonth ? Color.primary : Color.secondary.opacity(0.5)
              )
              .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
              .background(day.hasWorkout ? FitTheme.accent : .clear, in: .circle)
              .overlay(
                Circle().stroke(
                  day.isInMonth && !day.hasWorkout ? Color.gray.opacity(0.25) : .clear, lineWidth: 1
                )
              )
              .accessibilityLabel(
                "\(day.date.formatted(date: .complete, time: .omitted))\(day.hasWorkout ? ", была тренировка" : "")"
              )
          }
        }
      }
      Rectangle().fill(.gray.opacity(0.18)).frame(width: 1)
      VStack(spacing: 14) {
        Text("Всего").font(.subheadline).foregroundStyle(.secondary)
        Text("\(count)").font(.largeTitle.weight(.medium)).monospacedDigit()
        Divider()
        ZStack {
          Circle().stroke(.gray.opacity(0.15), lineWidth: 13)
          Circle().trim(
            from: 0,
            to: Double(days.filter { $0.isInMonth && $0.hasWorkout }.count)
              / Double(max(1, days.filter(\.isInMonth).count))
          )
          .stroke(FitTheme.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round))
          .rotationEffect(.degrees(-90))
        }.frame(width: 48, height: 48).padding(.top, 5).accessibilityLabel(
          "Дни с тренировками в выбранном месяце")
      }.frame(width: 68)
    }.fixedSize(horizontal: false, vertical: true).padding(16)
      .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
  }
  private func move(_ value: Int) {
    let start = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    date = Calendar.current.date(byAdding: .month, value: value, to: start) ?? date
  }
}
