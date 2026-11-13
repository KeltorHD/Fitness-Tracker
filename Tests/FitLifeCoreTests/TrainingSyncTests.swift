import Foundation
import Testing

@testable import FitLifeCore

private func trainingFingerprint(_ value: TrainingValue) throws -> String {
  try value.canonicalData().base64EncodedString()
}

private func cancelledTrainingWorkout() throws -> Workout {
  var workout = Workout(name: "Тренировка", startedAt: Date(timeIntervalSince1970: 100))
  try WorkoutEngine.cancel(&workout, at: Date(timeIntervalSince1970: 200))
  return workout
}

@Test func trainingPlannerPreservesConcurrentLocalChangesAndAcknowledgesConvergence() throws {
  let original = try cancelledTrainingWorkout()
  let baseline = TrainingBaseline(
    key: TrainingValue.workout(original).key, revision: 1,
    fingerprint: try trainingFingerprint(.workout(original)))
  var local = original
  local.notes = "Сохранено офлайн"
  var remote = original
  remote.notes = "Сохранено на другом устройстве"
  let change = try TrainingChange(key: baseline.key, revision: 2, value: .workout(remote))
  #expect(
    try TrainingSyncPlanner.decision(
      local: .workout(local), baseline: baseline, remote: change, fingerprint: trainingFingerprint)
      == .conflict)
  #expect(
    try TrainingSyncPlanner.decision(
      local: .workout(original), baseline: baseline, remote: change,
      fingerprint: trainingFingerprint) == .apply)
  #expect(
    try TrainingSyncPlanner.decision(
      local: .workout(remote), baseline: baseline, remote: change, fingerprint: trainingFingerprint)
      == .acknowledge)
  let unchanged = try TrainingChange(key: baseline.key, revision: 1, value: .workout(original))
  #expect(
    try TrainingSyncPlanner.decision(
      local: .workout(local), baseline: baseline, remote: unchanged,
      fingerprint: trainingFingerprint) == .ignore)
}

@Test func acknowledgedOldUploadKeepsAnEditMadeWhileRequestWasInFlightPending() throws {
  let sent = try cancelledTrainingWorkout()
  var current = sent
  current.notes = "Изменено во время запроса"
  var state = TrainingSyncState()
  state.remember(
    TrainingBaseline(
      key: TrainingValue.workout(sent).key, revision: 7,
      fingerprint: try trainingFingerprint(.workout(sent))))
  let pending = try TrainingSyncPlanner.pending(
    local: [.workout(current)], state: state, fingerprint: trainingFingerprint)
  #expect(pending.count == 1)
  #expect(pending[0].baseRevision == 7)
  #expect(pending[0].value == .workout(current))
  let older = try TrainingChange(key: pending[0].key, revision: 6, value: .workout(sent))
  #expect(
    try TrainingSyncPlanner.decision(
      local: .workout(current), baseline: state.baselines[0], remote: older,
      fingerprint: trainingFingerprint) == .ignore)
}

@Test func offlineDeletionsRemainPendingAcrossStateEncodingAndConflictsBlockOnlyTheirRecord() throws
{
  let workout = try cancelledTrainingWorkout()
  let value = TrainingValue.workout(workout)
  var state = TrainingSyncState()
  state.remember(
    TrainingBaseline(key: value.key, revision: 3, fingerprint: try trainingFingerprint(value)))
  let decoded = try TrainingCoding.decoder().decode(
    TrainingSyncState.self, from: TrainingCoding.encoder().encode(state))
  let deletion = try TrainingSyncPlanner.pending(
    local: [], state: decoded, fingerprint: trainingFingerprint)
  #expect(deletion.count == 1)
  #expect(deletion[0].value == nil)
  #expect(deletion[0].baseRevision == 3)
  let changed = try TrainingChange(key: value.key, revision: 4, value: value)
  state.remember(TrainingConflict(remote: changed))
  let weight = TrainingValue.bodyWeight(BodyWeightEntry(weightKG: 80))
  let other = try TrainingSyncPlanner.pending(
    local: [weight], state: state, fingerprint: trainingFingerprint)
  #expect(other.map(\.key) == [weight.key])
}

