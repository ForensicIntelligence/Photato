/// Streams square windows without keeping the padded source or all of a pass's
/// rows. The first stage replays outgoing rows. The second retains its exact
/// horizontal sums when its ring fits the workspace budget.
enum StreamingAreaFeather {
  static let maximumSecondStageCacheBytes = 40 * 1_024 * 1_024

  static func filter(width: Int, height: Int, widths: [Int], integerSamples: Bool,
    secondStageCacheBytes: Int = maximumSecondStageCacheBytes,
    row: (Int) -> [Float]) -> [Float]? {
    let firstSide = widths[0], secondSide = widths[1]
    let firstWidth = width - firstSide + 1
    let secondWidth = firstWidth - secondSide + 1
    let storesSecondRows = secondWidth <= secondStageCacheBytes / MemoryLayout<Double>.stride / secondSide
    var first = Stage(width: firstWidth, side: firstSide, replay: true, integerSamples: integerSamples)
    var laggedFirst: Stage? = storesSecondRows ? nil : first
    var second = Stage(width: secondWidth, side: secondSide, replay: !storesSecondRows, integerSamples: integerSamples)
    var currentWidth = second.width
    var remaining: [Stage] = []
    for side in widths.dropFirst(2) {
      currentWidth -= side - 1
      remaining.append(Stage(width: currentWidth, side: side, replay: false, integerSamples: integerSamples))
    }
    let resultHeight = height - widths.reduce(0) { $0 + $1 - 1 }
    var output: [Float] = []
    output.reserveCapacity(currentWidth * resultHeight)
    for y in 0..<height {
      if y % 16 == 0 && Task.isCancelled { return nil }
      // When the ring exceeds the budget, keep an independent pass to replay
      // the first-stage output from secondSide rows ago.
      let lag = y - secondSide
      let leaving = lag >= 0 ? laggedFirst?.advance(row(lag),
        leaving: lag >= firstSide ? row(lag - firstSide) : nil) : nil
      guard let entering = first.advance(row(y), leaving: y >= firstSide ? row(y - firstSide) : nil)
      else { continue }
      var next = second.advance(entering, leaving: leaving)
      for i in remaining.indices {
        guard let current = next else { break }
        next = remaining[i].advance(current, leaving: nil)
      }
      if let next { output.append(contentsOf: next) }
    }
    return output
  }

  private struct Stage {
    let width: Int
    let side: Int
    private let replay: Bool
    private let integerSamples: Bool
    private var vertical: [Double]
    private var ring: [Double]
    private var rows = 0

    init(width: Int, side: Int, replay: Bool, integerSamples: Bool) {
      self.width = width
      self.side = side
      self.replay = replay
      self.integerSamples = integerSamples
      vertical = [Double](repeating: 0, count: width)
      ring = [Double](repeating: 0, count: replay ? 0 : width * side)
    }

    mutating func advance(_ entering: [Float], leaving: [Float]?) -> [Float]? {
      let offset = (rows % side) * width
      var incoming = 0.0, outgoing = 0.0
      for i in 0..<side { incoming += Double(entering[i]) }
      if let leaving {
        for i in 0..<side { outgoing += Double(leaving[i]) }
      }
      for x in 0..<width {
        if x > 0 {
          incoming += Double(entering[x + side - 1]) - Double(entering[x - 1])
          if let leaving { outgoing += Double(leaving[x + side - 1]) - Double(leaving[x - 1]) }
        }
        if replay {
          vertical[x] += incoming - outgoing
        } else {
          vertical[x] += incoming - ring[offset + x]
          ring[offset + x] = incoming
        }
      }
      rows += 1
      guard rows >= side else { return nil }
      let area = Double(side * side)
      if integerSamples { return vertical.map { Float(($0 / area).rounded()) } }
      return vertical.map { Float($0 / area) }
    }
  }
}
