import Foundation
import Testing

@testable import FitLifeCore

@Test func watchArchiveMigrationPreservesOutboxAndAssignsOnlyFirstAccount() throws {
  let active = Workout(name: "На часах", startedAt: Date(timeIntervalSince1970: 100))
  var completed = Workout(name: "В очереди", startedAt: Date(timeIntervalSince1970: 10))
  try WorkoutEngine.cancel(&completed, at: Date(timeIntervalSince1970: 20))
  struct CurrentLocalArchive: Encodable {
    let active: Workout
    let pending: [Workout]
  }
  let data = try JSONEncoder().encode(CurrentLocalArchive(active: active, pending: [completed]))
  var archive = try JSONDecoder().decode(WatchTrainingArchive.self, from: data)
  #expect(archive.active == active && archive.pending == [completed])
  try archive.receive(
    WatchTrainingContext(currentAccountID: "account-a", firstAccountID: "account-a"))
  #expect(archive.activeAccountID == "account-a")
  #expect(archive.account(for: completed.id) == "account-a")
  try archive.receive(
    WatchTrainingContext(currentAccountID: "account-b", firstAccountID: "account-a"))
  #expect(archive.activeAccountID == "account-a")
  #expect(archive.account(for: completed.id) == "account-a")
  try archive.update(active: nil, pending: archive.pending + [active])
  #expect(archive.account(for: active.id) == "account-a")
  let next = Workout(name: "Другой аккаунт")
  try archive.update(active: next, pending: archive.pending)
  #expect(archive.activeAccountID == "account-b")
  let restored = try JSONDecoder().decode(
    WatchTrainingArchive.self, from: JSONEncoder().encode(archive))
  #expect(restored == archive)
  try archive.update(active: next, pending: archive.pending.filter { $0.id != completed.id })
  #expect(archive.pending == [active])
  #expect(archive.account(for: active.id) == "account-a")
  #expect(archive.account(for: completed.id) == nil)
}

@Test func phoneAcceptsWatchOutboxOnlyInOwningJournal() throws {
  let local = WatchTrainingContext()
  #expect(local.accepts(nil))
  #expect(!local.accepts("account-a"))
  let first = WatchTrainingContext(currentAccountID: "account-a", firstAccountID: "account-a")
  #expect(first.accepts(nil) && first.accepts("account-a"))
  let second = WatchTrainingContext(currentAccountID: "account-b", firstAccountID: "account-a")
  #expect(!second.accepts(nil) && !second.accepts("account-a") && second.accepts("account-b"))
  #expect(throws: TrainingSyncError.invalidData) {
    try WatchTrainingContext(currentAccountID: "../bad").validate()
  }
}
