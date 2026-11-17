import Foundation
import PhotoCraftCore

/// A presentation key retains immutable coverage, never a dense extraction.
struct SelectionOutlineRequest: Equatable, Sendable {
  let mask: SelectionMask
  let region: IntRect?
  let sampleStep: Int
  init(mask: SelectionMask, region: IntRect? = nil, sampleStep: Int = 1) {
    self.mask = mask; self.region = region; self.sampleStep = max(1, sampleStep)
  }
  /// Main-thread admission uses identity only; value comparison stays on the worker.
  func sharesSource(with other: Self) -> Bool {
    region == other.region && sampleStep == other.sampleStep
      && mask.sharesCoverageStorage(with: other.mask)
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.region == rhs.region && lhs.sampleStep == rhs.sampleStep
      && lhs.mask.width == rhs.mask.width && lhs.mask.height == rhs.mask.height
      && lhs.mask.bounds == rhs.mask.bounds && lhs.mask == rhs.mask
  }
}

/// One retained contour per document store. Failed/cancelled builds never replace it.
actor SelectionOutlineCache {
  private struct Entry { let request: SelectionOutlineRequest; let contour: SelectionContour }
  private var entry: Entry?
  private let builder: @Sendable (SelectionOutlineRequest) throws -> SelectionContour
  private(set) var builds = 0
  private(set) var hits = 0
  init(builder: @escaping @Sendable (SelectionOutlineRequest) throws -> SelectionContour = {
    try SelectionOutline.path($0.mask, region: $0.region, sampleStep: $0.sampleStep)
  }) { self.builder = builder }
  func path(for request: SelectionOutlineRequest?) throws -> SelectionContour? {
    try Task.checkCancellation()
    guard let request else { entry = nil; return nil }
    if let old = entry, old.request == request {
      // Adopt an equal newly allocated coverage plane for later identity-fast hits.
      entry = Entry(request: request, contour: old.contour); hits += 1
      return old.contour
    }
    let contour = try builder(request)
    try Task.checkCancellation()
    entry = Entry(request: request, contour: contour); builds += 1
    return contour
  }
}
