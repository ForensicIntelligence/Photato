import Foundation
import PhotoCraftCore

public enum RetouchPreparation {
  public static func sample(_ reference: RecordedRetouchSource, in target: CraftDocument,
    sources: [CraftDocument] = []) throws -> CloneSample {
    try reference.validate()
    let document: CraftDocument
    if let id = reference.documentID {
      let exact = sources.filter { $0.id == id }
      let matches = exact.isEmpty ? sources.filter { $0.name == reference.documentName } : exact
      guard matches.count == 1 else {
        throw CraftError.invalid("The recorded retouch source must be supplied as one unambiguous document.")
      }
      document = matches[0]
    } else { document = target }
    let id = try reference.layer.resolve(in: document)
    let sample = try Renderer.cloneSample(in: document, layerID: id, sampling: reference.sampling,
      ignoreAdjustments: reference.ignoreAdjustments, mask: reference.mask)
    guard reference.convertToTarget && !reference.mask else { return sample }
    var origin = sample.origin; origin?.convertToTarget = true
    return CloneSample(surface: try ColorManagement.converted(sample.surface, from: document, to: target),
      transform: sample.transform, outside: sample.outside, origin: origin)
  }
  public static func command(_ request: RecordedRetouchStroke, in document: CraftDocument,
    sources: [CraftDocument] = []) throws -> Command {
    try Task.checkCancellation(); try request.validate()
    let id = try request.target.resolve(in: document)
    if let tool = request.tool.toning {
      return .toning(id, .init(tool: tool, options: request.toning, brush: request.brush,
        points: request.points, mask: request.mask))
    }
    let source = try sample(request.source!, in: document, sources: sources)
    if let tool = request.tool.focus {
      return .focus(id, .init(tool: tool, options: request.focus, brush: request.brush,
        points: request.points, mask: request.mask, foreground: request.foreground, sample: source))
    }
    if request.tool == .spotHealing {
      return .spotHealing(id, .init(sample: source, brush: request.brush, points: request.points,
        kind: request.spotType, mask: request.mask))
    }
    let clone = CloneStroke(source: source, mapping: request.mapping, brush: request.brush,
      points: request.points, mask: request.mask)
    if request.tool == .healingBrush {
      return .healingBrush(id, .init(stroke: clone,
        destination: try request.destination.map { try sample($0, in: document, sources: sources) }))
    }
    return .cloneStamp(id, clone)
  }
}
