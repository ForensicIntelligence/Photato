import Foundation

/// Named template inputs. Several layer bindings may share one name and kind.
/// Behaviour originates in PhotoCraft's variables module and public Photoshop help.
public enum VariableKind: String, Codable, CaseIterable, Sendable {
  case visibility, textReplacement, pixelReplacement
}
public enum VariablePixelMethod: String, Codable, CaseIterable, Sendable {
  case fit, fill, asIs, conform
}
public struct VariablePixelOptions: Codable, Equatable, Sendable {
  public var method: VariablePixelMethod = .fit
  public var alignment: CanvasAnchor = .center
  public var clipToBounds = false
  public init() {}
}
/// Original replacement rectangle, independent of the last replacement's aspect ratio.
public struct VariablePixelFrame: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var transform: Transform2D
  public init(layer: Layer) throws {
    guard case .raster(let pixels) = layer.content else {
      throw CraftError.invalid("Pixel Replacement requires a pixel layer.")
    }
    let bounds = try pixels.contentBounds() ?? IntRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
    width = bounds.width; height = bounds.height
    transform = layer.coordinateTransform * .translation(Double(bounds.x), Double(bounds.y))
  }
  func validate() throws {
    _ = try Surface(width: width, height: height)
    _ = try transform.bounds(width: width, height: height)
  }
}
public struct VariableDefinition: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var layerID: UUID
  public var kind: VariableKind
  public var pixelOptions: VariablePixelOptions?
  public var pixelFrame: VariablePixelFrame?
  public init(id: UUID = UUID(), name: String, layerID: UUID, kind: VariableKind,
              pixelOptions: VariablePixelOptions? = nil) {
    self.id = id; self.name = name; self.layerID = layerID; self.kind = kind
    self.pixelOptions = kind == .pixelReplacement ? pixelOptions ?? .init() : nil
  }
  public static func validName(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 128 else { return false }
    let scalars = value.unicodeScalars
    guard let first = scalars.first,
          CharacterSet.letters.contains(first) || first == "_" || first == ":" else { return false }
    return scalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "_:.-".unicodeScalars.contains($0) }
  }
  public func supports(_ layer: Layer) -> Bool {
    switch kind {
    case .visibility: return true
    case .textReplacement: if case .text = layer.content { return true }; return false
    case .pixelReplacement:
      if case .raster = layer.content { return layer.smartObject == nil && layer.video == nil && layer.nativeMode == nil }
      return false
    }
  }
}
public enum VariableValue: Codable, Equatable, Sendable {
  case visibility(Bool)
  case text(String)
  /// nil is Photoshop's Do Not Replace, not a request to restore old pixels.
  case pixels(UUID?)
  public var kind: VariableKind {
    switch self { case .visibility: .visibility; case .text: .textReplacement; case .pixels: .pixelReplacement }
  }
}
public struct VariableDataSet: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var values: [String: VariableValue]
  public init(id: UUID = UUID(), name: String, values: [String: VariableValue] = [:]) {
    self.id = id; self.name = name; self.values = values
  }
}
/// Imported image pixels are embedded so a saved template does not depend on a path.
/// Their working profile is explicit; profile conversion belongs to the imaging layer.
public struct VariableImage: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var pixels: Surface
  public var workingICC: Data?
  public init(id: UUID = UUID(), name: String, pixels: Surface, workingICC: Data? = nil) {
    self.id = id; self.name = name; self.pixels = pixels; self.workingICC = workingICC
  }
  public var estimatedBytes: Int { pixels.allocatedBytes + name.utf8.count + (workingICC?.count ?? 0) + 256 }
}
public struct DataDrivenGraphics: Codable, Equatable, Sendable {
  public static let maximumDefinitions = 1536
  public static let maximumDataSets = 1000
  public static let maximumValues = 65_536
  public static let maximumImages = 256
  public static let maximumMetadataBytes = 16 * 1024 * 1024
  public static let maximumImageBytes = 512 * 1024 * 1024
  public var definitions: [VariableDefinition] = []
  public var dataSets: [VariableDataSet] = []
  public var images: [VariableImage] = []
  public var activeDataSetID: UUID?
  public init() {}
  public var isEmpty: Bool { definitions.isEmpty && dataSets.isEmpty && images.isEmpty }
  public var metadataBytes: Int {
    definitions.reduce(0) { $0 + $1.name.utf8.count + 256 }
      + dataSets.reduce(0) { sum, row in
        sum + row.name.utf8.count + 128 + row.values.reduce(0) { total, pair in
          let text: Int
          if case .text(let value) = pair.value { text = value.utf8.count } else { text = 64 }
          return total + pair.key.utf8.count + text + 64
        }
      }
  }
  public var estimatedBytes: Int { metadataBytes + images.reduce(0) { $0 + $1.estimatedBytes } }
  public var variableNames: [String] {
    var seen = Set<String>()
    return definitions.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
  }
  public func validate(in document: CraftDocument) throws {
    guard definitions.count <= Self.maximumDefinitions, dataSets.count <= Self.maximumDataSets,
          images.count <= Self.maximumImages,
          Set(definitions.map(\.id)).count == definitions.count,
          Set(dataSets.map(\.id)).count == dataSets.count,
          Set(dataSets.map(\.name)).count == dataSets.count,
          Set(images.map(\.id)).count == images.count,
          !definitions.isEmpty || dataSets.isEmpty,
          dataSets.reduce(0, { $0 + $1.values.count }) <= Self.maximumValues,
          metadataBytes <= Self.maximumMetadataBytes,
          images.reduce(0, { $0 + $1.estimatedBytes }) <= Self.maximumImageBytes,
          activeDataSetID == nil || dataSets.contains(where: { $0.id == activeDataSetID }) else {
      throw CraftError.invalid("Invalid or oversized variables and data sets.")
    }
    var names: [String: VariableKind] = [:], bindings = Set<String>()
    for definition in definitions {
      guard VariableDefinition.validName(definition.name),
            let layer = document.layers.first(where: { $0.id == definition.layerID }), definition.supports(layer),
            bindings.insert("\(definition.layerID):\(definition.kind.rawValue)").inserted,
            names[definition.name] == nil || names[definition.name] == definition.kind else {
        throw CraftError.invalid("A variable needs a compatible layer, valid name and unique layer/type binding. Linked names must use the same type.")
      }
      names[definition.name] = definition.kind
      if definition.kind == .pixelReplacement {
        guard definition.pixelOptions != nil, let frame = definition.pixelFrame else {
          throw CraftError.invalid("Pixel Replacement needs its original bounding box.")
        }
        try frame.validate()
      } else if definition.pixelOptions != nil || definition.pixelFrame != nil {
        throw CraftError.invalid("Only pixel variables have placement options.")
      }
    }
    let imageIDs = Set(images.map(\.id))
    for image in images {
      guard !image.name.isEmpty, image.name.utf8.count <= 1024 else { throw CraftError.invalid("Invalid replacement image name.") }
      try image.pixels.validated()
      if let profile = image.workingICC { try ICCProfile.validate(profile, linear: image.pixels.depth == .f32) }
    }
    for row in dataSets {
      guard !row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, row.name.utf8.count <= 256 else {
        throw CraftError.invalid("Data set names must contain 1–256 UTF-8 bytes.")
      }
      for (name, value) in row.values {
        guard names[name] == value.kind else { throw CraftError.invalid("Unknown variable or incorrect value type: \(name).") }
        if case .text(let text) = value, text.utf16.count > 100_000 { throw CraftError.invalid("Replacement text exceeds the type limit.") }
        if case .pixels(let id?) = value, !imageIDs.contains(id) { throw CraftError.invalid("A replacement image is missing.") }
      }
    }
  }
}
