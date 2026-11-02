import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PhotoCraftCore

/// Immutable asset preparation shared by native export and published output adapters.
public enum ImageAssetSelection {
  public enum Crop: String, Codable, CaseIterable, Hashable, Sendable { case documentBounds = "document_bounds", layerBounds = "layer_bounds", trim = "trim_to_transparency" }
  public static func document(_ source: CraftDocument, ids: [UUID]? = nil, crop: Crop = .documentBounds, includingAncestors: Bool = false) throws -> CraftDocument {
    try source.validate(); try Task.checkCancellation()
    var result = source
    if let ids {
      guard source.animation == nil, source.videoTimeline == nil else { throw CraftError.unsupported("Use the timeline/frame export workflow for individual temporal layers.") }
      guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ id in source.layers.contains { $0.id == id } }) else { throw CraftError.invalid("Choose distinct existing export layers.") }
      guard ids.count == 1 || crop != .layerBounds else { throw CraftError.invalid("Layer bounds requires exactly one layer or group.") }
      if ids.count == 1, let board = source.artboards.first(where: { $0.id == ids[0] }), crop != .documentBounds {
        result = try source.extractedArtboard(board.id)
      } else {
        var included = ids.reduce(into: Set<UUID>()) { $0.formUnion(source.subtreeIDs($1)) }
        var forced = Set(ids)
        if includingAncestors {
          for id in ids { let ancestors = source.ancestors(of:id).map(\.id); included.formUnion(ancestors); forced.formUnion(ancestors) }
        }
        result.layers = source.layers.filter { included.contains($0.id) };LayerLinks.prune(in:&result)
        for i in result.layers.indices {
          if let parent = result.layers[i].parentID, !included.contains(parent) { result.layers[i].parentID = nil }
          if forced.contains(result.layers[i].id) { result.layers[i].visible = true; result.layers[i].clipped = false }
        }
        result.activeLayerID = result.layers.last?.id
        clearDocumentOnlyState(&result)
        if crop == .layerBounds, let layer = source.layers.first(where: { $0.id == ids[0] }) {
          let canvas = IntRect(x:0,y:0,width:source.width,height:source.height)
          let box = try layer.isCanvasFill ? canvas : Renderer.layoutBounds(layer, in: source, stored: true) ?? canvas
          result = try reframed(result, bounds: box)
        }
      }
    } else if crop == .layerBounds { throw CraftError.invalid("Layer bounds requires exactly one layer or group.") }
    clearDocumentOnlyState(&result)
    if crop == .trim {
      let box = try Renderer.composite(result).contentBounds() ?? IntRect(x: 0, y: 0, width: 1, height: 1)
      result = try reframed(result, bounds: box)
    }
    try result.validate(); return result
  }
  static func clearDocumentOnlyState(_ result: inout CraftDocument) {
    if result.layerComps != nil || result.sourceMetadata?["psdResources"] != nil {
      var metadata = result.sourceMetadata ?? [:]; metadata["psdLayerCompsCleared"] = Data([1]); result.sourceMetadata = metadata
    }
    result.layerComps = nil; result.variables = nil; result.selection = nil; result.selectionMask = nil
    result.alphaChannels = nil; result.quickMask = nil; result.guides = []
  }
  public static func reframed(_ source: CraftDocument, bounds: IntRect) throws -> CraftDocument {
    guard bounds.width > 0, bounds.height > 0 else { throw CraftError.invalid("Export bounds are empty.") }
    var result = source
    let delta = Transform2D.translation(-Double(bounds.x), -Double(bounds.y))
    result.layers = try source.layers.map { layer in
      var moved = layer
      // This changes the coordinate frame, not the artwork's transform or sample grid.
      // Re-rendering transformLayer here would resample an existing affine a second time.
      moved.x -= bounds.x; moved.y -= bounds.y
      if case .text(var text) = moved.content {
        text.layoutWidth = text.layoutWidth ?? source.width; text.layoutHeight = text.layoutHeight ?? source.height; moved.content = .text(text)
      }
      moved.smartFilters?.transformPuppetPins(delta); moved.smartFilters?.transformPerspectivePlanes(delta)
      if let stack = layer.smartFilters { moved.smartFilters?.maskProperties.transform = delta * stack.maskProperties.transform }
      if case .patternFill(var fill) = moved.content { try fill.transform(by: delta); moved.content = .patternFill(fill) }
      if case .gradientFill(var fill) = moved.content { try fill.transform(by: delta); moved.content = .gradientFill(fill) }
      if let mask = layer.vectorMask { moved.vectorMask?.path = mask.path.transformed(delta) }
      return moved
    }
    result.width = bounds.width; result.height = bounds.height; result.artboardOrigin = nil; result.paths = nil
    clearDocumentOnlyState(&result); try result.validate(); return result
  }
}

