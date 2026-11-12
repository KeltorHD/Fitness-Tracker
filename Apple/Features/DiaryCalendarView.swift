import FitnessTrackerCore
import SwiftUI

struct DiaryCalendarView: View {
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.fitnessColorTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var phase
  @Binding var date: Date
  let workouts: [Workout]
  @State private var expanded = false
  @State private var page: DiaryCalendarPage?
  @GestureState private var translation: CGSize = .zero
  private var mode: DiaryCalendarMode { expanded ? .month : .week }

  var body: some View {
    VStack(spacing: 8) {
      header
      if let current = page {
        HStack(spacing: 2) {
          ForEach(Array(current.days.prefix(7)), id: \.date) { item in
            Text(item.date, format: .dateTime.weekday(.narrow))
              .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
        }.accessibilityHidden(true)
        dayGrid(current)
          .offset(x: reduceMotion ? 0 : horizontalOffset(translation) * 0.12)
          .frame(height: expanded ? 274 : 44, alignment: .top)
          .clipped().contentShape(.rect)
          .highPriorityGesture(
            DragGesture(minimumDistance: 20)
              .updating($translation) { value, state, transaction in
                transaction.animation = nil
                state = value.translation
              }
              .onEnded { settle($0.translation) }
          )
          .accessibilityElement(children: .contain).accessibilityIdentifier("diaryCalendarGrid")
      }
    }
    .padding(12).background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
    .themeGlow(in: RoundedRectangle(cornerRadius: FitTheme.radius))
    .accessibilityElement(children: .contain).accessibilityIdentifier("diaryCalendar")
    .onChange(of: workouts, initial: true) { refresh() }
    .onChange(of: date) { refresh() }
    .onChange(of: calendar) { refresh() }
    .onChange(of: phase) { if phase == .active { refresh() } }
  }

  private var header: some View {
    HStack(spacing: 6) {
      Button {
        move(-1)
      } label: {
        Image(systemName: "chevron.left").frame(width: 36, height: 44)
      }
      .accessibilityLabel(
        L10n.text(expanded ? "Предыдущий месяц" : "Предыдущая неделя", locale: locale)
      )
      .accessibilityIdentifier("previousDiaryPeriod")
      Button {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
          expanded.toggle()
          refresh()
        }
      } label: {
        HStack(spacing: 6) {
          VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.month(.wide).year()).font(.headline)
              .accessibilityIdentifier("diaryCalendarMonth")
            Text(date, format: .dateTime.weekday(.wide).day()).font(.caption)
              .foregroundStyle(.secondary).accessibilityIdentifier("diarySelectedDate")
          }
          Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            .rotationEffect(.degrees(expanded ? 180 : 0))
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
      }
      .accessibilityIdentifier("expandDiaryCalendar")
      .accessibilityValue(L10n.text(expanded ? "Месяц" : "Неделя", locale: locale))
      .accessibilityHint(
        L10n.text(expanded ? "Свернуть календарь" : "Развернуть календарь", locale: locale))
      if !calendar.isDateInToday(date) {
        Button(L10n.text("Сегодня", locale: locale)) { date = .now }
          .font(.caption.weight(.semibold)).frame(minHeight: 44)
          .accessibilityIdentifier("diaryToday")
      }
      Button {
        move(1)
      } label: {
        Image(systemName: "chevron.right").frame(width: 36, height: 44)
      }
      .accessibilityLabel(
        L10n.text(expanded ? "Следующий месяц" : "Следующая неделя", locale: locale)
      )
      .accessibilityIdentifier("nextDiaryPeriod")
    }.buttonStyle(.plain).foregroundStyle(theme.accent)
  }

  private func dayGrid(_ page: DiaryCalendarPage) -> some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7), spacing: 2
    ) {
      ForEach(Array(page.days.enumerated()), id: \.offset) { _, item in
        let selected = calendar.isDate(item.date, inSameDayAs: date)
        Button {
          date = item.date
        } label: {
          VStack(spacing: 2) {
            Text(item.date, format: .dateTime.day()).contentTransition(.numericText()).font(
              .subheadline.weight(selected ? .bold : .medium)
            )
            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 32, height: 32)
            .foregroundStyle(selected ? FitTheme.accentForeground : .primary)
            .background(selected ? theme.accent : .clear, in: .circle)
            .overlay {
              if calendar.isDateInToday(item.date), !selected {
                Circle().stroke(theme.accent, lineWidth: 1)
              }
            }
            Circle().fill(item.hasWorkout ? theme.accent : .clear).frame(width: 4, height: 4)
          }.opacity(expanded && !item.isInMonth ? 0.4 : 1)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain)
          .accessibilityLabel(
            item.date.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide).year())
          )
          .accessibilityHint(item.hasWorkout ? L10n.text("calendar.trained", locale: locale) : "")
          .accessibilityAddTraits(selected ? [.isSelected] : [])
          .accessibilityIdentifier(
            selected
              ? "selectedDiaryCalendarDay" : "diaryCalendarDay_\(item.date.timeIntervalSince1970)")
      }
    }
  }

  private func refresh(for selected: Date? = nil) {
    page = DiaryCalendar.page(
      containing: selected ?? date, mode: mode, workouts: workouts, now: .now, calendar: calendar)
  }
  private func move(_ direction: Int) {
    guard let next = DiaryCalendar.shifted(date, by: direction, mode: mode, calendar: calendar)
    else { return }
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
      date = next
      refresh(for: next)
    }
  }
  private func horizontalOffset(_ value: CGSize) -> CGFloat {
    guard abs(value.width) > abs(value.height) * 1.5 else { return 0 }
    return min(180, max(-180, value.width))
  }
  private func settle(_ value: CGSize) {
    let offset = horizontalOffset(value)
    guard abs(offset) >= 48 else { return }
    move(offset < 0 ? 1 : -1)
  }
}
