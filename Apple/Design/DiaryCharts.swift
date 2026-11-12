import Charts
import FitnessTrackerCore
import SwiftUI

struct DiaryDisclosureCard<Content: View>: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let title: String
  let summary: String
  let identifier: String
  @Binding var expanded: Bool
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
      } label: {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if !expanded {
              Text(summary).font(.subheadline).foregroundStyle(.secondary)
                .contentTransition(.numericText())
            }
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.down").font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary).rotationEffect(.degrees(expanded ? 180 : 0))
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
      }
      .buttonStyle(.plain).accessibilityIdentifier(identifier)
      .accessibilityValue(L10n.text(expanded ? "Развёрнуто" : "Свёрнуто", locale: locale))
      .accessibilityHint(L10n.text(expanded ? "Скрыть сводку" : "Показать сводку", locale: locale))
      if expanded { content() }
    }.fitCard().accessibilityElement(children: .contain)
  }
}

/// The complete disc, including its inner space, accepts ordinary taps for small slices.
struct DiaryRingSegment: Identifiable {
  let id: String
  let value: Double
  let color: Color
}

struct DiaryRingChart<Center: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let segments: [DiaryRingSegment]
  let selectedID: String?
  let onSelect: (String) -> Void
  @ViewBuilder let center: () -> Center
  @State private var angle: Double?

  var body: some View {
    Chart(segments) { segment in
      SectorMark(
        angle: .value("Value", segment.value), innerRadius: .ratio(0.68), angularInset: 2
      )
      .cornerRadius(4).foregroundStyle(segment.color.gradient)
      .opacity(selectedID == nil || selectedID == segment.id ? 1 : 0.28)
    }
    .chartAngleSelection(value: $angle)
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Circle().fill(.clear).contentShape(.circle)
          .onTapGesture { location in
            guard let plot = proxy.plotFrame else { return }
            let frame = geometry[plot]
            let dx = location.x - frame.midX
            let dy = location.y - frame.midY
            guard hypot(dx, dy) > 6 else { return }
            let radians = atan2(dx, -dy)
            let angle = Angle.radians(radians < 0 ? radians + 2 * .pi : radians)
            // A repeated tap must still select the slice after selection changed via its row.
            if let value = proxy.value(atAngle: angle, as: Double.self) { select(value) }
            proxy.selectAngleValue(at: angle)
          }
      }
    }
    .onChange(of: angle) { _, value in
      if let value { select(value) }
    }
    .onChange(of: selectedID) { _, value in
      if value == nil { angle = nil }
    }
    .overlay {
      if segments.allSatisfy({ $0.value == 0 }) {
        Circle().stroke(.secondary.opacity(0.12), lineWidth: 18).padding(10)
          .allowsHitTesting(false)
      }
      center().allowsHitTesting(false).accessibilityHidden(true)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedID)
    .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: segments.map(\.value))
    .accessibilityElement(children: .ignore)
    .accessibilityAdjustableAction { direction in
      let visible = segments.filter { $0.value > 0 }
      guard !visible.isEmpty else { return }
      let current = visible.firstIndex(where: { $0.id == selectedID }) ?? -1
      let next: Int
      switch direction {
      case .increment: next = (current + 1) % visible.count
      case .decrement: next = (max(0, current) + visible.count - 1) % visible.count
      @unknown default: return
      }
      onSelect(visible[next].id)
    }
  }

  private func select(_ value: Double) {
    guard let index = DiaryRingSelection.index(at: value, weights: segments.map(\.value)) else {
      return
    }
    onSelect(segments[index].id)
  }
}

struct DiaryProgressRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let progress: Double
  let color: Color
  var lineWidth: CGFloat = 12
  @State private var appeared = false
  private var fill: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }

  var body: some View {
    ZStack {
      Circle().stroke(color.opacity(0.13), lineWidth: lineWidth)
      Circle().trim(from: 0, to: appeared ? fill : 0)
        .stroke(
          AngularGradient(
            colors: [color.opacity(0.65), color, color], center: .center,
            startAngle: .degrees(0), endAngle: .degrees(360)),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ).rotationEffect(.degrees(-90))
    }
    .padding(lineWidth / 2)
    .onAppear { appeared = true }
    .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: appeared)
    .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: fill)
    .accessibilityHidden(true)
  }
}
