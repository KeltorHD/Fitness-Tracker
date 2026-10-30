import FitnessTrackerCore
import Foundation

struct HeartRateDevice: Identifiable, Equatable, Sendable {
  let id: UUID
  let name: String
}

enum HeartRateConnection: Equatable, Sendable {
  case idle, scanning, connecting, connected, disconnected, poweredOff, unauthorized, unsupported
  case failed
}

struct HeartRateBluetoothSnapshot: Sendable {
  var connection = HeartRateConnection.idle
  var devices: [HeartRateDevice] = []
  var deviceName: String?
  var reading: HeartRateReading?
}

@MainActor protocol HeartRateBluetooth: AnyObject {
  var onChange: (@MainActor (HeartRateBluetoothSnapshot) -> Void)? { get set }
  func scan()
  func stopScan()
  func connect(_ id: UUID)
  func disconnect()
}
