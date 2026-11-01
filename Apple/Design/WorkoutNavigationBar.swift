import SwiftUI

/// The center action shares the glass outline but does not change the selected tab.
struct WorkoutNavigationBar: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 18
  @Namespace private var selectionGlass
  @GestureState private var drag: NavigationSelectionDrag?
  @State private var tabFrames: [Int: CGRect] = [:]
  @Binding var selection: Int
  let hasActiveWorkout: Bool
  let onStart: () -> Void

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(alignment: .bottom, spacing: 0) {
        tab("Дневник", symbol: "book", value: 0)
        tab("Шаблоны", symbol: "dumbbell", value: 1)
        Button(action: onStart) {
          VStack(spacing: 4) {
            Image(systemName: "play.fill")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(FitTheme.accentForeground)
              .frame(width: 52, height: 52)
              .glassEffect(.regular.tint(FitTheme.accent).interactive(), in: .circle)
              .glassEffectID("workoutStart", in: selectionGlass)
              .accessibilityHidden(true)
            if !dynamicTypeSize.isAccessibilitySize {
              Text(L10n.text(hasActiveWorkout ? "Продолжить" : "Начать", locale: locale))
                .font(.caption2).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(height: labelHeight)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 62, alignment: .top)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          L10n.text(
            hasActiveWorkout ? "Продолжить тренировку" : "Начать тренировку", locale: locale)
        )
        .accessibilityIdentifier("workoutStartAction")
        .zIndex(1)
        tab("Результаты", symbol: "chart.bar.xaxis", value: 2)
        tab("Настройки", symbol: "gearshape", value: 3)
      }
      .coordinateSpace(name: "workoutNavigationBar")
      .padding(.horizontal, 8)
      .padding(.top, 4)
      .padding(.bottom, 8)
      .background {
        if reduceTransparency {
          WorkoutNavigationShape().fill(FitTheme.paper)
        }
      }
      .glassEffect(.regular, in: WorkoutNavigationShape())
      .overlay {
        if colorSchemeContrast == .increased {
          WorkoutNavigationShape().stroke(FitTheme.muted, lineWidth: 1)
            .allowsHitTesting(false)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selection)
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: drag == nil)
    .transaction { transaction in
      if reduceMotion { transaction.animation = nil }
    }
  }

  private func tab(_ title: String, symbol: String, value: Int) -> some View {
    Button {
      select(value)
    } label: {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 21, weight: highlightedTab == value ? .semibold : .regular))
          .frame(height: 24)
          .accessibilityHidden(true)
        if !dynamicTypeSize.isAccessibilitySize {
          Text(L10n.text(title, locale: locale))
            .font(.caption2).lineLimit(2).minimumScaleFactor(0.75)
            .frame(height: labelHeight)
        }
      }
      .foregroundStyle(highlightedTab == value ? Color.primary : FitTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 62)
      .background {
        if (drag?.source ?? selection) == value {
          Capsule()
            .fill(reduceTransparency ? FitTheme.card : Color.clear)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("selectedTab", in: selectionGlass)
            .glassEffectTransition(.matchedGeometry)
            .offset(x: selectionOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L10n.text(title, locale: locale))
    .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    .accessibilityIdentifier("navigationTab_\(value)")
    .onGeometryChange(for: CGRect.self) { geometry in
      geometry.frame(in: .named("workoutNavigationBar"))
    } action: { frame in
      tabFrames[value] = frame
    }
    .highPriorityGesture(selectionDrag)
  }

  private var highlightedTab: Int {
    drag?.target ?? drag?.source ?? selection
  }

  private var selectionOffset: CGFloat {
    guard let drag, let sourceFrame = tabFrames[drag.source],
      let left = tabFrames.values.map(\.midX).min(),
      let right = tabFrames.values.map(\.midX).max()
    else { return 0 }
    return min(max(sourceFrame.midX + drag.translation, left), right) - sourceFrame.midX
  }

  private var selectionDrag: some Gesture {
    DragGesture(minimumDistance: 10, coordinateSpace: .named("workoutNavigationBar"))
      .updating($drag) { value, state, transaction in
        guard let source = tabFrames.first(where: { $0.value.contains(value.startLocation) })?.key
        else { return }
        // Track the finger directly. The release animates to the destination tab.
        transaction.animation = nil
        state = NavigationSelectionDrag(
          source: source,
          target: tabFrames.first(where: { $0.value.contains(value.location) })?.key,
          translation: value.translation.width)
      }
      .onEnded { value in
        guard tabFrames.values.contains(where: { $0.contains(value.startLocation) }),
          let target = tabFrames.first(where: { $0.value.contains(value.location) })?.key
        else { return }
        select(target)
      }
  }

  private func select(_ value: Int) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
      selection = value
    }
  }
}

/// GestureState clears the preview when a drag ends or is cancelled, without changing tabs.
private struct NavigationSelectionDrag {
  let source: Int
  let target: Int?
  let translation: CGFloat
}

/// A rounded floating bar with a shallow rise around the play button.
private struct WorkoutNavigationShape: Shape {
  func path(in rect: CGRect) -> Path {
    let top = rect.minY + 12
    let radius = min(32, (rect.height - 12) / 2)
    let center = rect.midX
    let shoulder = min(44, max(0, rect.width / 2 - radius))
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + radius, y: top))
    path.addLine(to: CGPoint(x: center - shoulder, y: top))
    path.addCurve(
      to: CGPoint(x: center, y: rect.minY),
      control1: CGPoint(x: center - shoulder / 2, y: top),
      control2: CGPoint(x: center - shoulder / 2, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: center + shoulder, y: top),
      control1: CGPoint(x: center + shoulder / 2, y: rect.minY),
      control2: CGPoint(x: center + shoulder / 2, y: top))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: top + radius),
      control: CGPoint(x: rect.maxX, y: top))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + radius, y: top),
      control: CGPoint(x: rect.minX, y: top))
    path.closeSubpath()
    return path
  }
}
