import SwiftUI

/// Preserve Liquid Glass on modern watches and use native bordered controls on watchOS 10–11.
private struct WatchButtonAppearance: ViewModifier {
  let prominent: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if #available(watchOS 26.0, *) {
      if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
    } else {
      if prominent {
        content.buttonStyle(.borderedProminent)
      } else {
        content.buttonStyle(.bordered)
      }
    }
  }
}

extension View {
  func watchButtonStyle(prominent: Bool = true) -> some View {
    modifier(WatchButtonAppearance(prominent: prominent))
  }
}