@Test func restoredServerCannotResurrectAcknowledgedDeletionsWithoutAnExplicitChoice() throws {
  let value = TrainingValue.workout(try cancelledTrainingWorkout())
  var state = TrainingSyncState()
  state.remember(TrainingBaseline(key: value.key, revision: 20, fingerprint: nil))
  state.cursor = 20
  state.resetServerRevisions()
  let olderServerCopy = try TrainingChange(key: value.key, revision: 2, value: value)
  #expect(
    try TrainingSyncPlanner.decision(
      local: nil, baseline: state.baselines[0], remote: olderServerCopy,
      fingerprint: trainingFingerprint) == .conflict)
  let pending = try TrainingSyncPlanner.pending(
    local: [], state: state, fingerprint: trainingFingerprint)
  #expect(pending.count == 1)
  #expect(pending[0].baseRevision == 0)
  #expect(pending[0].value == nil)
}

@Test func templateFingerprintsIgnoreSetIterationOrderAndPreserveAllTargets() throws {
  let template = WorkoutTemplate(
    name: "План", exercises: [TemplateExercise(exercise: ExerciseCatalog.all[0])],
    muscleGroups: [.arms, .chest], muscles: [.biceps, .chest],
    preferredWeekdays: [.monday, .friday], baseVariationName: "База",
    muscleRegions: [.bicepsLong, .chestUpper])
  let value = TrainingValue.template(template)
  let encoded = try value.canonicalData()
  let decoded = try TrainingCoding.decoder().decode(TrainingValue.self, from: encoded)
  #expect(decoded == value)
  #expect(try decoded.canonicalData() == encoded)
}

@MainActor @Test func accountJournalsAdoptLocalDataOnceAndKeepAccountSwitchesIsolated() throws {
  let repository = MemoryWorkoutRepository()
  let original = try cancelledTrainingWorkout()
  try repository.save(original)
  try repository.activateTrainingAccount("account-a")
  #expect(try repository.workouts() == [original])
  try repository.activateTrainingAccount("account-b")
  #expect(try repository.workouts().isEmpty)
  let other = try cancelledTrainingWorkout()
  try repository.save(other)
  try repository.activateTrainingAccount("account-a")
  #expect(try repository.workouts() == [original])
  #expect(repository.trainingAccountSelection.firstAccountID == "account-a")
  try repository.activateTrainingAccount("account-b")
  #expect(try repository.workouts() == [other])
}

@MainActor @Test func accountSwitchAndRemoteImportCannotHideAnUnfinishedWorkout() throws {
  let repository = MemoryWorkoutRepository()
  try repository.activateTrainingAccount("account-a")
  let active = Workout(name: "Активная")
  try repository.save(active)
  #expect(throws: TrainingSyncError.activeWorkout) {
    try repository.activateTrainingAccount("account-b")
  }
  let other = TrainingValue.workout(Workout(name: "Другая активная"))
  let change = try TrainingChange(key: other.key, revision: 1, value: other)
  #expect(throws: TrainingSyncError.activeWorkout) { try repository.applyTrainingChanges([change]) }
  #expect(try repository.workouts() == [active])
  #expect(repository.trainingAccountSelection.currentAccountID == "account-a")
}

@MainActor @Test func demoMutationsNeverNotifyPersonalSynchronization() throws {
  let repository = WorkoutWorkspaceRepository(personal: MemoryWorkoutRepository())
  var changes = 0
  repository.onTrainingChange = { changes += 1 }
  try repository.save(cancelledTrainingWorkout())
  #expect(changes == 1)
  try repository.openDemo(WorkoutArchive(workouts: [], templates: []))
  try repository.save(cancelledTrainingWorkout())
  #expect(changes == 1)
  _ = try repository.closeDemo()
  #expect(try repository.workouts().count == 1)
}
