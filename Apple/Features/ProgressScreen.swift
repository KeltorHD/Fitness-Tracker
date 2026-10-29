import Charts
import FitSessionCore
import SwiftUI

struct ProgressScreen: View {
  @Environment(AppStore.self) private var store
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @Environment(\.calendar) private var calendar
  @Environment(\.scenePhase) private var phase
  @State private var model = ProgressViewModel()
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(spacing: 14) {
            SectionHeading(title: "История", symbol: "clock")
            TrainingMonthCard(date: model.month, summary: model.report.month, move: model.moveMonth)
          }
          if let record = model.selectedRecord {
            VStack(spacing: 14) {
              HStack {
                SectionHeading(title: record.exercise.name, symbol: "dumbbell")
                Menu {
                  ForEach(model.report.records) { item in
                    Button(item.exercise.name) { model.selectedExerciseID = item.id }
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
                Chart(model.points) { point in
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
              Chart(model.report.weeks) { week in
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
            if model.report.records.isEmpty {
              ContentUnavailableView(
                "Пока нет рекордов", systemImage: "trophy",
                description: Text("Они появятся после рабочих подходов с добавленным весом."))
            }
            ForEach(model.report.records) { record in
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
              ForEach(model.report.years, id: \.self) { year in
                Button(String(year)) { model.selectYear(year) }
              }
            } label: {
              Text(String(model.year)).foregroundStyle(.primary)
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Начать тренировку", systemImage: "plus") { store.start() }.foregroundStyle(
              .primary)
          }
        }
        .onChange(of: store.workouts, initial: true) { refresh() }
        .onChange(of: calendar) { refresh() }
        .onChange(of: phase) { if phase == .active { refresh() } }
    }
  }
  private func refresh() { model.refresh(workouts: store.workouts, calendar: calendar) }
}

struct TrainingMonthCard: View {
  let date: Date
  let summary: TrainingMonthSummary
  let move: (Int) -> Void
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
          ForEach(summary.days) { day in
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
        Text("\(summary.workoutCount)").font(.largeTitle.weight(.medium)).monospacedDigit()
        Divider()
        ZStack {
          Circle().stroke(.gray.opacity(0.15), lineWidth: 13)
          Circle().trim(
            from: 0,
            to: summary.trainingDayFraction
          )
          .stroke(FitTheme.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round))
          .rotationEffect(.degrees(-90))
        }.frame(width: 48, height: 48).padding(.top, 5).accessibilityLabel(
          "Дни с тренировками в выбранном месяце")
      }.frame(width: 68)
    }.fixedSize(horizontal: false, vertical: true).padding(16)
      .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
  }
}
