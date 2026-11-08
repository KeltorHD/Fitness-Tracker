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
  @State private var expandedMuscles: Set<ExerciseMuscle> = []

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
          groupLabel(group)
          if expandedGroups.contains(group) {
            ForEach(children, id: \.self) { muscle in
              muscleRow(muscle)
            }
          }
        }
      } footer: {
        Text(L10n.text("Фильтр учитывает основные мышцы и отмеченные области.", locale: locale))
        Text(
          L10n.text(
            "Области груди и пресса — части одной мышцы, а не отдельные мышцы. Фильтр показывает упражнения с отмеченной областью; полная изоляция не подразумевается.",
            locale: locale))
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
      expandedMuscles.formUnion(
        ExerciseMuscle.allCases.filter { selection.state(ofMuscle: $0) == .partial })
    }
  }

  @ViewBuilder private func muscleRow(_ muscle: ExerciseMuscle) -> some View {
    let regions = ExerciseMuscleRegion.inMuscle(muscle)
    VStack(alignment: .leading, spacing: 4) {
      let state = selection.state(ofMuscle: muscle)
      selectionToggle(
        muscle.title, identifier: "muscle_\(muscle.rawValue)",
        isOn: Binding(
          get: {
            regions.isEmpty ? selection.contains(muscle) : selection.state(ofMuscle: muscle) == .all
          },
          set: { selection.set(muscle, selected: $0) }),
        partiallySelected: state == .partial)
      if !regions.isEmpty {
        Button {
          if !expandedMuscles.insert(muscle).inserted { expandedMuscles.remove(muscle) }
        } label: {
          HStack {
            Text(
              L10n.format("Области: %@", L10n.text(muscle.title, locale: locale), locale: locale)
            ).font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: expandedMuscles.contains(muscle) ? "chevron.down" : "chevron.right")
              .font(.caption.weight(.semibold)).accessibilityHidden(true)
          }.frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityValue(
          L10n.text(expandedMuscles.contains(muscle) ? "Развёрнуто" : "Свёрнуто", locale: locale)
        )
        .accessibilityIdentifier("expandMuscle_\(muscle.rawValue)")
        if expandedMuscles.contains(muscle) {
          ForEach(regions, id: \.self) { region in
            selectionToggle(
              region.title, identifier: "muscleRegion_\(region.rawValue)",
              isOn: Binding(
                get: { selection.contains(region) }, set: { selection.set(region, selected: $0) }),
              accessibilityTitle: L10n.format(
                "%@: %@", L10n.text(muscle.title, locale: locale),
                L10n.text(region.title, locale: locale), locale: locale)
            )
            .padding(.leading, 24)
          }
        }
      }
    }
    .padding(.leading, 12)
    .padding(.vertical, 4)
  }

  private func selectionToggle(
    _ title: String, identifier: String, isOn: Binding<Bool>, partiallySelected: Bool = false,
    accessibilityTitle: String? = nil
  ) -> some View {
    HStack(spacing: 8) {
      HStack {
        Text(L10n.text(title, locale: locale))
        if partiallySelected {
          Image(systemName: "minus.circle.fill").foregroundStyle(colorTheme.accent)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(.rect)
      .onTapGesture { isOn.wrappedValue.toggle() }
      .accessibilityHidden(true)
      Toggle(L10n.text(title, locale: locale), isOn: isOn)
        .labelsHidden()
        .accessibilityLabel(accessibilityTitle ?? L10n.text(title, locale: locale))
        .accessibilityHint(partiallySelected ? L10n.text("Частично выбрано", locale: locale) : "")
        .accessibilityIdentifier(identifier)
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
      if ExerciseMuscle.inGroup(group).isEmpty {
        Text(MuscleSelectionText.groupTitle(group, locale: locale)).font(.headline)
      } else {
        Button {
          if !expandedGroups.insert(group).inserted { expandedGroups.remove(group) }
        } label: {
          HStack {
            Text(MuscleSelectionText.groupTitle(group, locale: locale))
              .font(.headline).foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
              .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }.frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityValue(
          L10n.text(expandedGroups.contains(group) ? "Развёрнуто" : "Свёрнуто", locale: locale)
        )
        .accessibilityIdentifier("expandMuscleGroup_\(group.rawValue)")
      }
    }
  }
}

enum MuscleSelectionText {
  static func groupTitle(_ group: MuscleGroup, locale: Locale) -> String {
    L10n.text(group == .shoulders ? "Плечи и шея" : group.title, locale: locale)
  }

  static func summary(_ selection: ExerciseMuscleSelection, locale: Locale) -> String {
    guard !selection.isEmpty else { return L10n.text("Все мышцы", locale: locale) }
    var labels: [String] = []
    for group in MuscleGroup.allCases {
      if selection.groups.contains(group) {
        labels.append(groupTitle(group, locale: locale))
        continue
      }
      for muscle in ExerciseMuscle.inGroup(group) {
        if selection.muscles.contains(muscle) {
          labels.append(L10n.text(muscle.title, locale: locale))
          continue
        }
        let regions = ExerciseMuscleRegion.inMuscle(muscle)
          .filter { selection.regions.contains($0) }
          .map { L10n.text($0.title, locale: locale) }
        if !regions.isEmpty {
          labels.append(
            L10n.format(
              "%@: %@", L10n.text(muscle.title, locale: locale),
              regions.joined(separator: ", "), locale: locale))
        }
      }
    }
    return labels.joined(separator: "; ")
  }

  static func compactSummary(_ selection: ExerciseMuscleSelection, locale: Locale) -> String {
    let count = selection.groups.count + selection.muscles.count + selection.regions.count
    return count > 1
      ? L10n.format("Мышцы: %@", String(count), locale: locale)
      : summary(selection, locale: locale)
  }
}
