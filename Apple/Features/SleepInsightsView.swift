import Charts
import FitnessTrackerCore
import SwiftUI

struct SleepInsightsView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.fitnessColorTheme) private var theme
  let nights: [SleepNight]
  let day: Date
  @State private var days = 7
  @State private var chartDate: Date?
  @State private var focusedDay: Date?
  @State private var selectedTime: Date?
  @State private var focusedPeriod: SleepPeriod?
  @State private var selectedStage: SleepStage?
  private var trend: SleepTrend {
    SleepTrend(nights: nights, endingOn: day, days: days, calendar: calendar)
  }
  private var night: SleepNight? { trend.night(at: focusedDay ?? day, calendar: calendar) }
  private var trendDomain: ClosedRange<Date> {
    let start = trend.nights.first?.day ?? calendar.startOfDay(for: day)
    let end = calendar.date(byAdding: .day, value: 1, to: trend.nights.last?.day ?? start) ?? start
    return start...max(start, end)
  }
  var body: some View {
    Group {
      if let night, let asleep = night.asleep {
        summary(night, asleep: asleep).fitCard().cardListRow().accessibilityElement(
          children: .contain
        ).accessibilityIdentifier(
          "sleepNightSummary")
        phases(night).fitCard().cardListRow()
        details(night).fitCard().cardListRow()
      } else if let night, let bed = night.inBed {
        VStack(alignment: .leading, spacing: 12) {
          Label(L10n.text("В постели", locale: locale), systemImage: "bed.double.fill").font(
            .headline)
          Text(SleepDisplay.duration(bed, locale: locale)).font(.largeTitle.bold())
            .monospacedDigit()
          Text(
            L10n.text(
              "Источник передал только время в постели, без длительности и фаз сна.", locale: locale
            )
          ).font(.subheadline).foregroundStyle(.secondary)
        }.fitCard().cardListRow()
      } else {
        ContentUnavailableView {
          Label(L10n.text("Нет записей сна за эту ночь", locale: locale), systemImage: "moon.zzz")
        } description: {
          Text(
            L10n.text(
              "Данные могут ещё не синхронизироваться с часов. Проверьте записи и доступ в приложении «Здоровье».",
              locale: locale))
        }.cardListRow()
      }
      history.fitCard().cardListRow()
    }
    .onChange(of: day) { _, _ in
      chartDate = nil
      focusedDay = nil
      resetPhase()
    }
    .onChange(of: days) { _, _ in
      chartDate = nil
      focusedDay = nil
      resetPhase()
    }
    .onChange(of: chartDate) { _, value in
      if let value { focusedDay = calendar.startOfDay(for: value) }
    }
    .onChange(of: night?.id) { _, _ in resetPhase() }
  }
  private func summary(_ night: SleepNight, asleep: TimeInterval) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(night.day, format: .dateTime.weekday(.wide).day().month()).font(.subheadline)
            .foregroundStyle(.secondary)
          Text(SleepDisplay.duration(asleep, locale: locale)).font(
            .system(.largeTitle, design: .rounded).bold()
          ).monospacedDigit().accessibilityIdentifier("selectedSleepDuration")
          Text(L10n.text("Во сне", locale: locale)).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        phaseRing(night).frame(width: 136, height: 136)
      }
      if let delta = trend.differenceFromPrevious(night, calendar: calendar) {
        Label {
          Text(
            L10n.format(
              delta >= 0 ? "На %@ больше прошлой ночи" : "На %@ меньше прошлой ночи",
              SleepDisplay.duration(abs(delta), locale: locale), locale: locale))
        } icon: {
          Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
        }
        .font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 24) {
        if let start = night.sleepStart {
          timeMetric("Начало сна", date: start, symbol: "moon.fill")
        }
        if let end = night.sleepEnd { timeMetric("Пробуждение", date: end, symbol: "sun.max.fill") }
      }
      if let source = night.sourceName {
        Label(source, systemImage: "heart.text.clipboard").font(.caption).foregroundStyle(
          .secondary)
      }
    }
  }
  private func phaseRing(_ night: SleepNight) -> some View {
    let stages = SleepDisplay.recordedStages.filter { night.duration($0) > 0 }
    return DiaryRingChart(
      segments: stages.map {
        DiaryRingSegment(id: $0.rawValue, value: night.duration($0), color: SleepDisplay.color($0))
      }, selectedID: selectedStage?.rawValue,
      onSelect: { id in
        if let stage = SleepStage(rawValue: id) { focus(stage, in: night) }
      }
    ) {
      if let selectedStage, let share = night.recordedStageFraction(selectedStage) {
        VStack(spacing: 2) {
          Text(share, format: .percent.precision(.fractionLength(0))).font(.headline)
            .monospacedDigit()
          Text(SleepDisplay.chartTitle(selectedStage, locale: locale)).font(.caption2)
            .foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
        }.padding(22)
      } else {
        Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(theme.accent)
      }
    }
    .accessibilityLabel(L10n.text("Доли фаз сна", locale: locale))
    .accessibilityValue(selectedStage.map { SleepDisplay.title($0, locale: locale) } ?? "")
    .accessibilityIdentifier("sleepPhaseRing")
  }
  private func phases(_ night: SleepNight) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(L10n.text("Как прошла ночь", locale: locale)).font(.headline)
        Spacer()
        if selectedStage != nil || focusedPeriod != nil {
          Button(L10n.text("Сбросить выбор", locale: locale), systemImage: "xmark.circle.fill") {
            resetPhase()
          }
          .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
        }
      }
      Chart {
        ForEach(night.periods) { period in
          BarMark(
            xStart: .value(L10n.text("Начало", locale: locale), period.interval.start),
            xEnd: .value(L10n.text("Конец", locale: locale), period.interval.end),
            y: .value(
              L10n.text("Фаза", locale: locale),
              SleepDisplay.chartTitle(period.stage, locale: locale)), height: .ratio(0.6)
          )
          .cornerRadius(5).foregroundStyle(SleepDisplay.color(period.stage))
          .opacity(selectedStage == nil || selectedStage == period.stage ? 1 : 0.25)
        }
        if let selected = focusedPeriod {
          RuleMark(
            x: .value(L10n.text("Выбранный участок", locale: locale), selected.interval.start)
          ).foregroundStyle(.primary.opacity(0.4)).lineStyle(
            StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
      }
      .chartYScale(
        domain: [SleepStage.deep, .core, .rem, .awake, .unspecified].filter {
          night.duration($0) > 0
        }.map { SleepDisplay.chartTitle($0, locale: locale) }
      )
      .chartXSelection(value: $selectedTime)
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.hour().minute())
        }
      }
      .frame(height: 190).accessibilityIdentifier("sleepStagesChart")
      .accessibilityLabel(L10n.text("Фазы сна за ночь", locale: locale))
      .onChange(of: selectedTime) { _, time in
        if let time, let period = night.period(at: time) {
          focusedPeriod = period
          selectedStage = period.stage
        }
      }
      if let period = focusedPeriod {
        VStack(alignment: .leading, spacing: 4) {
          Label(SleepDisplay.title(period.stage, locale: locale), systemImage: "circle.fill")
            .foregroundStyle(SleepDisplay.color(period.stage)).font(.subheadline.bold())
          HStack(spacing: 4) {
            Text(period.interval.start, style: .time)
            Text(verbatim: "—")
            Text(period.interval.end, style: .time)
            Spacer()
            Text(SleepDisplay.duration(period.interval.duration, locale: locale))
          }.font(.caption).monospacedDigit()
        }.accessibilityElement(children: .combine).accessibilityIdentifier("selectedSleepPhase")
      } else {
        Text(
          L10n.text("Коснитесь графика или фазы, чтобы рассмотреть сон подробнее.", locale: locale)
        ).font(.caption).foregroundStyle(.secondary)
      }
      ForEach(
        SleepDisplay.recordedStages.filter { $0 == .awake || night.duration($0) > 0 }, id: \.self
      ) { stage in
        Button {
          if selectedStage == stage { resetPhase() } else { focus(stage, in: night) }
        } label: {
          VStack(spacing: 7) {
            HStack {
              Circle().fill(SleepDisplay.color(stage)).frame(width: 8, height: 8)
              Text(SleepDisplay.title(stage, locale: locale)).font(.subheadline)
              Spacer()
              Text(
                night.duration(stage) > 0
                  ? SleepDisplay.duration(night.duration(stage), locale: locale)
                  : L10n.text("Нет данных", locale: locale)
              ).font(
                .subheadline.weight(.semibold)
              ).monospacedDigit()
              if night.duration(stage) > 0, let share = night.recordedStageFraction(stage) {
                Text(share, format: .percent.precision(.fractionLength(0))).font(.caption)
                  .foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
              }
            }
            if night.duration(stage) > 0 {
              ProgressView(value: night.recordedStageFraction(stage) ?? 0)
                .tint(SleepDisplay.color(stage))
            }
          }.frame(minHeight: 44).padding(.vertical, 5).contentShape(.rect)
        }.buttonStyle(.plain).disabled(night.duration(stage) == 0)
          .accessibilityIdentifier("sleepStage_\(stage.rawValue)")
          .accessibilityAddTraits(selectedStage == stage ? [.isSelected] : [])
      }
      Text(L10n.text("Доли рассчитаны по записанным фазам сна и бодрствования.", locale: locale))
        .font(.caption).foregroundStyle(.secondary)
      if !night.hasStages {
        Text(L10n.text("Источник не передал подробные фазы сна.", locale: locale)).font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
  private func details(_ night: SleepNight) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L10n.text("Подробности сна", locale: locale)).font(.headline)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], alignment: .leading, spacing: 18
      ) {
        if let longest = night.longestSleepEpisode {
          metric(
            "Без пробуждений", value: SleepDisplay.duration(longest, locale: locale),
            symbol: "moon.zzz.fill")
        }
        if night.hasStages {
          metric(
            "Периоды бодрствования", value: String(night.awakePeriods), symbol: "waveform.path")
        }
        if let bed = night.inBed {
          metric(
            "В постели", value: SleepDisplay.duration(bed, locale: locale), symbol: "bed.double")
        }
        if let latency = night.sleepOnsetLatency {
          metric(
            "Время засыпания", value: SleepDisplay.duration(latency, locale: locale),
            symbol: "hourglass")
        }
        if let efficiency = night.efficiency {
          metric(
            "Доля сна в постели",
            value: efficiency.formatted(.percent.precision(.fractionLength(0)).locale(locale)),
            symbol: "chart.pie")
        }
      }
      Text(
        L10n.text(
          "Показатели рассчитаны только по записанным интервалам. Пропуски данных не считаются сном или бодрствованием.",
          locale: locale)
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  private var history: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.text("Ваш ритм сна", locale: locale)).font(.headline)
      Picker(L10n.text("Период анализа сна", locale: locale), selection: $days) {
        Text(L10n.text("Неделя", locale: locale)).tag(7)
        Text(L10n.text("Месяц", locale: locale)).tag(30)
      }.pickerStyle(.segmented).accessibilityIdentifier("sleepTrendPeriod")
      if let average = trend.average {
        HStack(alignment: .firstTextBaseline) {
          Text(SleepDisplay.duration(average, locale: locale)).font(.title2.bold())
            .monospacedDigit()
          Text(L10n.text("в среднем", locale: locale)).font(.caption).foregroundStyle(.secondary)
          Spacer()
          Text(L10n.format("%@ ночей с данными", String(trend.recorded.count), locale: locale))
            .font(.caption).foregroundStyle(.secondary)
        }
        Chart {
          ForEach(trend.nights) { item in
            if let duration = item.asleep {
              BarMark(
                x: .value(L10n.text("Дата", locale: locale), item.day, unit: .day),
                y: .value(L10n.text("Часы", locale: locale), duration / 3600)
              ).cornerRadius(5)
                .foregroundStyle(
                  theme.accent.opacity(
                    calendar.isDate(item.day, inSameDayAs: focusedDay ?? day) ? 1 : 0.35))
            }
          }
          RuleMark(y: .value(L10n.text("Среднее", locale: locale), average / 3600)).foregroundStyle(
            theme.accent.opacity(0.6)
          ).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXSelection(value: $chartDate)
        .chartXScale(domain: trendDomain)
        .chartXAxis {
          AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in
            AxisValueLabel(format: .dateTime.day())
          }
        }
        .frame(height: 155).accessibilityIdentifier("sleepTrendChart")
        Text(
          L10n.text(
            "Выберите столбик, чтобы посмотреть эту ночь. Пустые дни не участвуют в среднем.",
            locale: locale)
        ).font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 16) {
          if let shortest = trend.shortest {
            metric(
              "Самая короткая ночь", value: SleepDisplay.duration(shortest, locale: locale),
              symbol: "arrow.down")
          }
          if let longest = trend.longest {
            metric(
              "Самая длинная ночь", value: SleepDisplay.duration(longest, locale: locale),
              symbol: "arrow.up")
          }
        }
      } else {
        Text(L10n.text("Недостаточно данных для анализа периода.", locale: locale)).foregroundStyle(
          .secondary)
      }
    }
  }
  private func timeMetric(_ title: String, date: Date, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(L10n.text(title, locale: locale), systemImage: symbol).font(.caption).foregroundStyle(
        .secondary)
      Text(date, style: .time).font(.title3.bold()).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func metric(_ title: String, value: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(L10n.text(title, locale: locale), systemImage: symbol).font(.caption).foregroundStyle(
        .secondary
      ).fixedSize(horizontal: false, vertical: true)
      Text(value).font(.headline).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
  private func focus(_ stage: SleepStage, in night: SleepNight) {
    selectedStage = stage
    focusedPeriod = night.periods.first { $0.stage == stage }
  }
  private func resetPhase() {
    selectedTime = nil
    focusedPeriod = nil
    selectedStage = nil
  }
}

private enum SleepDisplay {
  static let recordedStages: [SleepStage] = [.rem, .core, .deep, .unspecified, .awake]
  static func duration(_ value: TimeInterval, locale: Locale) -> String {
    Duration.seconds(value).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
  }
  static func title(_ stage: SleepStage, locale: Locale) -> String {
    let title: String
    switch stage {
    case .inBed: title = "В постели"
    case .awake: title = "Бодрствование"
    case .core: title = "Базовый сон"
    case .deep: title = "Глубокий сон"
    case .rem: title = "Быстрый сон (REM)"
    case .unspecified: title = "Сон без уточнения фазы"
    }
    return L10n.text(title, locale: locale)
  }
  static func color(_ stage: SleepStage) -> Color {
    switch stage {
    case .inBed: .gray
    case .awake: .orange
    case .core: .blue
    case .deep: .indigo
    case .rem: .purple
    case .unspecified: .secondary
    }
  }
  static func chartTitle(_ stage: SleepStage, locale: Locale) -> String {
    let title: String
    switch stage {
    case .core: title = "Базовый"
    case .deep: title = "Глубокий"
    case .rem: title = "REM"
    case .unspecified: title = "Не уточнён"
    default: return self.title(stage, locale: locale)
    }
    return L10n.text(title, locale: locale)
  }
}
