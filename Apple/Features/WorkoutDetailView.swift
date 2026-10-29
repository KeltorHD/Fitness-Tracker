import FitSessionCore
import SwiftUI

struct WorkoutDetailView: View {
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
        WorkoutHero(title: session.name, date: session.startedAt)
        VStack(spacing: 20) {
          HStack(spacing: 8) {
            SummaryMetric(title: "Время", value: session.duration().workoutDuration)
            SummaryMetric(
              title: "Объём",
              value:
                "\(unit.display(session.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)"
            )
            SummaryMetric(title: "Подходы", value: "\(session.completedSets)")
          }
          ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
            VStack(spacing: 16) {
              NavigationLink {
                ExerciseDetailView(exercise: exercise.exercise)
              } label: {
                HStack(alignment: .top, spacing: 14) {
                  Text("\(index + 1)").font(.subheadline).frame(width: 16)
                  VStack(alignment: .leading, spacing: 7) {
                    Text(exercise.exercise.name).font(.title3.weight(.medium))
                    Text(setSummary(exercise)).font(.subheadline)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  if let entry = ExerciseLibrary.entry(for: exercise.exercise.id) {
                    ExercisePhoto(path: entry.images[0]).frame(width: 48, height: 48)
                      .clipShape(.rect(cornerRadius: 10))
                      .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(
                          .gray.opacity(0.3), lineWidth: 0.5)
                      )
                      .accessibilityHidden(true)
                  }
                }.foregroundStyle(.primary)
              }.buttonStyle(.plain)
              Divider().padding(.leading, 30)
            }
          }
          if !session.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Заметка").font(.headline)
              Text(session.notes)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
              .background(FitTheme.card, in: .rect(cornerRadius: FitTheme.radius))
          }
          Button("Экспорт в «Здоровье»", systemImage: "heart") {
            exporting = true
            Task {
              await store.exportHealth(session)
              exporting = false
            }
          }.disabled(exporting).frame(maxWidth: .infinity, alignment: .leading)
          Text(
            "Калории и пульс не рассчитываются из веса снарядов. В «Здоровье» передаются тип, длительность и паузы тренировки."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
      }
    }
    .background(FitTheme.paper).navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(FitTheme.accent, for: .navigationBar).toolbarBackground(
      .visible, for: .navigationBar
    )
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("Закрыть", systemImage: "chevron.down") { dismiss() }.foregroundStyle(.white)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Изменить тренировку", systemImage: "pencil") { editing = true }
          Button("Сохранить как шаблон", systemImage: "list.clipboard") { createTemplate() }
          ShareLink(item: WorkoutDocument(workout: session), preview: SharePreview(session.name)) {
            Label("Поделиться", systemImage: "square.and.arrow.up")
          }
          Button("Удалить", systemImage: "trash", role: .destructive) { confirmDelete = true }
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
        .accessibilityLabel("Сохранить как шаблон")
        Spacer()
        Button("Повторить") {
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
        .accessibilityLabel("Изменить тренировку")
      }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10).background(
        FitTheme.paper)
    }
    .sheet(isPresented: $editing) { WorkoutEditorView(workout: session) }
    .sheet(item: $templateDraft) { TemplateEditor(template: $0) }
    .confirmationDialog(
      "Удалить тренировку?", isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button("Удалить", role: .destructive) {
        store.delete(workout: session)
        if store.error == nil { dismiss() }
      }
    }
    .alert(
      "FitSession",
      isPresented: Binding(
        get: { store.error != nil || store.notice != nil },
        set: {
          if !$0 {
            store.error = nil
            store.notice = nil
          }
        })
    ) {
      Button("Понятно") {
        store.error = nil
        store.notice = nil
      }
    } message: {
      Text(store.error ?? store.notice ?? "")
    }
  }
  private func setSummary(_ exercise: WorkoutExercise) -> String {
    exercise.sets.filter { $0.completedAt != nil }.map {
      "\(unit.display($0.weightKG).formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue) × \($0.repetitions)"
    }.joined(separator: ", ")
  }
  private func createTemplate() {
    do { templateDraft = try WorkoutEngine.makeTemplate(from: session) } catch {
      store.error = error.localizedDescription
    }
  }
}

struct WorkoutEditorView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State var workout: Workout
  @State private var message: String?
  var body: some View {
    NavigationStack {
      List {
        Section("Название и заметка") {
          TextField("Название", text: $workout.name)
          TextField("Заметка", text: $workout.notes, axis: .vertical)
        }
        Section("Упражнения") {
          ForEach(workout.exercises) { item in
            VStack(alignment: .leading, spacing: 5) {
              Text(item.exercise.name).font(.headline)
              Text("\(item.sets.filter { $0.completedAt != nil }.count) выполненных подходов").font(
                .subheadline
              ).foregroundStyle(.secondary)
            }
          }
          .onMove { workout.exercises.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { workout.exercises.remove(atOffsets: $0) }
        }
        if let message { Text(message).foregroundStyle(.red) }
      }
      .navigationTitle("Изменить тренировку").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        ToolbarItem(placement: .primaryAction) { EditButton() }
        ToolbarItem(placement: .confirmationAction) {
          Button("Готово") {
            if store.updateCompleted(workout) { dismiss() } else { message = store.error }
          }
        }
      }
    }.tint(FitTheme.accent)
  }
}
