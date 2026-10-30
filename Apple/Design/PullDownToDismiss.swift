import SwiftUI

extension View {
  /// Apply to the screen's vertical ScrollView, so scrolling back to the top remains available.
  func pullDownToDismiss() -> some View {
    modifier(PullDownToDismissModifier())
  }
}

private struct PullDownToDismissModifier: ViewModifier {
  @Environment(\.dismiss) private var dismiss

  func body(content: Content) -> some View {
    content
      .environment(\.refresh, nil)
      .scrollBounceBehavior(.always, axes: .vertical)
      .onScrollPhaseChange { oldPhase, newPhase, context in
        guard oldPhase == .interacting, newPhase != .interacting else { return }
        // Insets account for the navigation bar and safe area. Require an intentional pull
        // beyond the top, rather than dismissing when the user merely scrolls toward it.
        let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top
        if offset < -60 { dismiss() }
      }
  }
}
