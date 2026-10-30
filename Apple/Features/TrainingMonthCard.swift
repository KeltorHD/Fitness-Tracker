import FitnessTrackerCore
import SwiftUI

struct TrainingMonthPager: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @GestureState private var translation: CGSize = .zero
  @State private var width: CGFloat = 0
  @State private var settlingOffset: CGFloat = 0
  @State private var isSettling = false
  let pages: [TrainingMonthPage]
  let move: (Int) -> Void

  var body: some View {
    ZStack(alignment: .top) {
      ForEach(pages) { page in
        TrainingMonthCard(date: page.date, summary: page.summary)
          .offset(x: CGFloat(page.offset) * width + visibleOffset)
          .opacity(page.offset == 0 || width > 0 ? 1 : 0)
          .accessibilityHidden(page.offset != 0)
          .allowsHitTesting(page.offset == 0)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .clipped()
    .contentShape(.rect)
    .simultaneousGesture(
      DragGesture(minimumDistance: 20)
        .updating($translation) { value, state, transaction in
          guard !isSettling else { return }
          transaction.animation = nil
          state = value.translation
        }
        .onEnded { value in settle(value.translation) }
    )
  }

  private var visibleOffset: CGFloat {
    if reduceMotion { return 0 }
    return isSettling ? settlingOffset : horizontalOffset(translation)
  }

  private func horizontalOffset(_ translation: CGSize) -> CGFloat {
    guard abs(translation.width) > abs(translation.height) * 1.5 else { return 0 }
    return min(width, max(-width, translation.width))
  }

  private func settle(_ translation: CGSize) {
    guard !isSettling, width > 0 else { return }
    let offset = horizontalOffset(translation)
    let direction = abs(offset) >= 50 ? (offset < 0 ? 1 : -1) : 0
    if reduceMotion {
      if direction != 0 { move(direction) }
      return
    }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      settlingOffset = offset
      isSettling = true
    }
    withAnimation(.snappy(duration: 0.25), completionCriteria: .removed) {
      settlingOffset = -CGFloat(direction) * width
    } completion: {
      withTransaction(transaction) {
        if direction != 0 { move(direction) }
        settlingOffset = 0
        isSettling = false
      }
    }
  }
}

struct TrainingMonthCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  let date: Date
  let summary: TrainingMonthSummary

  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 20) {
          calendar
          Divider()
          HStack {
            total
            Spacer()
            ring
          }
        }
      } else {
        HStack(alignment: .top, spacing: 24) {
          calendar.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 16) {
            total
            Divider()
            ring.padding(.top, 32)
          }.frame(width: 64)
        }
        .overlay(alignment: .trailing) {
          Rectangle().fill(FitTheme.separator).frame(width: 1).padding(.trailing, 76)
        }
      }
    }
    .resultsCard(padding: 16).accessibilityIdentifier("trainingMonthCard")
  }

  private var calendar: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(date.formatted(.dateTime.locale(locale).month(.wide)).localizedCapitalized)
        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        .accessibilityIdentifier("trainingMonthTitle")
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7), spacing: 4
      ) {
        ForEach(summary.days) { day in
          // The shape owns the cell size. Overlay text cannot shrink the circle or the grid row.
          Circle().fill(.clear).aspectRatio(1, contentMode: .fit)
            .overlay {
              if day.hasWorkout {
                Circle().fill(FitTheme.header)
              } else if day.isInMonth {
                Circle().stroke(FitTheme.separator, lineWidth: 1)
              }
            }
            .overlay {
              Text(day.date, format: .dateTime.day())
                .font(.subheadline).fontWeight(day.hasWorkout ? .semibold : .regular)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(
                  day.hasWorkout
                    ? Color.white : day.isInMonth ? Color.primary : Color.secondary.opacity(0.6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(day.date.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide).year()))\(day.hasWorkout ? ", " + L10n.text("calendar.trained", locale: locale) : "")"
            )
        }
      }
    }.padding(.bottom, 24)
  }
  private var total: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("Всего", locale: locale)).font(.subheadline).foregroundStyle(.secondary)
      Text("\(summary.workoutCount)").font(.largeTitle.weight(.medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.6)
    }.accessibilityElement(children: .combine)
  }
  private var ring: some View {
    ZStack {
      Circle().stroke(FitTheme.separator, lineWidth: 12)
      Circle().trim(from: 0, to: summary.trainingDayFraction)
        .stroke(FitTheme.header, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }.frame(width: 52, height: 52).padding(6)
      .accessibilityLabel(L10n.text("Дни с тренировками в выбранном месяце", locale: locale))
      .accessibilityValue(
        summary.trainingDayFraction.formatted(.percent.locale(locale).precision(.fractionLength(0)))
      )
  }
}
