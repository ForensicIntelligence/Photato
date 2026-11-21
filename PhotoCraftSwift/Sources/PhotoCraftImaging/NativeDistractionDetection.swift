import Foundation
import PhotoCraftCore
import Vision

public struct NativeDistractionDetection: RemoveDistractionDetecting {
  private let proposals: CoreMLDistractionDetector?

  public init(model: CoreMLDistractionDetector? = nil) { proposals = model }

  public func detectDistractions(in input: Surface) async throws -> [RemoveDistractionMark] {
    let foreground = VisionForegroundDetector()
    let objects = try await foreground.masksIfPresent(for: input)
    let candidates = try await proposals?.proposals(in: input) ?? []
    try Task.checkCancellation()
    var marks: [RemoveDistractionMark] = []
    var protected: [IntRect] = candidates.compactMap { $0.category == nil ? $0.bounds : nil }
    var classifications: [Int: String] = [:]
    for object in objects {
      guard let bounds = object.mask.bounds else { continue }
      if let label = try classify(object, in: input) {
        classifications[object.instanceID] = label
        if Self.isSubject(label) { protected.append(bounds) }
      }
    }
    // A large unnamed instance can contain several nearby objects. Hold it back
    // from the fallback review while still allowing independently refined objects.
    let central = objects.filter { object in
      guard classifications[object.instanceID] == nil else { return false }
      guard let b = object.mask.bounds else { return false }
      return b.contains(input.width / 2, input.height / 2) && b.width * b.height >= input.width * input.height / 9
    }.max { a, b in
      guard let ab = a.mask.bounds, let bb = b.mask.bounds else { return false }
      return ab.width * ab.height < bb.width * bb.height
    }
    let uncertainSubject = protected.isEmpty ? central : nil

    var covered = Set<Int>()
    for candidate in candidates {
      try Task.checkCancellation()
      guard let category = candidate.category else { continue }
      let matches = objects.compactMap { object -> (DetectedObjectMask, Double)? in
        guard let bounds = object.mask.bounds else { return nil }
        let agreement = CoreMLDistractionDetector.overlap(bounds, candidate.bounds)
        // A loose match can merge a bin with the bench beside it under one label.
        return agreement >= 0.58 ? (object, agreement) : nil
      }
      let selected = matches.max { $0.1 < $1.1 }?.0
      if let selected, !covered.insert(selected.instanceID).inserted { continue }
      let mask: SelectionMask?
      if let selected { mask = selected.mask }
      else { mask = try await refine(candidate, in: input, using: foreground) }
      if let mask, let coverage = try Self.reviewCoverage(mask, from: protected) {
        marks.append(.init(category: category, mask: coverage))
      }
    }
    for object in objects where !covered.contains(object.instanceID) && object.instanceID != uncertainSubject?.instanceID {
      try Task.checkCancellation()
      let label = classifications[object.instanceID]
      if let label, Self.isSubject(label) { continue }
      let category = label.map(Self.category) ?? .unrecognizedObjects
      if let bounds = object.mask.bounds, marks.contains(where: { mark in
        guard let local = mark.mask.bounds else { return false }
        return CoreMLDistractionDetector.overlap(bounds, local) > 0.32
      }) { continue }
      if let coverage = try Self.reviewCoverage(object.mask, from: protected) {
        marks.append(.init(category: category, mask: coverage))
      }
    }
    let dustExclusions = protected + [uncertainSubject?.mask.bounds].compactMap { $0 }
    if let dust = try DistractionDustDetection.detect(input, protected: dustExclusions) { marks.append(dust) }
    return marks
  }

