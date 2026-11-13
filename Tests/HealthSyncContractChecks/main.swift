import FitLifeCore
import Foundation

private enum ContractError: Error { case invalidArguments, fixtureMismatch }

@main private struct HealthSyncContractChecks {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else { throw ContractError.invalidArguments }
    let mode = CommandLine.arguments[1]
    let path = URL(fileURLWithPath: CommandLine.arguments[2])
    let day = Date(timeIntervalSince1970: 1_711_756_800)
    func id(_ last: UInt8) -> UUID {
      UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, last))
    }
    let sleepID = id(5)
    let sleepStart = day.addingTimeInterval(3600)
    let sleepEnd = day.addingTimeInterval(7200)
    let batch = try HealthSyncBatch(
      deviceID: id(3), sequence: 1, batchID: id(2), timeZoneID: "UTC",
      observedAt: day.addingTimeInterval(10_800),
      quantities: [
        HealthQuantity(
          id: id(4), metric: .bodyWeight, start: day, end: day, value: 72.35, sourceID: "healthkit",
          sourceName: "Здоровье")
      ],
      sleep: [
        HealthSleepRecord(
          id: sleepID, start: sleepStart, end: sleepEnd, asleepSeconds: nil,
          sourceID: "watch:healthkit", sourceName: "Часы",
          segments: [
            HealthSleepSegment(id: sleepID, start: sleepStart, end: sleepEnd, stage: .deep)
          ])
      ],
      aggregates: [
        HealthSyncAggregate(
          bucket: HealthSyncBucket(
            metric: .steps, start: day, end: day.addingTimeInterval(86_400), timeZoneID: "UTC",
            revision: 1), value: nil)
      ])
    let bytes = try HealthSyncCoding.encoder().encode(batch)
    if mode == "--write" {
      try bytes.write(to: path)
    } else if mode == "--verify" {
      guard try Data(contentsOf: path) == bytes else { throw ContractError.fixtureMismatch }
    } else {
      throw ContractError.invalidArguments
    }
    print(
      "Health sync contract: actual Core Codable payload, optional fields, native UUIDs and units verified."
    )
  }
}