public struct ImageExportSettings: Codable, Equatable, Sendable {
  public enum Format: String, Codable, CaseIterable, Sendable { case png, jpeg, gif }
  public enum Target: String, Codable, CaseIterable, Sendable { case document, layers, artboards }
  public enum Metadata: String, Codable, CaseIterable, Sendable { case none, copyright }
  public struct Scale: Codable, Equatable, Sendable {
    public var factor: Double
    public var suffix: String
    public init(_ factor: Double = 1, suffix: String = "") { self.factor = factor; self.suffix = suffix }
  }
  public var format: Format = .png
  public var target: Target = .document
  public var ids: [UUID] = []
  public var scales = [Scale()]
  public var width: Int?
  public var height: Int?
  public var canvasWidth: Int?
  public var canvasHeight: Int?
  public var resampling: Resampling = .bicubic
  public var transparency = true
  public var quality = 100
  public var convertToSRGB = true
  public var embedProfile = false
  public var metadata: Metadata = .none
  public var trim = false
  public init() {}
  public func validate() throws {
    guard format != .gif || (!embedProfile && metadata == .none && convertToSRGB) else { throw CraftError.unsupported("GIF exports require sRGB with no embedded profile or descriptive metadata.") }
    guard !scales.isEmpty, scales.count <= 16, ids.count <= 256, Set(ids).count == ids.count,
      Set(scales.map(\.suffix)).count == scales.count, (0...100).contains(quality),
      scales.allSatisfy({ $0.factor.isFinite && (0.01...1000).contains($0.factor) && $0.suffix.utf8.count <= 64 && $0.suffix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-.@ ".unicodeScalars.contains($0) }) }),
      [width, height, canvasWidth, canvasHeight].compactMap({ $0 }).allSatisfy({ (1...Surface.maxDimension).contains($0) }),
      (target == .document ? ids.isEmpty : !ids.isEmpty) else { throw CraftError.invalid("Invalid export target, dimensions, scales, suffixes or quality.") }
  }
}
public struct ImageExportFile: Sendable {
  public let name: String
  public let data: Data
  public let width: Int
  public let height: Int
  public let sourceID: UUID?
  public let scale: Double
}
public enum ImageAssetExport {
  public static let maximumBytes = 128 * 1024 * 1024
  public static func assets(_ source: CraftDocument, settings: ImageExportSettings) throws -> [(UUID?, String, CraftDocument)] {
    try settings.validate()
    if settings.target == .document { return [(nil, source.name, try ImageAssetSelection.document(source, crop: settings.trim ? .trim : .documentBounds))] }
    return try settings.ids.map { id in
      guard let layer = source.layers.first(where: { $0.id == id }), settings.target != .artboards || layer.artboardBounds != nil else { throw CraftError.invalid("An export asset no longer exists.") }
      return (id, layer.name, try ImageAssetSelection.document(source, ids: [id], crop: settings.trim ? .trim : .layerBounds, includingAncestors: true))
    }
  }
  public static func render(_ source: CraftDocument, settings: ImageExportSettings, maximumBytes: Int = maximumBytes) throws -> [ImageExportFile] {
    guard (1...Self.maximumBytes).contains(maximumBytes) else { throw CraftError.invalid("Invalid export byte budget.") }
    let inputs = try assets(source, settings: settings)
    var files: [ImageExportFile] = [], names = Set<String>(), total = 0
    for (id, name, document) in inputs {
      try Task.checkCancellation()
      let composite = try Renderer.composite(document)
      for scale in settings.scales {
        let prepared = try prepare(composite, document: document, settings: settings, scale: scale.factor)
        let bytes = try encoded(prepared, settings: settings)
        guard bytes.count <= maximumBytes - total else { throw CraftError.invalid("Export exceeds its encoded byte budget.") }; total += bytes.count
        let ext = settings.format == .jpeg ? "jpg" : settings.format.rawValue
        var base = safeName(name), candidate = base + scale.suffix + "." + ext, counter = 2
        while !names.insert(candidate.lowercased()).inserted { base = safeName(name) + "-\(counter)"; candidate = base + scale.suffix + "." + ext; counter += 1 }
        files.append(.init(name: candidate, data: bytes, width: prepared.width, height: prepared.height, sourceID: id, scale: scale.factor))
      }
    }
    try Task.checkCancellation(); return files
  }
  public static func safeName(_ value: String) -> String {
    let name = String(value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) ? "_" : String($0) }.joined().prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    var bounded = ""
    for scalar in name.unicodeScalars { if bounded.utf8.count + scalar.utf8.count > 150 { break }; bounded.unicodeScalars.append(scalar) }
    return bounded.isEmpty || bounded == "." || bounded == ".." ? "Untitled" : bounded
  }
  public static func prepare(_ surface: Surface, document: CraftDocument, settings: ImageExportSettings, scale: Double = 1) throws -> CraftDocument {
    try settings.validate()
    func dimension(_ value: Double) throws -> Int {
      guard value.isFinite, value >= 0.5, value <= Double(Surface.maxDimension) + 0.49 else { throw CraftError.invalid("Scaled export dimensions exceed the document limit.") }; return max(1, Int(value.rounded()))
    }
    let ratio = Double(surface.width) / Double(surface.height)
    let baseW = settings.width.map(Double.init) ?? settings.height.map { Double($0) * ratio } ?? Double(surface.width)
    let baseH = settings.height.map(Double.init) ?? settings.width.map { Double($0) / ratio } ?? Double(surface.height)
    let w = try dimension(baseW * scale), h = try dimension(baseH * scale)
    let cw = try dimension((settings.canvasWidth.map(Double.init) ?? baseW) * scale), ch = try dimension((settings.canvasHeight.map(Double.init) ?? baseH) * scale)
    var output = try CraftDocument(width: cw, height: ch, depth: .u8, name: document.name)
    if !settings.convertToSRGB {
      let space = try ColorManagement.space(for: document)
      // RGB32 profiles must be converted to an encoded RGB space for an 8-bit web asset.
      if document.depth == .f32, document.workingICC != nil { throw CraftError.unsupported("Convert this custom RGB32 profile to sRGB for web export.") }
      output.workingICC = document.depth == .f32 ? nil : space.copyICCData() as Data?; output.sourceICC = output.workingICC
    }
    output.profileIsUntagged = !settings.embedProfile
    var pixels = surface
    if w != surface.width || h != surface.height {
      pixels = try RasterGeometry.render(pixels, transform: .scale(Double(w)/Double(surface.width), Double(h)/Double(surface.height)), bounds: .init(x: 0, y: 0, width: w, height: h), method: settings.resampling, clampEdges: true)
    }
    if cw != w || ch != h {
      pixels = try RasterGeometry.render(pixels, transform: .translation(floor(Double(cw-w)/2), floor(Double(ch-h)/2)), bounds: .init(x: 0, y: 0, width: cw, height: ch), method: .nearest)
    }
    pixels = try ColorManagement.converted(pixels, from: document, to: output)
    if !settings.transparency || settings.format == .jpeg {
      pixels.mapPixels { _, _, p in Pixel(p.r*p.a+1-p.a, p.g*p.a+1-p.a, p.b*p.a+1-p.a, 1) }
    }
    output.layers[0].name = "Export"; output.layers[0].content = .raster(pixels)
    if settings.metadata == .copyright {
      let original = try FileInfoMetadata.read(document); var info = FileInformation()
      info.author = original.author; info.copyright = original.copyright; info.copyrightStatus = original.copyrightStatus; info.copyrightUrl = original.copyrightUrl
      output = try FileInfoMetadata.applying(info, fields: ["author", "copyright", "copyrightStatus", "copyrightUrl"], to: output)
    }
    return output
  }
  public static func encoded(_ document: CraftDocument, settings: ImageExportSettings) throws -> Data {
    if settings.format == .gif {
      let bytes = NSMutableData(); guard let destination = CGImageDestinationCreateWithData(bytes, UTType.gif.identifier as CFString, 1, nil) else { throw CraftError.unavailable("GIF export is unavailable.") }
      var pixels = try Renderer.composite(document); pixels.mapPixels { _, _, p in p.a >= 0.5 ? Pixel(p.r,p.g,p.b,1) : .clear }
      CGImageDestinationAddImage(destination, try ColorManagement.image(pixels, in: document), nil)
      guard CGImageDestinationFinalize(destination) else { throw CraftError.invalid("Could not encode GIF.") }; return bytes as Data
    }
    var options = RasterEncodingOptions()
    if settings.format == .jpeg { options.jpegQuality = Int((Double(settings.quality)*12/100).rounded()); options.jpegEmbedProfile = settings.embedProfile }
    let encoded = try RasterIO.encoded(document, type: settings.format == .png ? .png : .jpeg, options: options)
    return settings.metadata == .none ? try withoutMetadata(encoded, format: settings.format) : encoded
  }
  static func withoutMetadata(_ data: Data, format: ImageExportSettings.Format) throws -> Data {
    if format == .jpeg {
      let bytes = [UInt8](data); var output = Data([255,216])
      for record in try JPEGContainer.segments(bytes) {
        if [225,237,254].contains(record.marker) { continue }
        output.append(contentsOf: bytes[record.range]); if let entropy = record.entropy { output.append(contentsOf: bytes[entropy]) }
      }
      return output
    }
    guard format == .png, data.starts(with: [137,80,78,71,13,10,26,10]) else { return data }
    var output = Data(data.prefix(8)), offset = 8
    while offset < data.count {
      try Task.checkCancellation()
      guard data.count - offset >= 12 else { throw CraftError.invalid("Truncated generated PNG metadata.") }
      let count = data[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
      guard count <= data.count - offset - 12 else { throw CraftError.invalid("Truncated generated PNG chunk.") }
      let type = String(decoding: data[offset+4..<offset+8], as: UTF8.self)
      if !["eXIf", "iTXt", "tEXt", "zTXt"].contains(type) { output.append(data[offset..<offset+count+12]) }
      offset += count + 12
    }
    return output
  }
}
