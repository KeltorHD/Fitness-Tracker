import SwiftUI

/// Visual constants measured from the supplied reference screens; system colors adapt to Dark Mode.
enum FitTheme {
  static let accent = Color(red: 1, green: 0.31, blue: 0.20)
  static let paper = Color(.systemBackground)
  static let card = Color(.secondarySystemBackground)
  static let grouped = Color(.systemGroupedBackground)
  static let muted = Color(.secondaryLabel)
  static let header = LinearGradient(
    colors: [Color(red: 1, green: 0.36, blue: 0.22), Color(red: 1, green: 0.18, blue: 0.10)],
    startPoint: .top, endPoint: .bottom)
  static let radius: CGFloat = 25
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

struct SummaryMetric: View {
  let title: String
  let value: String
  var body: some View {
    VStack(spacing: 4) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
    }.frame(maxWidth: .infinity).padding(.vertical, 13)
      .background(FitTheme.card, in: .rect(cornerRadius: 16))
      .accessibilityElement(children: .combine)
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
  let title: String
  var date: Date? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Group {
        if let date {
          Text(date, format: .dateTime.weekday(.wide).hour().minute())
        } else {
          Text("Шаблон тренировки")
        }
      }.font(.subheadline).textCase(.uppercase).frame(maxWidth: .infinity)
      Rectangle().fill(.white.opacity(0.25)).frame(height: 0.5)
      Label(title, systemImage: "figure.strengthtraining.traditional")
        .font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
    }.foregroundStyle(.white).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
      .background(FitTheme.header)
  }
}
