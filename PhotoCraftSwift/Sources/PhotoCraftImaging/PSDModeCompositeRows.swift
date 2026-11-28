import Foundation
import PhotoCraftCore

/// Merged previews reuse the existing RGB compositor and mode conversion math,
/// retaining only a bounded band of small converted patches. Layer separations
/// are written independently, directly from their original numerical planes.
final class PSDModeCompositeRows {
  private let document: CraftDocument
  private let descriptor: DocumentModeDescriptor
  private var firstRow = -1, height = 0
  private var patches: [NativeModeRaster] = []
  init(_ document: CraftDocument) throws {
    guard let descriptor=document.modeDescriptor else {throw CraftError.invalid("Missing native mode descriptor.")}
    self.document=document;self.descriptor=descriptor
  }
  func row(_ y: Int, channel: Int, depth: Int) throws -> [UInt8] {
    guard (0...descriptor.mode.componentCount).contains(channel),
      depth == (document.depth == .u8 ? 8 : document.depth == .u16 ? 16 : 32) else {
      throw CraftError.invalid("Invalid Photoshop native composite row.")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(document.width * (depth / 8))
    try forEachSample(inRow: y) { patch, index in
      try PSDChannelCodec.append(PSDModeStorage.mergedSample(patch, component: channel, index: index), depth: depth, to: &bytes)
    }
    return bytes
  }

  func forEachSample(inRow y: Int, _ process: (NativeModeRaster, Int) throws -> Void) throws {
    guard (0..<document.height).contains(y) else { throw CraftError.invalid("Invalid native component row.") }
    if y<firstRow || y>=firstRow+height {
      firstRow=y;height=min(document.height-y,max(1,min(64,PSDCompositeRows.preferredBandPixels/document.width)))
      patches=[]
      for x in stride(from:0,to:document.width,by:2048) {
        try Task.checkCancellation()
        let region=IntRect(x:x,y:y,width:min(2048,document.width-x),height:height)
        let rendered=try Renderer.composite(document,region:region)
        let patch=try rendered.cropped(to:region)
        patches.append(try NativeModeRaster.converting(patch,to:descriptor.mode,depth:document.depth,
          profile:descriptor.profile,intent:descriptor.intent))
      }
    }
    for patch in patches {
      try Task.checkCancellation()
      let rowStart = (y - firstRow) * patch.width
      for x in 0..<patch.width { try process(patch, rowStart + x) }
    }
  }
}

/// Union of stored component blocks. Outside these ranges a numerical layer
/// has its implicit word, and an aligned pointwise composite is also constant.
struct PSDNativeRowSupport {
  private let width: Int
  private let height: Int
  private let ranges: [Range<Int>]
  let implicitIndex: Int

  init?(width: Int, height: Int, streams: [AnySequence<Range<Int>>]) throws {
    var stored: [Range<Int>] = []
    for stream in streams {
      for range in stream {
        try Task.checkCancellation()
        guard stored.count < PSDStoredRows.retainedTileCount else { return nil }
        stored.append(range)
      }
    }
    stored.sort { $0.lowerBound < $1.lowerBound }
    var merged: [Range<Int>] = []
    for range in stored {
      if let previous = merged.last, previous.upperBound >= range.lowerBound {
        merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    let sample = merged.first.map { $0.lowerBound == 0 ? $0.upperBound : 0 } ?? 0
    guard sample < width * height else { return nil }
    self.width = width
    self.height = height
    self.ranges = merged
    implicitIndex = sample
  }

  private func firstRange(after index: Int) -> Int {
    var low = 0, high = ranges.count
    while low < high {
      let middle = (low + high) / 2
      if ranges[middle].upperBound <= index { low = middle + 1 }
      else { high = middle }
    }
    return low
  }

  func repeatedRows(from y: Int) -> Int {
    let next = firstRange(after: y * width)
    guard next < ranges.count else { return height - y }
    return max(1, ranges[next].lowerBound / width - y)
  }

  func containsSample(matching predicate: (Int) -> Bool) throws -> Bool {
    if predicate(implicitIndex) { return true }
    for range in ranges {
      try Task.checkCancellation()
      for index in range {
        if index % 4096 == 0 { try Task.checkCancellation() }
        if predicate(index) { return true }
      }
    }
    return false
  }

  func row(_ y: Int, depth: Int, sample: (Int) -> Float) throws -> [UInt8] {
    let rowStart = y * width, rowEnd = rowStart + width
    let bytesPerSample = depth / 8
    var implicit: [UInt8] = []
    try PSDChannelCodec.append(sample(implicitIndex), depth: depth, to: &implicit)
    var bytes = Array(PSDChannelWriter.repeating(Data(implicit), count: width))
    var index = firstRange(after: rowStart)
    while index < ranges.count, ranges[index].lowerBound < rowEnd {
      try Task.checkCancellation()
      let left = max(rowStart, ranges[index].lowerBound), right = min(rowEnd, ranges[index].upperBound)
      var patch: [UInt8] = []
      patch.reserveCapacity((right - left) * bytesPerSample)
      for position in left..<right {
        if position % 4096 == 0 { try Task.checkCancellation() }
        try PSDChannelCodec.append(sample(position), depth: depth, to: &patch)
      }
      bytes.replaceSubrange((left - rowStart) * bytesPerSample..<(right - rowStart) * bytesPerSample, with: patch)
      index += 1
    }
    return bytes
  }
}
