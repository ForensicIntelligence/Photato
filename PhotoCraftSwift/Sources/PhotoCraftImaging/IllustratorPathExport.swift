import Foundation
import PhotoCraftCore
import UniformTypeIdentifiers

/// Geometry-only Illustrator interchange. No raster, appearance, profile or artwork is sampled.
/// The Illustrator path operators are documented by Adobe; Photoshop path annotations
/// and physical sizing are qualified separately with owned Photoshop 2026 exports.
public enum IllustratorPathExport {
  public static let contentType = UTType(importedAs: "com.adobe.illustrator.ai-image", conformingTo: .data)
  public static let mediaType = "application/postscript"
  public static let maximumBytes = 32 * 1024 * 1024
  public enum Target: String, Codable, CaseIterable, Hashable, Sendable {
    case documentBounds, all, saved, shape, vectorMask
  }
  public struct Selection: Codable, Equatable, Hashable, Sendable {
    public var target: Target
    public var id: UUID?
    public init(_ target: Target, id: UUID? = nil) { self.target = target; self.id = id }
    public func validate() throws {
      guard (target == .all || target == .documentBounds) == (id == nil) else {
        throw CraftError.invalid("Choose document bounds, all paths, or one existing path identifier.")
      }
    }
  }
  public struct Source: Equatable, Sendable {
    public let selection: Selection
    public let name: String
    public let path: VectorPath
  }
  public struct Choice: Equatable, Sendable {
    public let selection: Selection
    public let name: String
  }
  /// Photoshop offers saved/Work Paths and the active layer's vector target,
  /// rather than silently exporting vector masks belonging to inactive layers.
  public static func sources(_ document: CraftDocument) throws -> [Source] {
    var result = (document.paths ?? []).map {
      Source(selection: .init(.saved, id: $0.id), name: $0.isWorkPath ? "Work Path" : $0.name, path: $0.path)
    }
    if let layer = document.layers.first(where: { $0.id == document.activeLayerID }) {
      if let path = try layer.shapePath() {
        result.append(.init(selection: .init(.shape, id: layer.id), name: layer.name + " Shape Path", path: path))
      }
      if let mask = layer.vectorMask {
        result.append(.init(selection: .init(.vectorMask, id: layer.id), name: layer.name + " Vector Mask", path: mask.path))
      }
    }
    return result
  }
  public static func choices(_ document: CraftDocument) throws -> [Choice] {
    let paths = try sources(document)
    return [.init(selection: .init(.documentBounds), name: "Document Bounds")]
      + (paths.count > 1 ? [.init(selection: .init(.all), name: "All Paths")] : [])
      + paths.map { .init(selection: $0.selection, name: $0.name) }
  }
  public static func defaultSelection(_ document: CraftDocument) throws -> Selection {
    let paths = try sources(document)
    return paths.count > 1 ? .init(.all) : paths.first?.selection ?? .init(.documentBounds)
  }
  public static func encoded(_ document: CraftDocument, selection: Selection? = nil,
    title: String = "Paths.ai") throws -> Data {
    try document.validate(); try Task.checkCancellation()
    let selected = try selection ?? defaultSelection(document)
    try selected.validate()
    guard !title.isEmpty, title.utf8.count <= 1024,
      !title.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
      throw CraftError.invalid("The Illustrator filename must contain 1–1024 UTF-8 bytes without control characters.")
    }
    let available = try sources(document), paths: [Source]
    switch selected.target {
    case .documentBounds: paths = [] // The reference writes crop marks, without a rectangle contour.
    case .all: paths = available
    default:
      guard let path = available.first(where: { $0.selection == selected }) else {
        throw CraftError.invalid("The chosen path is no longer available in this document.")
      }
      paths = [path]
    }
    let scale = 72 / document.pixelsPerInch
    let width = Double(document.width) * scale, height = Double(document.height) * scale
    guard scale.isFinite, scale > 0, width.isFinite, height.isFinite else {
      throw CraftError.invalid("The document has invalid physical dimensions.")
    }
    func compact(_ number: Double) -> String { String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), number) }
    let bounds = "0 0 \(compact(width)) \(compact(height))"
    var text = "%!PS-Adobe-2.0\r%%Creator: Photato Pen Path Export\r%%Title: (\(escaped(title)))\r"
    text += "%%DocumentNeededResources: procset Adobe_packedarray 2.0 0\r%%+ procset Adobe_IllustratorA_AI3 1.0 1\r"
    text += "%%ColorUsage: Black&White\r%%BoundingBox: 0 0 \(compact(ceil(width))) \(compact(ceil(height)))\r"
    text += "%%HiResBoundingBox: \(bounds)\r%AI3_Cropmarks: \(bounds)\r%%DocumentPreview: None\r%%EndComments\r"
    // References to public Illustrator interpreter resources; no Adobe procset code is embedded.
    text += "%%BeginProlog\r%%IncludeResource: procset Adobe_packedarray 2.0 0\rAdobe_packedarray /initialize get exec\r"
    text += "%%IncludeResource: procset Adobe_IllustratorA_AI3 1.0 1\r%%EndProlog\r%%BeginSetup\r"
    text += "Adobe_IllustratorA_AI3 /initialize get exec\rn\r%%EndSetup\r0.0 0.0 0.0 1.0 k\r0 i 0 J 0 j 1 w 4 M []0 d\r%%Note:\r"
    func coordinate(_ value: Double) -> String { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value) }
    func point(_ p: PathPoint) -> String { "\(coordinate(p.x * scale)) \(coordinate((Double(document.height) - p.y) * scale))" }
    for source in paths {
      try Task.checkCancellation(); let path = source.path; try path.validate()
      // Photoshop paths use Even-Odd. Preserve a native Nonzero region when the
      // two rules differ; otherwise use the reference's canonical Even-Odd form.
      let evenOdd: Bool
      if path.fillRule == .evenOdd { evenOdd = true }
      else { evenOdd = !(try VectorPathGeometry.fillRulesDiffer(path)) }
      text += "%Adobe_Photoshop_Path_Begin:<< /defaultFill \(path.inverted ? "true" : "false") >>\r"
      var groupOpen = false
      for component in path.components where !component.knots.isEmpty {
        try Task.checkCancellation()
        if !groupOpen || component.operation != .join {
          if groupOpen { text += "*U\r" }
          let operation: String
          switch component.operation {
          case .combine, .join: operation = "union"
          case .subtract: operation = "subtract"
          case .intersect: operation = "intersect"
          case .exclude: operation = "xor /defaultFill false"
          }
          text += "*u\r%AI3_Note:<< /operation /\(operation) >>\r\(evenOdd ? 1 : 0) XR\r"
          groupOpen = true
        }
        let knots = component.knots
        text += point(knots[0].anchor) + " m\r"
        let segments = component.closed ? knots.count : knots.count - 1
        if segments > 0 {
          for i in 0..<segments {
            let a = knots[i], b = knots[(i + 1) % knots.count]
            if a.outgoing == a.anchor && b.incoming == b.anchor {
              text += point(b.anchor) + (b.smooth ? " l\r" : " L\r")
            } else {
              text += point(a.outgoing) + " " + point(b.incoming) + " " + point(b.anchor) + (b.smooth ? " c\r" : " C\r")
            }
          }
        }
        text += component.closed ? "n\r" : "N\r"
        guard text.utf8.count <= maximumBytes else { throw CraftError.invalid("Illustrator path output exceeds 32 MiB.") }
      }
      if groupOpen { text += "*U\r" }
      text += "%Adobe_Photoshop_Path_End\r"
    }
    text += "%%Trailer\r%%EOF\r"
    try Task.checkCancellation()
    guard text.utf8.count <= maximumBytes else { throw CraftError.invalid("Illustrator path output exceeds 32 MiB.") }
    return Data(text.utf8)
  }
  private static func escaped(_ string: String) -> String {
    string.utf8.map { value in
      switch value {
      case 40, 41, 92: return "\\" + String(UnicodeScalar(value))
      case 32...126: return String(UnicodeScalar(value))
      default: return String(format: "\\%03o", Int(value))
      }
    }.joined()
  }
}