  private func refine(_ proposal: DistractionProposal, in image: Surface,
    using detector: VisionForegroundDetector) async throws -> SelectionMask? {
    let rect = proposal.bounds
    let padX = max(3, rect.width / 10), padY = max(3, rect.height / 10)
    let crop = IntRect(x: rect.x - padX, y: rect.y - padY, width: rect.width + padX * 2, height: rect.height + padY * 2)
      .clipped(toWidth: image.width, height: image.height)
    let cropped = try image.cropped(to: crop)
    let objects = try await detector.masksIfPresent(for: cropped)
    let supported = objects.compactMap { found -> (SelectionMask, Double)? in
      guard let b = found.mask.bounds else { return nil }
      let located = IntRect(x: b.x + crop.x, y: b.y + crop.y, width: b.width, height: b.height)
      let agreement = CoreMLDistractionDetector.overlap(located, rect)
      return agreement >= 0.30 ? (found.mask, agreement) : nil
    }
    if let localized = supported.max(by: { $0.1 < $1.1 })?.0 {
      return try SelectionMask.sampledCoverage(width: image.width, height: image.height, regions: [crop]) { x, y in
        localized.byte(at: (y - crop.y) * crop.width + x - crop.x)
      }
    }
    // Vision can miss narrow objects even inside a tight crop. Keep a bounded
    // geometric mark only for strongly classified, slender poles for the user to review.
    if proposal.category == .poles, proposal.confidence >= 0.45, rect.height >= rect.width * 3 {
      return try SelectionMask.make(.rectangle(rect), width: image.width, height: image.height, antiAlias: false)
    }
    return nil
  }

  private func classify(_ object: DetectedObjectMask, in input: Surface) throws -> String? {
    guard let bounds = object.mask.bounds else { return nil }
    var cutout = try input.cropped(to: bounds)
    try cutout.mapPixels(in: IntRect(x: 0, y: 0, width: bounds.width, height: bounds.height)) { x, y, p in
      let alpha = object.mask.coverage(x: bounds.x + x, y: bounds.y + y)
      return Pixel(p.r * alpha + 0.5 * (1 - alpha), p.g * alpha + 0.5 * (1 - alpha), p.b * alpha + 0.5 * (1 - alpha))
    }
    let request = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(cgImage: try RasterIO.displayImage(cutout))
    try handler.perform([request]); try Task.checkCancellation()
    let predictions = request.results ?? []
    // Vision may return a parent class e.g. structure before a useful specific term.
    if let subject = predictions.first(where: { $0.confidence >= 0.37 && Self.isSubject($0.identifier) }) {
      return subject.identifier
    }
    if let specific = predictions.first(where: { $0.confidence >= 0.32 && Self.category($0.identifier) != .unrecognizedObjects }) {
      return specific.identifier
    }
    return nil
  }

  private static func category(_ name: String) -> RemoveDistractionCategory {
    switch name {
    case "trash_can", "rubbish", "litter", "bottle", "traffic_cone", "cardboard_box": .visualClutter
    case "pole", "flagpole", "lamppost", "street_light", "bollard": .poles
    case "plant", "decorative_plant", "shrub", "tree", "eucalyptus_tree", "maple_tree", "oak_tree", "palm_tree": .vegetation
    case "car", "vehicle", "truck", "bus", "motorcycle", "bicycle", "bench", "street_sign", "backpack", "luggage": .identifiedObjects
    default: .unrecognizedObjects
    }
  }

  private static func isSubject(_ name: String) -> Bool {
    ["person", "human", "dog", "cat", "animal", "bird"].contains(name)
  }

  static func reviewCoverage(_ mask: SelectionMask, from protected: [IntRect]) throws -> SelectionMask? {
    guard let eligible = try protect(mask, from: protected) else { return nil }
    // Include a small repair margin in the visible review so users can refine it
    // before applying. Protect neighboring subjects again after expansion.
    let expanded = try SelectionModification(.expand, amount: 3).applied(to: eligible)
    return try protect(expanded, from: protected)
  }

  private static func protect(_ mask: SelectionMask, from protected: [IntRect]) throws -> SelectionMask? {
    guard let bounds = mask.bounds else { return nil }
    // Reject a candidate primarily on the protected subject. Clip lesser overlaps
    // explicitly so a neighbouring object can still be reviewed and removed.
    let covered = protected.filter { CoreMLDistractionDetector.intersection($0, bounds).width > 0
      && CoreMLDistractionDetector.intersection($0, bounds).height > 0 }
    guard !covered.isEmpty else { return mask }
    var total = 0, retained = 0
    let result = try SelectionMask.sampledCoverage(width: mask.width, height: mask.height, regions: [bounds]) { x, y in
      let value = mask.byte(at: y * mask.width + x)
      total += Int(value)
      if covered.contains(where: { $0.contains(x, y) }) { return 0 }
      retained += Int(value)
      return value
    }
    return retained * 2 > total ? result : nil
  }
}
