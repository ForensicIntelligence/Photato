import Foundation

/// Seed-zero XXH64 checksum required by Zstandard frames (RFC 8878).
enum PcraftXXHash64 {
  private static let p1: UInt64 = 11400714785074694791
  private static let p2: UInt64 = 14029467366897019727
  private static let p3: UInt64 = 1609587929392839161
  private static let p4: UInt64 = 9650029242287828579
  private static let p5: UInt64 = 2870177450012600261
  private static func rotate(_ value: UInt64, _ n: Int) -> UInt64 { (value << n) | (value >> (64 - n)) }
  private static func round(_ state: UInt64, _ value: UInt64) -> UInt64 {
    rotate(state &+ value &* p2, 31) &* p1
  }
  static func hash(_ bytes: [UInt8]) throws -> UInt64 {
    func number(_ at: Int, _ length: Int) -> UInt64 {
      var value: UInt64 = 0
      for i in 0..<length { value |= UInt64(bytes[at + i]) << (8 * i) }
      return value
    }
    var at = 0, result: UInt64
    if bytes.count >= 32 {
      var lanes: [UInt64] = [p1 &+ p2, p2, 0, 0 &- p1]
      while at <= bytes.count - 32 {
        if at & 65535 == 0 { try Task.checkCancellation() }
        for i in 0..<4 { lanes[i] = round(lanes[i], number(at + i * 8, 8)) }
        at += 32
      }
      result = rotate(lanes[0], 1) &+ rotate(lanes[1], 7) &+ rotate(lanes[2], 12) &+ rotate(lanes[3], 18)
      for lane in lanes { result = (result ^ round(0, lane)) &* p1 &+ p4 }
    } else { result = p5 }
    result &+= UInt64(bytes.count)
    while at <= bytes.count - 8 {
      result = rotate(result ^ round(0, number(at, 8)), 27) &* p1 &+ p4; at += 8
    }
    if at <= bytes.count - 4 {
      result = rotate(result ^ (number(at, 4) &* p1), 23) &* p2 &+ p3; at += 4
    }
    while at < bytes.count {
      result = rotate(result ^ (UInt64(bytes[at]) &* p5), 11) &* p1; at += 1
    }
    result ^= result >> 33; result &*= p2
    result ^= result >> 29; result &*= p3
    return result ^ (result >> 32)
  }
}
