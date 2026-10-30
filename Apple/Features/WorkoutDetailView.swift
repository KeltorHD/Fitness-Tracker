import FitnessTrackerCore
import SwiftUI

struct WorkoutDetailView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
  @State private var exporting = false
  @State private var editing = false
  @State private var templateDraft: WorkoutTemplate?
  @State private var confirmDelete = false
  let workout: Workout
  var onRepeat: ((Workout) -> Void)? = nil
  private var session: Workout { store.workouts.first { $0.id == workout.id } ?? workout }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        WorkoutHero(title: session.name, showsDate: false)
        VStack(spacing: 20) {
          WorkoutSessionSummary(workout: session, unit: unit)
          VStack(spacing: 0) {
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, row in
              NavigationLink {
                WorkoutExerciseView(workout: session, exerciseID: row.id, unit: unit)
              } label: {
                WorkoutExerciseListRow(row: row, index: index, unit: unit, completedOnly: true)
              }.buttonStyle(.plain).accessibilityIdentifier("openWorkoutExercise")
              Divider().padding(.leading, 34)
            }
          }
          WorkoutBodyWeightRow(workout: session).fitCard()
          if !session.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text(L10n.text("Заметка", locale: locale)).font(.headline)
              Text(session.notes)
            }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
          }
          if !store.isDemoMode {
            WorkoutHeartRateView(workout: session, tracker: store.tracker)
            Button(L10n.text("Экспорт в «Здоровье»", locale: locale), systemImage: "heart") {
              exporting = true
            }.disabled(exporting || session.durationIsKnown == false).frame(
              maxWidth: .infinity, alignment: .leading)
            if session.durationIsKnown == false {
              Text(
                L10n.text(
                  "В исходном файле нет длительности тренировки. Экспорт в «Здоровье» недоступен.",
                  locale: locale)
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
          }
          Text(
            L10n.text(
              "Калории и пульс не рассчитываются из веса снарядов. В «Здоровье» передаются тип, длительность и паузы тренировки.",
              locale: locale)
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
      }
    }
    .background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .top) { if store.isDemoMode { DemoModeBanner() } }
    .toolbarBackground(FitTheme.accent, for: .navigationBar).toolbarBackground(
      .visible, for: .navigationBar
    )
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(session.startedAt, format: .dateTime.weekday(.wide).hour().minute())
          .font(.subheadline).textCase(.uppercase).foregroundStyle(.white)
      }
      ToolbarItem(placement: .topBarLeading) {
        Button(L10n.text("Закрыть", locale: locale), systemImage: "chevron.down") { dismiss() }
          .foregroundStyle(.white)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(L10n.text("Изменить тренировку", locale: locale), systemImage: "pencil") {
            editing = true
          }
          Button(L10n.text("Сохранить как шаблон", locale: locale), systemImage: "list.clipboard") {
            createTemplate()
          }
          ShareLink(item: WorkoutDocument(workout: session), preview: SharePreview(session.name)) {
            Label(L10n.text("Поделиться JSON", locale: locale), systemImage: "square.and.arrow.up")
          }
          Button(L10n.text("Экспорт файла", locale: locale), systemImage: "doc.badge.arrow.up") {
            store.archiveTransfer.present(workout: session)
          }
          Button(L10n.text("Удалить", locale: locale), systemImage: "trash", role: .destructive) {
            confirmDelete = true
          }
        } label: {
          Image(systemName: "ellipsis.circle.fill").foregroundStyle(.white)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Button {
          createTemplate()
        } label: {
          Image(systemName: "plus").font(.title2).frame(width: 48, height: 48).background(
            FitTheme.card, in: .circle)
        }
        .accessibilityLabel(L10n.text("Сохранить как шаблон", locale: locale))
        Spacer()
        Button(L10n.text("Повторить", locale: locale)) {
          if let onRepeat {
            onRepeat(session)
          } else {
            store.repeatWorkout(session)
            dismiss()
          }
        }.font(.headline).buttonStyle(.glassProminent).controlSize(.large)
        Spacer()
        Button {
          editing = true
        } label: {
          Image(systemName: "pencil").font(.title2).frame(width: 48, height: 48).background(
            FitTheme.card, in: .circle)
        }
        .accessibilityLabel(L10n.text("Изменить тренировку", locale: locale))
      }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10).background(
        FitTheme.paper)
    }
    .task(id: exporting) {
      guard exporting else { return }
      await store.exportHealth(session)
      exporting = false
    }
    .sheet(isPresented: $editing) { WorkoutEditorView(workout: session) }
    .sheet(item: $templateDraft, onDismiss: { store.showingTemplateEditor = false }) {
      TemplateEditor(template: $0).onAppear { store.showingTemplateEditor = true }
    }
    .archiveTransferPresenter(
      when: !editing && templateDraft == nil && !confirmDelete && !store.showingBodyWeightEditor
    )
    .confirmationDialog(
      L10n.text("Удалить тренировку?", locale: locale), isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button(L10n.text("Удалить", locale: locale), role: .destructive) {
        store.delete(workout: session)
        if store.error == nil { dismiss() }
      }
    }
    .alert(
      "FitnessTracker",
      isPresented: Binding(
        get: {
          !editing && templateDraft == nil && !store.archiveTransfer.isPresented
            && !store.showingBodyWeightEditor
            && (store.error != nil || store.notice != nil)
        },
        set: {
          if !$0 {
            store.error = nil
            store.notice = nil
          }
        })
    ) {
      Button(L10n.text("Понятно", locale: locale)) {
        store.error = nil
        store.notice = nil
      }
    } message: {
      Text(L10n.text(store.error ?? store.notice ?? "", locale: locale))
    }
  }
  private func createTemplate() {
    do { templateDraft = try WorkoutEngine.makeTemplate(from: session) } catch {
      store.error = error.localizedDescription
    }
  }
}

struct WorkoutEditorView: View {
  @Environment(\.locale) private var locale
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State var workout: Workout
  @State private var message: String?
  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("Название и заметка", locale: locale)) {
          TextField(L10n.text("Название", locale: locale), text: $workout.name)
          TextField(L10n.text("Заметка", locale: locale), text: $workout.notes, axis: .vertical)
        }
        Section(L10n.text("Упражнения", locale: locale)) {
          ForEach(workout.exercises) { item in
            VStack(alignment: .leading, spacing: 5) {
              Text(L10n.exerciseName(item.exercise, locale: locale)).font(.headline)
              Text(
                L10n.countText(
                  item.sets.filter { $0.completedAt != nil }.count, kind: "completed.set",
                  locale: locale)
              ).font(
                .subheadline
              ).foregroundStyle(.secondary)
            }
          }
          .onMove { workout.exercises.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { workout.exercises.remove(atOffsets: $0) }
        }
        if let message { Text(L10n.text(message, locale: locale)).foregroundStyle(.red) }
      }
      .navigationTitle(L10n.text("Изменить тренировку", locale: locale))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Отмена", locale: locale)) { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) { EditButton() }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Готово", locale: locale)) {
            if store.updateCompleted(workout) { dismiss() } else { message = store.error }
          }
        }
      }
      .archiveTransferPresenter(when: true)
    }.tint(FitTheme.accent)
  }
}
