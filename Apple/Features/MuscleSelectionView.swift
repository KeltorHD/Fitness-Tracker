import FitnessTrackerCore
import SwiftUI

/// Shared by template preferences and the exercise catalog so both use the same selection rules.
struct MuscleSelectionView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: ExerciseMuscleSelection
  var showsDoneButton = false
  @State private var expandedGroups: Set<MuscleGroup> = []

  private var groups: [MuscleGroup] {
    MuscleGroup.allCases.filter {
      !ExerciseMuscle.inGroup($0).isEmpty || selection.groups.contains($0)
    }
  }

  var body: some View {
    List {
      Section {
        Button(L10n.text("Сбросить выбор", locale: locale)) {
          selection = ExerciseMuscleSelection()
        }
        .disabled(selection.isEmpty)
        .accessibilityIdentifier("clearMuscleSelection")
      } footer: {
        Text(
          L10n.text(
            "Отметьте группу целиком или раскройте её и выберите отдельные мышцы.", locale: locale))
      }
      Section {
        ForEach(groups, id: \.self) { group in
          let children = ExerciseMuscle.inGroup(group)
          if children.isEmpty {
            groupLabel(group)
          } else {
            DisclosureGroup(
              isExpanded: Binding(
                get: { expandedGroups.contains(group) },
                set: { expanded in
                  if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                })
            ) {
              ForEach(children, id: \.self) { muscle in
                Toggle(
                  L10n.text(muscle.title, locale: locale),
                  isOn: Binding(
                    get: { selection.contains(muscle) },
                    set: { selection.set(muscle, selected: $0) })
                )
                .accessibilityIdentifier("muscle_\(muscle.rawValue)")
              }
            } label: {
              groupLabel(group)
            }
            .accessibilityIdentifier("expandMuscleGroup_\(group.rawValue)")
          }
        }
      } footer: {
        Text(L10n.text("Фильтр учитывает основные мышцы упражнения.", locale: locale))
      }
    }
    .tint(colorTheme.accent)
    .navigationTitle(L10n.text("Группы и мышцы", locale: locale))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsDoneButton {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Готово", locale: locale)) { dismiss() }
        }
      }
    }
    .onAppear {
      expandedGroups.formUnion(groups.filter { selection.state(of: $0) != .none })
    }
  }

  private func groupLabel(_ group: MuscleGroup) -> some View {
    let state = selection.state(of: group)
    return HStack(spacing: 8) {
      Button {
        selection.set(group, selected: state != .all)
      } label: {
        Image(
          systemName: state == .all
            ? "checkmark.square.fill" : state == .partial ? "minus.square.fill" : "square"
        )
        .font(.title3)
        .foregroundStyle(state == .none ? FitTheme.muted : colorTheme.accent)
        .frame(width: 44, height: 44).contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(
        L10n.format(
          state == .all ? "Снять выбор группы: %@" : "Выбрать всю группу: %@",
          MuscleSelectionText.groupTitle(group, locale: locale), locale: locale)
      )
      .accessibilityValue(
        state == .partial
          ? L10n.text("Частично выбрано", locale: locale)
          : state == .all ? L10n.text("Выбрано", locale: locale) : ""
      )
      .accessibilityAddTraits(state == .all ? [.isSelected] : [])
      .accessibilityIdentifier("muscleGroup_\(group.rawValue)")
      Text(MuscleSelectionText.groupTitle(group, locale: locale))
        .font(.headline).foregroundStyle(.primary)
    }
  }
}

enum MuscleSelectionText {
  static func groupTitle(_ group: MuscleGroup, locale: Locale) -> String {
    L10n.text(group == .shoulders ? "Плечи и шея" : group.title, locale: locale)
  }

  static func summary(_ selection: ExerciseMuscleSelection, locale: Locale) -> String {
    guard !selection.isEmpty else { return L10n.text("Все мышцы", locale: locale) }
    let groups = MuscleGroup.allCases.filter { selection.groups.contains($0) }
      .map { groupTitle($0, locale: locale) }
    let muscles = ExerciseMuscle.allCases.filter { selection.muscles.contains($0) }
      .map { L10n.text($0.title, locale: locale) }
    return (groups + muscles).joined(separator: ", ")
  }

  static func compactSummary(_ selection: ExerciseMuscleSelection, locale: Locale) -> String {
    let count = selection.groups.count + selection.muscles.count
    return count > 1
      ? L10n.format("Мышцы: %@", String(count), locale: locale)
      : summary(selection, locale: locale)
  }
}
