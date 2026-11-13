import Foundation

public struct WatchTrainingContext: Codable, Equatable, Sendable {
  public let currentAccountID: String?
  public let firstAccountID: String?
  public init(currentAccountID: String? = nil, firstAccountID: String? = nil) {
    self.currentAccountID = currentAccountID
    self.firstAccountID = firstAccountID
  }
  public func validate() throws {
    for scope in [currentAccountID, firstAccountID].compactMap({ $0 }) {
      guard !scope.isEmpty, scope.count <= 256,
        scope.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
      else { throw TrainingSyncError.invalidData }
    }
  }
  public func accepts(_ owner: String?) -> Bool {
    if let owner { return currentAccountID == owner }
    return currentAccountID == nil || currentAccountID == firstAccountID
  }
}

/// Version 2 assigns outbox ownership without changing workout UUIDs or acknowledging delivery.
public struct WatchTrainingArchive: Codable, Equatable, Sendable {
  public private(set) var active: Workout?
  public private(set) var pending: [Workout]
  public private(set) var context: WatchTrainingContext
  public private(set) var activeAccountID: String?
  private var pendingAccounts: [String: String]
  public init() {
    active = nil
    pending = []
    context = WatchTrainingContext()
    activeAccountID = nil
    pendingAccounts = [:]
  }
  public func account(for id: UUID) -> String? { pendingAccounts[id.uuidString.lowercased()] }
  public mutating func receive(_ context: WatchTrainingContext) throws {
    try context.validate()
    self.context = context
    if let first = context.firstAccountID {
      if active != nil && activeAccountID == nil { activeAccountID = first }
      for workout in pending where account(for: workout.id) == nil {
        pendingAccounts[workout.id.uuidString.lowercased()] = first
      }
    }
  }
  public mutating func update(active: Workout?, pending: [Workout]) throws {
    if let previous = self.active, pending.contains(where: { $0.id == previous.id }),
      let account = activeAccountID
    {
      pendingAccounts[previous.id.uuidString.lowercased()] = account
    }
    if active?.id != self.active?.id {
      activeAccountID = active == nil ? nil : context.currentAccountID
    }
    self.active = active
    self.pending = pending
    let ids = Set(pending.map { $0.id.uuidString.lowercased() })
    pendingAccounts = pendingAccounts.filter { ids.contains($0.key) }
    try validate()
  }
  private func validate() throws {
    try context.validate()
    if let active { try Validation.workout(active) }
    for workout in pending { try Validation.workout(workout) }
    guard Set(pending.map(\.id)).count == pending.count,
      active == nil || !pending.contains(where: { $0.id == active?.id })
    else { throw TrainingSyncError.invalidData }
    try WatchTrainingContext(currentAccountID: activeAccountID).validate()
    for (id, scope) in pendingAccounts {
      guard pending.contains(where: { $0.id.uuidString.lowercased() == id }) else {
        throw TrainingSyncError.invalidData
      }
      try WatchTrainingContext(currentAccountID: scope).validate()
    }
  }
  private enum Keys: String, CodingKey {
    case version, active, pending, context, activeAccountID, pendingAccounts
  }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    active = try container.decodeIfPresent(Workout.self, forKey: .active)
    pending = try container.decode([Workout].self, forKey: .pending)
    switch version {
    case 1:
      context = WatchTrainingContext()
      activeAccountID = nil
      pendingAccounts = [:]
    case 2:
      context = try container.decode(WatchTrainingContext.self, forKey: .context)
      activeAccountID = try container.decodeIfPresent(String.self, forKey: .activeAccountID)
      pendingAccounts = try container.decode([String: String].self, forKey: .pendingAccounts)
    default: throw TrainingSyncError.invalidData
    }
    try validate()
  }
  public func encode(to encoder: any Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(2, forKey: .version)
    try container.encodeIfPresent(active, forKey: .active)
    try container.encode(pending, forKey: .pending)
    try container.encode(context, forKey: .context)
    try container.encodeIfPresent(activeAccountID, forKey: .activeAccountID)
    try container.encode(pendingAccounts, forKey: .pendingAccounts)
  }
}
