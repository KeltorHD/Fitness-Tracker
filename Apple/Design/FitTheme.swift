import SwiftUI

/// Shared neutral journal surfaces. Accent colors come from the inherited FitnessColorTheme.
enum FitTheme {
  static let accentForeground = Color("AccentForeground")
  static let paper = Color(.systemBackground)
  static let card = Color(.secondarySystemBackground)
  static let grouped = Color(.systemGroupedBackground)
  static let muted = Color(.secondaryLabel)
  static let radius: CGFloat = 25
  static let cardPadding: CGFloat = 16
  static let resultsRadius: CGFloat = 28
  static let resultsPadding: CGFloat = 20
  static let exerciseCardRadius: CGFloat = 28
  static let resultsSurface = Color("ResultsSurface")
  static let separator = Color(.separator).opacity(0.5)
}

extension View {
  func cardListRow() -> some View {
    listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
      .listRowSeparator(.hidden).listRowBackground(Color.clear)
  }

  func resultsCard(padding: CGFloat = FitTheme.resultsPadding) -> some View {
    self.padding(padding)
      .background(FitTheme.resultsSurface, in: .rect(cornerRadius: FitTheme.resultsRadius))
  }
  func fitCard() -> some View {
    padding(FitTheme.cardPadding)
      .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
  }
}

struct SummaryChip: View {
  let text: String
  var symbol: String? = nil
  var body: some View {
    HStack(spacing: 6) {
      if let symbol { Image(systemName: symbol) }
      Text(text)
    }.font(.subheadline).padding(.horizontal, 14).padding(.vertical, 10)
      .background(FitTheme.card, in: .capsule).accessibilityElement(children: .combine)
  }
}

struct WorkoutSummaryCard: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let metrics: [(title: String, value: String)]

  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
            if index > 0 { Divider() }
            metricView(metric)
          }
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
            metricView(metric).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
  }

  private func metricView(_ metric: (title: String, value: String)) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(metric.title).font(.caption).foregroundStyle(.secondary)
      Text(metric.value).font(.headline).monospacedDigit().foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }.accessibilityElement(children: .combine)
  }
}

struct SectionHeading: View {
  let title: String
  let symbol: String
  var body: some View {
    Label(title, systemImage: symbol).font(.title2.bold()).foregroundStyle(.primary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WorkoutHero: View {
  @Environment(\.locale) private var locale
  let title: String
  var date: Date? = nil
  var showsDate = true
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showsDate {
        Group {
          if let date {
            Text(date, format: .dateTime.weekday(.wide).hour().minute())
          } else {
            Text(L10n.text("Шаблон тренировки", locale: locale))
          }
        }.font(.subheadline).foregroundStyle(.secondary)
      }
      Text(title).font(.title.bold()).foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
  }
}
