import Foundation

/// One immutable Float32 plane held in scratch storage. Each pass writes
/// bounded chunks and preserves the operation order of the dense filters.
package struct CameraRawScalarPlane: Sendable {
  let width: Int
  let height: Int
  private let storage: FileBackedSource

  init(width: Int, height: Int, filling fill: (Int, UnsafeMutableBufferPointer<Float>) throws -> Void) throws {
    let stride = MemoryLayout<Float>.stride
    self.width = width
    self.height = height
    storage = try FileBackedSource.retain(byteCount: width * height * stride) { bytes, count in
      precondition(bytes.isMultiple(of: stride) && count.isMultiple(of: stride))
      var values = [Float](repeating: 0, count: count / stride)
      try values.withUnsafeMutableBufferPointer { try fill(bytes / stride, $0) }
      return values.withUnsafeBytes { Data($0) }
    }
  }

  package init(width: Int, height: Int, storage: FileBackedSource) throws {
    guard width > 0, height > 0, storage.data.count.isMultiple(of: MemoryLayout<Float>.stride),
      storage.data.count / MemoryLayout<Float>.stride / width == height,
      storage.data.count / MemoryLayout<Float>.stride % width == 0 else {
      throw CraftError.invalid("Invalid Camera Raw scratch plane.")
    }
    self.width = width
    self.height = height
    self.storage = storage
  }

  package init(width: Int, height: Int, values: (Int) -> Float) throws {
    try self.init(width: width, height: height, filling: { start, output in
      for i in output.indices { output[i] = values(start + i) }
    })
  }

  package func withSamples<T>(_ body: (UnsafeBufferPointer<Float>) throws -> T) rethrows -> T {
    try storage.data.withUnsafeBytes { try body($0.bindMemory(to: Float.self)) }
  }

  package subscript(index: Int) -> Float {
    withSamples { $0[index] }
  }

  func box(radius: Int) throws -> Self {
    guard radius > 0 else { return self }
    let w = width, h = height
    let divisor = Double(2 * radius + 1)
    let horizontal = try withSamples { pixels in
      var sum = 0.0
      return try Self(width: w, height: h, filling: { offset, output in
        for i in output.indices {
          let index = offset + i, x = index % w, row = index - x
          if x == 0 {
            sum = 0
            for k in -radius...radius { sum += Double(pixels[row + min(w - 1, max(0, k))]) }
          }
          output[i] = Float(sum / divisor)
          sum += Double(pixels[row + min(w - 1, x + radius + 1)]) - Double(pixels[row + max(0, x - radius)])
        }
      })
    }
    return try horizontal.withSamples { pixels in
      // Each column retains its own running Double sum. Traversing rows
      // keeps scratch reads contiguous without changing any column's recurrence.
      var sums = [Double](repeating: 0, count: w)
      for k in -radius...radius {
        try Task.checkCancellation()
        let row = min(h - 1, max(0, k)) * w
        for x in 0..<w { sums[x] += Double(pixels[row + x]) }
      }
      return try Self(width: w, height: h, filling: { offset, output in
        for i in output.indices {
          let index = offset + i, x = index % w, y = index / w
          output[i] = Float(sums[x] / divisor)
          sums[x] += Double(pixels[min(h - 1, y + radius + 1) * w + x]) - Double(pixels[max(0, y - radius) * w + x])
        }
      })
    }
  }

  package func gaussian(sigma: Float) throws -> Self {
    try CameraRawMath.gaussianRadii(sigma).reduce(self) { try $0.box(radius: $1) }
  }

  func mixing(_ filtered: Self, keeping keep: Float) throws -> Self {
    try withSamples { original in
      try filtered.withSamples { smooth in
        try Self(width: width, height: height, values: { smooth[$0] + (original[$0] - smooth[$0]) * keep })
      }
    }
  }

  func guidedSelf(radius: Int, epsilon: Float) throws -> Self {
    let mean = try box(radius: radius)
    // For self guidance both means and both second moments are identical.
    let squared = try withSamples { values in
      try Self(width: width, height: height, values: { values[$0] * values[$0] })
    }
    let meanSquare = try squared.box(radius: radius)
    let a = try mean.withSamples { m in
      try meanSquare.withSamples { ms in
        try Self(width: width, height: height, values: { i in
          let variance = ms[i] - m[i] * m[i]
          return variance / (max(0, variance) + epsilon)
        })
      }
    }
    let b = try mean.withSamples { m in
      try a.withSamples { coefficients in
        try Self(width: width, height: height, values: { m[$0] - coefficients[$0] * m[$0] })
      }
    }
    let meanA = try a.box(radius: radius), meanB = try b.box(radius: radius)
    return try withSamples { input in
      try meanA.withSamples { slope in
        try meanB.withSamples { offset in
          try Self(width: width, height: height, values: { slope[$0] * input[$0] + offset[$0] })
        }
      }
    }
  }
}
