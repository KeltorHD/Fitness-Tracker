import Foundation

/// RFC 4122 UUID v5 for import identities, not for cryptographic authentication.
enum StableIdentifier {
  static let urlNamespace = UUID(
    uuid: (
      0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
      0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
    ))

  static func uuid(_ name: String, namespace: UUID = urlNamespace) -> UUID {
    var namespaceBytes = namespace.uuid
    var bytes = withUnsafeBytes(of: &namespaceBytes) { Array($0) }
    bytes.append(contentsOf: name.utf8)
    var digest = sha1(bytes)
    digest[6] = (digest[6] & 0x0f) | 0x50
    digest[8] = (digest[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
        digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
      ))
  }

  private static func rotate(_ value: UInt32, by count: UInt32) -> UInt32 {
    (value << count) | (value >> (32 - count))
  }
  private static func sha1(_ input: [UInt8]) -> [UInt8] {
    var bytes = input
    let bitCount = UInt64(bytes.count) * 8
    bytes.append(0x80)
    while bytes.count % 64 != 56 { bytes.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
    }
    var hash: [UInt32] = [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476, 0xc3d2_e1f0]
    for offset in stride(from: 0, to: bytes.count, by: 64) {
      var words = [UInt32](repeating: 0, count: 80)
      for index in 0..<16 {
        let start = offset + index * 4
        words[index] =
          UInt32(bytes[start]) << 24 | UInt32(bytes[start + 1]) << 16
          | UInt32(bytes[start + 2]) << 8 | UInt32(bytes[start + 3])
      }
      for index in 16..<80 {
        words[index] = rotate(
          words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16], by: 1)
      }
      var a = hash[0]
      var b = hash[1]
      var c = hash[2]
      var d = hash[3]
      var e = hash[4]
      for index in 0..<80 {
        let function: UInt32
        let constant: UInt32
        switch index {
        case 0..<20:
          function = (b & c) | (~b & d)
          constant = 0x5a82_7999
        case 20..<40:
          function = b ^ c ^ d
          constant = 0x6ed9_eba1
        case 40..<60:
          function = (b & c) | (b & d) | (c & d)
          constant = 0x8f1b_bcdc
        default:
          function = b ^ c ^ d
          constant = 0xca62_c1d6
        }
        let next = rotate(a, by: 5) &+ function &+ e &+ constant &+ words[index]
        e = d
        d = c
        c = rotate(b, by: 30)
        b = a
        a = next
      }
      hash[0] &+= a
      hash[1] &+= b
      hash[2] &+= c
      hash[3] &+= d
      hash[4] &+= e
    }
    return hash.flatMap { word in
      [
        UInt8(truncatingIfNeeded: word >> 24), UInt8(truncatingIfNeeded: word >> 16),
        UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word),
      ]
    }
  }
}
