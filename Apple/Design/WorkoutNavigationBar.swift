import SwiftUI

/// The center action shares the glass outline but does not change the selected tab.
struct WorkoutNavigationBar: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 18
  @Binding var selection: Int
  let hasActiveWorkout: Bool
  let onStart: () -> Void

  var body: some View {
    GlassEffectContainer {
      HStack(alignment: .bottom, spacing: 0) {
        tab("Дневник", symbol: "book", value: 0)
        tab("Шаблоны", symbol: "dumbbell", value: 1)
        Button(action: onStart) {
          VStack(spacing: 4) {
            Image(systemName: "play.fill")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 58, height: 58)
              .background(FitTheme.accent, in: .circle)
              .glassEffect(.regular.tint(FitTheme.accent).interactive(), in: .circle)
              .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
              .accessibilityHidden(true)
            if !dynamicTypeSize.isAccessibilitySize {
              Text(L10n.text(hasActiveWorkout ? "Продолжить" : "Начать", locale: locale))
                .font(.caption2).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(height: labelHeight)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          L10n.text(
            hasActiveWorkout ? "Продолжить тренировку" : "Начать тренировку", locale: locale)
        )
        .accessibilityIdentifier("workoutStartAction")
        tab("Результаты", symbol: "chart.bar.xaxis", value: 2)
        tab("Настройки", symbol: "gearshape", value: 3)
      }
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
  }

  private func tab(_ title: String, symbol: String, value: Int) -> some View {
    Button {
      selection = value
    } label: {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 21, weight: selection == value ? .semibold : .regular))
          .frame(height: 24)
          .accessibilityHidden(true)
        if !dynamicTypeSize.isAccessibilitySize {
          Text(L10n.text(title, locale: locale))
            .font(.caption2).lineLimit(2).minimumScaleFactor(0.75)
            .frame(height: labelHeight)
        }
      }
      .foregroundStyle(selection == value ? Color.primary : FitTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 62)
      .background {
        if selection == value {
          Capsule().fill(Color.primary.opacity(0.07))
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L10n.text(title, locale: locale))
    .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    .accessibilityIdentifier("navigationTab_\(value)")
  }
}

/// A rounded floating bar with a shallow rise around the play button.
private struct WorkoutNavigationShape: Shape {
  func path(in rect: CGRect) -> Path {
    let top = rect.minY + 16
    let radius = min(32, (rect.height - 16) / 2)
    let center = rect.midX
    let shoulder = min(52, max(0, rect.width / 2 - radius))
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
