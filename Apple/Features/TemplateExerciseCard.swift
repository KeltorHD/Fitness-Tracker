import FitnessTrackerCore
import SwiftUI

/// One exercise is one card. The header, technique and removal are separate accessible actions.
struct TemplateExerciseCard: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var typeSize
  let item: TemplateExercise
  let index: Int
  let onTechnique: () -> Void
  var onRemove: (() -> Void)? = nil
  var onMoveUp: (() -> Void)? = nil
  var onMoveDown: (() -> Void)? = nil

  private var entry: ExerciseLibraryEntry? {
    ExerciseLibrary.entry(
      for: item.exercise.id,
      language: AppLanguage.system.resolved(preferredLanguages: [locale.identifier]))
  }

  private var name: String { entry?.name ?? item.exercise.name }

  private var summary: String {
    L10n.countText(item.setCount, kind: "set", locale: locale)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.format("Упражнение %@", String(index + 1), locale: locale))
            .font(.caption).foregroundStyle(.secondary)
          if item.supersetID != nil {
            Label(L10n.text("Суперсет", locale: locale), systemImage: "link")
              .font(.caption.weight(.semibold)).foregroundStyle(colorTheme.accent)
          }
          Text(name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !typeSize.isAccessibilitySize {
          WorkoutExerciseThumbnail(exercise: item.exercise)
        }
        if let onRemove {
          Button(role: .destructive, action: onRemove) {
            Image(systemName: "minus.circle.fill").font(.title3)
              .symbolRenderingMode(.hierarchical)
              .frame(width: 44, height: 44).contentShape(.circle)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(L10n.format("Убрать упражнение: %@", name, locale: locale))
          .accessibilityIdentifier("removeTemplateExercise_\(item.id)")
        }
        if onMoveUp != nil || onMoveDown != nil {
          Menu {
            if let onMoveUp {
              Button(
                L10n.text("Переместить выше", locale: locale), systemImage: "arrow.up",
                action: onMoveUp
              )
              .accessibilityIdentifier("moveTemplateExerciseUp_\(item.id)")
            }
            if let onMoveDown {
              Button(
                L10n.text("Переместить ниже", locale: locale), systemImage: "arrow.down",
                action: onMoveDown
              )
              .accessibilityIdentifier("moveTemplateExerciseDown_\(item.id)")
            }
          } label: {
            Image(systemName: "arrow.up.arrow.down")
              .frame(width: 44, height: 44).contentShape(.rect)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(L10n.text("Изменить порядок упражнений", locale: locale))
          .accessibilityIdentifier("reorderTemplateExercise_\(item.id)")
        }
      }.padding(FitTheme.cardPadding)
      Divider().padding(.horizontal, FitTheme.cardPadding)
      VStack(alignment: .leading, spacing: 8) {
        if let entry {
          Text(entry.primaryMuscles.joined(separator: ", "))
            .font(.subheadline).foregroundStyle(.secondary)
          Text(L10n.text(entry.equipment.title, locale: locale))
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(item.exercise.muscle.title).font(.subheadline).foregroundStyle(.secondary)
        }
        Text(summary).font(.subheadline).foregroundStyle(.primary)
        Button(action: onTechnique) {
          HStack(spacing: 8) {
            Label(L10n.text("Техника выполнения", locale: locale), systemImage: "info.circle")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
          }
          .foregroundStyle(colorTheme.accent)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("templateExerciseTechnique_\(item.id)")
      }.padding(FitTheme.cardPadding)
    }
    .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.exerciseCardRadius))
    .themeGlow(in: RoundedRectangle(cornerRadius: FitTheme.exerciseCardRadius))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("templateExerciseCard_\(item.id)")
  }
}
