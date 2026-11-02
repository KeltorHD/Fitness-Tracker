import FitnessTrackerCore
import SwiftUI
import UIKit

enum WorkoutStartSelection {
  case empty
  case templates([WorkoutTemplate])
}

struct WorkoutStartView: View {
  @Environment(\.fitnessColorTheme) private var colorTheme
  @Environment(AppStore.self) private var store
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.dismiss) private var dismiss
  @State private var currentDate = Date()
  @State private var selectedIDs: [UUID] = []
  @State private var filter = WorkoutTemplateFilter()
  @State private var suggestions = WorkoutTemplateSuggestions(
    templates: [], date: .now, calendar: .current)
  let onSelect: (WorkoutStartSelection) -> Void

  private var selectedTemplates: [WorkoutTemplate] {
    selectedIDs.compactMap { id in store.templates.first { $0.id == id } }
  }

  private var localCalendar: Calendar {
    var value = calendar
    value.timeZone = timeZone
    return value
  }

  private var hiddenSelectionCount: Int {
    let visible = Set((suggestions.today + suggestions.others).map(\.id))
    return selectedTemplates.filter { !visible.contains($0.id) }.count
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if store.templates.isEmpty {
            ContentUnavailableView(
              L10n.text("Мои шаблоны", locale: locale), systemImage: "dumbbell",
              description: Text(
                L10n.text(
                  "Шаблонов пока нет. Их можно создать в разделе «Шаблоны».", locale: locale))
            ).accessibilityIdentifier("workoutStartEmptyTemplates")
          } else if suggestions.today.isEmpty && suggestions.others.isEmpty {
            ContentUnavailableView(
              L10n.text("Нет подходящих шаблонов", locale: locale),
              systemImage: "line.3.horizontal.decrease",
              description: Text(L10n.text("Измените поиск или сбросьте фильтры.", locale: locale)))
            Button(L10n.text("Сбросить поиск и фильтры", locale: locale)) {
              filter = WorkoutTemplateFilter()
            }.accessibilityIdentifier("resetWorkoutTemplateFilters")
          } else {
            if !suggestions.today.isEmpty {
              templateHeading("На сегодня")
              ForEach(suggestions.today) { templateRow($0) }
            }
            if !suggestions.others.isEmpty {
              templateHeading(suggestions.today.isEmpty ? "Мои шаблоны" : "Другие шаблоны")
              ForEach(suggestions.others) { templateRow($0) }
            }
          }
        }.padding(16)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(FitTheme.paper)
      .navigationTitle(L10n.text("Шаблоны", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .searchable(
        text: $filter.query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: L10n.text("Название шаблона или упражнения", locale: locale)
      )
      .safeAreaInset(edge: .top, spacing: 0) { filterBar }
      .safeAreaInset(edge: .bottom) {
        if !store.templates.isEmpty { startControls }
      }
      .onChange(of: filter, initial: true) { refresh() }
      .onChange(of: localCalendar) { refresh() }
      .onChange(of: currentDate) { refresh() }
      .onChange(of: phase) {
        if phase == .active { currentDate = Date() }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
      ) { _ in
        currentDate = Date()
      }
      .onChange(of: store.templates) {
        let availableIDs = Set(store.templates.map(\.id))
        selectedIDs.removeAll { !availableIDs.contains($0) }
        refresh()
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Закрыть", locale: locale), systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly).accessibilityIdentifier("closeWorkoutStart")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            onSelect(.empty)
          } label: {
            if typeSize.isAccessibilitySize {
              Image(systemName: "plus")
            } else {
              Label(L10n.text("Без шаблона", locale: locale), systemImage: "plus")
            }
          }
          .font(.subheadline).buttonStyle(.glass).controlSize(.small)
          .accessibilityLabel(L10n.text("Без шаблона", locale: locale))
          .accessibilityHint(
            L10n.text("Начать тренировку с пустым списком упражнений.", locale: locale)
          )
          .accessibilityIdentifier("startWorkoutWithoutTemplate")
        }
      }
    }
  }

  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        Menu {
          Picker(L10n.text("Расписание", locale: locale), selection: $filter.schedule) {
            ForEach(WorkoutTemplateFilter.Schedule.allCases, id: \.self) { schedule in
              Text(L10n.text(schedule.title, locale: locale)).tag(schedule)
            }
          }
          Section(L10n.text("Инвентарь", locale: locale)) {
            Button(L10n.text("Весь инвентарь", locale: locale)) { filter.equipment = [] }
            ForEach(ExerciseEquipment.allCases, id: \.self) { value in
              Toggle(
                L10n.text(value.title, locale: locale),
                isOn: Binding(
                  get: { filter.equipment.contains(value) },
                  set: { selected in
                    if selected {
                      filter.equipment.insert(value)
                    } else {
                      filter.equipment.remove(value)
                    }
                  }))
            }
          }
        } label: {
          Label(
            L10n.text(filter.hasFilters ? "Фильтры включены" : "Фильтры", locale: locale),
            systemImage: "line.3.horizontal.decrease")
        }.accessibilityIdentifier("workoutTemplateFilters")
        NavigationLink {
          MuscleSelectionView(selection: $filter.muscles, showsDoneButton: true)
        } label: {
          Label(
            MuscleSelectionText.compactSummary(filter.muscles, locale: locale),
            systemImage: "figure.strengthtraining.traditional")
        }.accessibilityIdentifier("workoutTemplateMuscles")
        if filter.isActive {
          Button(L10n.text("Сбросить", locale: locale), systemImage: "xmark") {
            filter = WorkoutTemplateFilter()
          }.accessibilityIdentifier("clearWorkoutTemplateFilters")
        }
      }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 16).padding(.vertical, 8)
    }.background(FitTheme.paper)
  }

  private var startControls: some View {
    VStack(spacing: 8) {
      Text(
        selectedTemplates.isEmpty
          ? L10n.text("Выберите один или несколько шаблонов.", locale: locale)
          : L10n.format("Выбрано шаблонов: %@", String(selectedTemplates.count), locale: locale)
      )
      .font(.subheadline).foregroundStyle(.secondary)
      if hiddenSelectionCount > 0 {
        Text(L10n.format("Выбрано вне фильтра: %@", String(hiddenSelectionCount), locale: locale))
          .font(.caption).foregroundStyle(.secondary)
      }
      if selectedTemplates.count > 1 {
        Text(
          L10n.text(
            "При объединении параметры упражнения берутся из первого вхождения, отдых — из первого выбранного шаблона.",
            locale: locale)
        ).font(.caption).foregroundStyle(.secondary)
      }
      Button(L10n.text("Начать тренировку", locale: locale), systemImage: "play.fill") {
        let templates = selectedTemplates
        guard !templates.isEmpty else { return }
        onSelect(.templates(templates))
      }
      .buttonStyle(.glassProminent).controlSize(.large)
      .disabled(selectedTemplates.isEmpty)
      .accessibilityIdentifier("startSelectedTemplates")
    }
    .frame(maxWidth: .infinity).padding(16).background(FitTheme.paper)
  }

  private func refresh() {
    suggestions = filter.apply(to: store.templates, date: currentDate, calendar: localCalendar)
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
        Image(systemName: "dumbbell").foregroundStyle(colorTheme.accent).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(template.name).font(.headline)
          TemplateMuscleGroups(template: template)
          Text(L10n.format("Упражнения: %@", String(template.exercises.count), locale: locale))
            .font(.caption).foregroundStyle(.secondary)
          if let selectionIndex {
            Text(L10n.format("Порядок: %@", String(selectionIndex + 1), locale: locale))
              .font(.caption).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: selectionIndex == nil ? "circle" : "checkmark.circle.fill")
          .foregroundStyle(selectionIndex == nil ? FitTheme.muted : colorTheme.accent)
          .accessibilityHidden(true)
      }
      .padding(18).frame(minHeight: 64)
      .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius)).contentShape(.rect)
    }
    .buttonStyle(.plain).accessibilityIdentifier("startWorkoutTemplate_\(template.id)")
    .accessibilityAddTraits(selectionIndex == nil ? [] : [.isSelected])
  }
}
