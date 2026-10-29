import Foundation

/// Unkeyed BLAKE3-256 content addresses used by original PhotoCraft projects.
/// Algorithm follows the official CC0 reference implementation; provenance and
/// independent vectors are recorded in Pcraft fixture documentation.
enum PcraftBLAKE3 {
  private static let iv: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ]
  private static let permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

  private struct Output {
    let cv: [UInt32]
    let words: [UInt32]
    let counter: UInt64
    let length: UInt32
    let flags: UInt32
    func chainingValue() -> [UInt32] {
      Array(compress(cv, words, counter, length, flags).prefix(8))
    }
  }

  static func hash(_ data: Data) throws -> Data {
    try Task.checkCancellation()
    return try data.withUnsafeBytes { input in
      var stack: [[UInt32]] = []
      let chunks = max(1, (input.count + 1023) / 1024)
      var final: Output?
      for chunk in 0..<chunks {
        try Task.checkCancellation()
        let start = chunk * 1024, end = min(start + 1024, input.count)
        var cv = iv
        let blocks = max(1, (end - start + 63) / 64)
        var output: Output?
        for block in 0..<blocks {
          let offset = start + block * 64, length = min(64, end - offset)
          var words = [UInt32](repeating: 0, count: 16)
          for i in 0..<length { words[i / 4] |= UInt32(input[offset + i]) << ((i % 4) * 8) }
          output = Output(cv: cv, words: words, counter: UInt64(chunk),
            length: UInt32(length), flags: (block == 0 ? 1 : 0) | (block == blocks - 1 ? 2 : 0))
          if block < blocks - 1 { cv = output!.chainingValue() }
        }
        if chunk == chunks - 1 {
          final = output
        } else {
          var value = output!.chainingValue(), completed = chunk + 1
          while completed & 1 == 0 {
            value = parent(stack.removeLast(), value).chainingValue()
            completed >>= 1
          }
          stack.append(value)
        }
      }
      var output = final!
      while let left = stack.popLast() { output = parent(left, output.chainingValue()) }
      let words = compress(output.cv, output.words, 0, output.length, output.flags | 8)
      var result = Data()
      for word in words.prefix(8) {
        for shift in stride(from: 0, to: 32, by: 8) { result.append(UInt8(truncatingIfNeeded: word >> shift)) }
      }
      return result
    }
  }

  static func hex(_ data: Data) throws -> String {
    try hash(data).map { String(format: "%02x", $0) }.joined()
  }

  private static func parent(_ left: [UInt32], _ right: [UInt32]) -> Output {
    Output(cv: iv, words: left + right, counter: 0, length: 64, flags: 4)
  }
  private static func rotate(_ value: UInt32, _ count: Int) -> UInt32 {
    (value >> count) | (value << (32 - count))
  }
  private static func mix(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int,
    _ x: UInt32, _ y: UInt32) {
    s[a] = s[a] &+ s[b] &+ x; s[d] = rotate(s[d] ^ s[a], 16)
    s[c] = s[c] &+ s[d]; s[b] = rotate(s[b] ^ s[c], 12)
    s[a] = s[a] &+ s[b] &+ y; s[d] = rotate(s[d] ^ s[a], 8)
    s[c] = s[c] &+ s[d]; s[b] = rotate(s[b] ^ s[c], 7)
  }
  private static func compress(_ cv: [UInt32], _ words: [UInt32], _ counter: UInt64,
    _ length: UInt32, _ flags: UInt32) -> [UInt32] {
    var s = cv + Array(iv.prefix(4)) + [
      UInt32(truncatingIfNeeded: counter), UInt32(counter >> 32), length, flags,
    ]
    var m = words
    for round in 0..<7 {
      mix(&s, 0, 4, 8, 12, m[0], m[1]); mix(&s, 1, 5, 9, 13, m[2], m[3])
      mix(&s, 2, 6, 10, 14, m[4], m[5]); mix(&s, 3, 7, 11, 15, m[6], m[7])
      mix(&s, 0, 5, 10, 15, m[8], m[9]); mix(&s, 1, 6, 11, 12, m[10], m[11])
      mix(&s, 2, 7, 8, 13, m[12], m[13]); mix(&s, 3, 4, 9, 14, m[14], m[15])
      if round < 6 { m = permutation.map { m[$0] } }
    }
    for i in 0..<8 { s[i] ^= s[i + 8]; s[i + 8] ^= cv[i] }
    return s
  }
}
