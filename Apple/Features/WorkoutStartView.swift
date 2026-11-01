import FitnessTrackerCore
import SwiftUI
import UIKit

enum WorkoutStartSelection {
  case empty
  case templates([WorkoutTemplate])
}

struct WorkoutStartView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.scenePhase) private var phase
  @State private var currentDate = Date()
  @Environment(\.dismiss) private var dismiss
  @State private var selectedIDs: [UUID] = []
  let onSelect: (WorkoutStartSelection) -> Void

  private var selectedTemplates: [WorkoutTemplate] {
    selectedIDs.compactMap { id in store.templates.first { $0.id == id } }
  }

  private var localCalendar: Calendar {
    var value = calendar
    value.timeZone = timeZone
    return value
  }

  var body: some View {
    let suggestions = WorkoutTemplateSuggestions(
      templates: store.templates, date: currentDate, calendar: localCalendar)
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
          if !store.templates.isEmpty {
            Text(
              L10n.text(
                "Выберите один или несколько шаблонов. Повторяющиеся упражнения добавятся один раз.",
                locale: locale)
            ).font(.subheadline).foregroundStyle(.secondary)
            Text(
              L10n.text(
                "При объединении параметры упражнения берутся из первого вхождения, отдых — из первого выбранного шаблона.",
                locale: locale)
            ).font(.caption).foregroundStyle(.secondary)
          }
          if store.templates.isEmpty {
            Text(
              L10n.text(
                "Шаблонов пока нет. Их можно создать в разделе «Шаблоны».", locale: locale)
            )
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityIdentifier("workoutStartEmptyTemplates")
          }
          if !suggestions.today.isEmpty {
            templateHeading("На сегодня")
            ForEach(suggestions.today) { template in
              templateRow(template)
            }
            if !suggestions.others.isEmpty {
              templateHeading("Другие шаблоны")
            }
          }
          ForEach(suggestions.others) { template in
            templateRow(template)
          }
        }
        .padding(16)
      }
      .background(FitTheme.paper)
      .navigationTitle(L10n.text("Начать тренировку", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        if !store.templates.isEmpty {
          VStack(spacing: 8) {
            Text(
              L10n.format("Выбрано шаблонов: %@", String(selectedTemplates.count), locale: locale)
            ).font(.subheadline).foregroundStyle(.secondary)
            Button(L10n.text("Начать тренировку", locale: locale), systemImage: "play.fill") {
              let templates = selectedTemplates
              guard !templates.isEmpty else { return }
              onSelect(.templates(templates))
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(selectedTemplates.isEmpty)
            .accessibilityIdentifier("startSelectedTemplates")
          }
          .frame(maxWidth: .infinity).padding(16)
          .background(FitTheme.paper)
        }
      }
      .onChange(of: phase) {
        if phase == .active { currentDate = Date() }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
      ) { _ in
        currentDate = Date()
      }
      .onChange(of: store.templates.map(\.id)) {
        let availableIDs = Set(store.templates.map(\.id))
        selectedIDs.removeAll { !availableIDs.contains($0) }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale), systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly).accessibilityIdentifier("closeWorkoutStart")
        }
      }
    }
  }

  private func templateHeading(_ title: String) -> some View {
    Text(L10n.text(title, locale: locale))
      .font(.headline).foregroundStyle(.secondary).padding(.top, 8)
      .accessibilityAddTraits(.isHeader)
  }

  private func templateRow(_ template: WorkoutTemplate) -> some View {
    let selectionIndex = selectedIDs.firstIndex(of: template.id)
    return Button {
      if let selectionIndex {
        selectedIDs.remove(at: selectionIndex)
      } else {
        selectedIDs.append(template.id)
      }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "dumbbell").foregroundStyle(FitTheme.accent)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(template.name).font(.headline)
          TemplateMuscleGroups(template: template)
          if let selectionIndex {
            Text(L10n.format("Порядок: %@", String(selectionIndex + 1), locale: locale))
              .font(.caption).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: selectionIndex == nil ? "circle" : "checkmark.circle.fill")
          .foregroundStyle(selectionIndex == nil ? FitTheme.muted : FitTheme.accent)
          .accessibilityHidden(true)
      }
      .padding(18).frame(minHeight: 64)
      .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
      .contentShape(.rect)
    }
    .buttonStyle(.plain).accessibilityIdentifier("startWorkoutTemplate_\(template.id)")
    .accessibilityAddTraits(selectionIndex == nil ? [] : [.isSelected])
  }

}
