import FitnessTrackerCore
import SwiftUI

enum WorkoutStartSelection {
  case empty
  case template(WorkoutTemplate)
}

struct WorkoutStartView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  let onSelect: (WorkoutStartSelection) -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          Button {
            onSelect(.empty)
          } label: {
            HStack(spacing: 14) {
              Image(systemName: "play.circle")
                .font(.largeTitle).foregroundStyle(FitTheme.accent)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Без шаблона", locale: locale)).font(.headline)
                Text(L10n.text("Добавляйте упражнения по ходу", locale: locale))
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.accent.opacity(0.08), in: .rect(cornerRadius: FitTheme.radius))
            .contentShape(.rect)
          }
          .buttonStyle(.plain).accessibilityIdentifier("startWorkoutWithoutTemplate")

          Text(L10n.text("Мои шаблоны", locale: locale))
            .font(.headline).foregroundStyle(.secondary).padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
          if store.templates.isEmpty {
            Text(
              L10n.text(
                "Шаблонов пока нет. Их можно создать в разделе «Каталог».", locale: locale)
            )
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityIdentifier("workoutStartEmptyTemplates")
          }
          ForEach(store.templates) { template in
            Button {
              onSelect(.template(template))
            } label: {
              HStack(spacing: 14) {
                Image(systemName: "dumbbell").foregroundStyle(FitTheme.accent)
                  .accessibilityHidden(true)
                Text(template.name).font(.headline)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                  .accessibilityHidden(true)
              }
              .padding(18).frame(minHeight: 64)
              .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
              .contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityIdentifier("startWorkoutTemplate_\(template.id)")
          }
        }
        .padding(16)
      }
      .background(FitTheme.paper)
      .navigationTitle(L10n.text("Начать тренировку", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale), systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly).accessibilityIdentifier("closeWorkoutStart")
        }
      }
    }
  }
}
