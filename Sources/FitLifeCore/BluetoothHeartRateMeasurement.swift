import Foundation

/// Bluetooth SIG Heart Rate Measurement (0x2A37), not a proprietary Xiaomi protocol.
public struct BluetoothHeartRateMeasurement: Equatable, Sendable {
  public let beatsPerMinute: UInt16
  public let hasSkinContact: Bool?
  public let energyKJ: UInt16?
  public let rrIntervals: [TimeInterval]

  public static func decode(_ data: Data) throws -> Self {
    let bytes = Array(data)
    guard let flags = bytes.first, flags & 0xE0 == 0 else {
      throw TrackerDataError.malformedPacket
    }
    var offset = 1
    func word() throws -> UInt16 {
      guard offset + 1 < bytes.count else { throw TrackerDataError.malformedPacket }
      defer { offset += 2 }
      return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    let bpm: UInt16
    if flags & 1 != 0 {
      bpm = try word()
    } else {
      guard offset < bytes.count else { throw TrackerDataError.malformedPacket }
      bpm = UInt16(bytes[offset])
      offset += 1
    }
    let energy = flags & 8 != 0 ? try word() : nil
    var rr: [TimeInterval] = []
    if flags & 16 != 0 {
      guard offset < bytes.count else { throw TrackerDataError.malformedPacket }
      while offset < bytes.count { rr.append(Double(try word()) / 1024) }
    }
    guard offset == bytes.count else { throw TrackerDataError.malformedPacket }
    return Self(
      beatsPerMinute: bpm, hasSkinContact: flags & 4 != 0 ? flags & 2 != 0 : nil,
      energyKJ: energy, rrIntervals: rr)
  }
}
