import CryptoKit
import Foundation
import PhotoCraftCore

/// Editable migration from the original Rust application's project format.
/// Unsupported editing data rejects the whole import; previews are never used.
public enum PcraftImport {
  public static let contentTypeIdentifier = "org.photocraft.project"
  public static let mediaType = "application/vnd.photocraft.project"
  public static var sourceSmartFilterCommands:[String]{PcraftSmartFilters.commands}
  public static let unsupportedSourceSmartFilterCommands:[String]=[]
  public static let sourceSmartFilterLimitations=["Source Lens Blur layer-mask depth context", "Native processing-depth restrictions; RGB32 Lens Blur requires a pristine saved cache or inactive stage","Unresolved source Displace references require explicit rebinding for edits","Fractional or out-of-range source controls outside native admission","Unknown source stages/fields, source limits and unqualified exact rerender kernels"]

  public static func read(_ data: Data, rasterByteLimit: Int = 1_073_741_824) throws -> CraftDocument {
    try convert(PcraftProject.read(data, limits: limits(rasterByteLimit)), rasterByteLimit: rasterByteLimit)
  }
  public static func read(_ url: URL, rasterByteLimit: Int = 1_073_741_824) throws -> CraftDocument {
    try convert(PcraftProject.read(url, limits: limits(rasterByteLimit)), rasterByteLimit: rasterByteLimit)
  }
  private static func limits(_ rasterBytes: Int) throws -> PcraftProject.Limits {
    guard (0...1_073_741_824).contains(rasterBytes) else {
      throw CraftError.invalid("Invalid PhotoCraft raster budget.")
    }
    var result = PcraftProject.Limits()
    result.layers = LayerLimits.maximumLayers; result.surfaces = LayerLimits.maximumLayers * 2 + 1
    result.blobBytes = SmartObject.maximumSourceBytes
    result.totalBytes = min(result.totalBytes, rasterBytes + result.manifestBytes + result.blobBytes)
    return result
  }
  public static func dimensions(_ data: Data) throws -> (Int, Int) {
    let manifest = try PcraftZIP(data).read("manifest.json", limit: 16 * 1024 * 1024)
    let root = PcraftNode(try PcraftJSON.parse(manifest), path: "")
    let size = try root.field("document").field("size")
    return try (size.field("width").integer(), size.field("height").integer())
  }
  /// Recognition is bounded to the manifest. Full import still verifies every
  /// referenced tile/blob, schema, editable feature and source-file stability.
  public static func recognizes(_ data: Data) -> Bool {
    guard data.starts(with: [80, 75, 3, 4]), let zip = try? PcraftZIP(data),
      let manifest = try? zip.read("manifest.json", limit: 16 * 1024 * 1024) else { return false }
    return recognizesManifest(manifest)
  }
  public static func recognizes(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      guard let directory = try? PcraftDirectory(url),
        let manifest = try? directory.read("manifest.json", limit: 16 * 1024 * 1024) else { return false }
      return recognizesManifest(manifest)
    }
    guard let file = try? PSDFileSource(url, maximumBytes: PcraftZIP.maximumArchiveBytes),
      let prefix = try? file.bytes(at: 0, count: min(file.count, 4)),
      prefix.starts(with: [80, 75, 3, 4]),
      let bytes = try? file.bytes(at: 0, count: file.count) else { return false }
    return recognizes(bytes)
  }
  private static func recognizesManifest(_ data: Data) -> Bool {
    guard let value = try? PcraftJSON.parse(data) else { return false }
    return value["format_version"]?.uint != nil && value["document"]?["layers"]?.array != nil
      && value["generator"]?.string != nil
  }
  // Keep preparation and final document assembly off the recursive decode stack.
  // The mapper owns the parent value on the heap while originals are opened.
  @inline(never) static func convert(_ project: PcraftProject, rasterByteLimit: Int) throws -> CraftDocument {
    let mapper = try prepare(project, rasterByteLimit: rasterByteLimit)
    let source = try PcraftNode(project.manifest, path: "").field("document")
    let layers = try mapper.layers(source.field("layers"), parent: nil)
    return try finish(mapper, layers: layers)
  }
  @inline(never) private static func prepare(_ project: PcraftProject, rasterByteLimit: Int) throws -> PcraftLayerMapper {
    guard (0...1_073_741_824).contains(rasterByteLimit) else {
      throw CraftError.invalid("Invalid PhotoCraft raster budget.")
    }
    let root = PcraftNode(project.manifest, path: "")
    try root.keys("format_version generator document thumbnail composite")
    let source = try root.field("document")
    try source.keys("id name size resolution_dpi mode depth icc_profile layers channels guides selection metadata global_light paths work_path clipping_path quick_mask patterns color_table duotone layer_comps last_applied_comp last_document_state variables timeline measurement notes text_styles slices")
    guard try source.field("mode").string() == "Rgb" else {
      throw source.unsupported("Only RGB projects are currently editable.")
    }
    let depth = try PcraftSamples.depth(source.field("depth").string())
    let size = try source.field("size")
    try size.keys("width height")
    var document = try CraftDocument(width: size.field("width").integer(),
      height: size.field("height").integer(), depth: depth, name: source.field("name").string())
    let namespace = Data(SHA256.hash(data: project.rawManifest))
    document.id = identity(namespace, role: "document", id: try source.field("id").unsigned())
    document.resolution = Double(try source.field("resolution_dpi").float())
    document.guides = try PcraftGuides.read(source.field("guides"),namespace:namespace)
    let light=try source.field("global_light");try light.keys("angle altitude")
    let sourceLight=GlobalLight(angle:Double(try light.field("angle").float()),altitude:Double(try light.field("altitude").float()));try sourceLight.validate()
    if sourceLight != GlobalLight(){document.globalLight=sourceLight}
    for field in ["layer_comps", "notes"] { try source.defaultValue(field, "[]") }
    for field in ["clipping_path", "color_table", "duotone", "last_applied_comp",
      "last_document_state", "timeline", "slices"] { try source.defaultValue(field, "null") }
    try source.defaultValue("variables", "{\"defs\":[],\"data_sets\":[],\"active\":null}")
    try source.defaultValue("measurement", "{\"scale\":{\"pixel_length\":1,\"logical_length\":1,\"units\":\"pixels\"},\"count_groups\":[],\"active_count_group\":0,\"ruler\":null}")
    try source.defaultValue("text_styles", "{\"character\":[],\"paragraph\":[],\"basic\":{\"id\":0,\"name\":\"Basic Paragraph\",\"para_attrs\":{},\"char_attrs\":{}},\"psd_raw\":null}")
    document.sourceMetadata = try PcraftMetadata.read(source.field("metadata"), project: project)
    if let profile = try source.optional("icc_profile")?.string() {
      guard let bytes = project.blobs[profile] else { throw source.invalid }
      document.sourceICC = bytes
      document.workingICC = try ColorManagement.importedProfile(bytes, depth: depth)
    }
    var remaining = rasterByteLimit
    let patterns = try PcraftPatterns.read(source, project: project, budget: &remaining)
    document.patterns = patterns.isEmpty ? nil : patterns
    return PcraftLayerMapper(project: project, document:document, namespace: namespace, depth: depth,
      remainingBytes: remaining, patterns: patterns, dpi:document.pixelsPerInch, canvas:.init(x:0,y:0,width:document.width,height:document.height))
  }
  @inline(never) private static func finish(_ mapper: PcraftLayerMapper, layers: [Layer]) throws -> CraftDocument {
    let project = mapper.project, namespace = mapper.namespace
    let source = try PcraftNode(project.manifest, path: "").field("document")
    var document = mapper.document
    document.layers = layers
    document.activeLayerID = document.layers.last?.id
    document.paths = try PcraftPaths.named(source, namespace: namespace)
    if let selection = project.surfaces["/document/selection"] {
      try PcraftSamples.validateSchema(source.field("selection"))
      let mask = try PcraftSamples.selection(selection, width: document.width, height: document.height,
        budget: &mapper.remainingBytes)
      guard mask.bounds != nil else {
        throw source.unsupported("An explicit empty selection cannot be represented without changing editing coverage.")
      }
      document.selection = mask.bounds
      document.selectionMask = mask
    }
    try PcraftChannels.read(source,project:project,document:&document,namespace:namespace,budget:&mapper.remainingBytes)
    // Import provenance is immutable source evidence, never an editing cache.
    document.sourceMetadata = (document.sourceMetadata ?? [:]).merging(["pcraft.manifest": project.rawManifest]) { _, new in new }
    try document.validate()
    _ = try ColorManagement.space(for: document)
    try Task.checkCancellation()
    return document
  }
  static func identity(_ namespace: Data, role: String, id: UInt64) -> UUID {
    var bytes = Array(SHA256.hash(data: namespace + Data("\(role):\(id)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 15) | 0x50
    bytes[8] = (bytes[8] & 63) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}

/// Path-bearing schema errors let callers identify an unsupported source feature
/// without publishing a partially converted document.
struct PcraftNode {
  let value: PcraftJSON
  let path: String
  init(_ value: PcraftJSON, path: String) { self.value = value; self.path = path }
  var invalid: CraftError { .invalid("Invalid PhotoCraft value at \(path).") }
  func unsupported(_ message: String) -> CraftError {
    .unsupported("PhotoCraft import at \(path): \(message)")
  }
  func field(_ key: String) throws -> Self {
    guard let value = value[key] else { throw invalid }
    return Self(value, path: path + "/" + key)
  }
  func optional(_ key: String) -> Self? {
    guard let value = value[key], value != .null else { return nil }
    return Self(value, path: path + "/" + key)
  }
  func keys(_ allowed: String) throws {
    guard case .object(let fields) = value else { throw invalid }
    let known = Set(allowed.split(separator: " ").map(String.init))
    if let unknown = fields.keys.sorted().first(where: { !known.contains($0) }) {
      throw unsupported("The field '\(unknown)' is not supported.")
    }
  }
  func string() throws -> String { guard let v = value.string else { throw invalid }; return v }
  func boolean() throws -> Bool { guard let v = value.bool else { throw invalid }; return v }
  func unsigned() throws -> UInt64 { guard let v = value.uint else { throw invalid }; return v }
  func integer() throws -> Int {
    guard let v = value.int, let result = Int(exactly: v) else { throw invalid }; return result
  }
  func double() throws -> Double {
    guard case .number(let token) = value, let v = Double(token), v.isFinite else { throw invalid }; return v
  }
  func float() throws -> Float {
    guard case .number(let token) = value, let v = Float(token), v.isFinite else { throw invalid }; return v
  }
  func array() throws -> [Self] {
    guard let values = value.array else { throw invalid }
    return values.enumerated().map { Self($0.element, path: path + "/\($0.offset)") }
  }
  func defaultValue(_ key: String, _ expected: String) throws {
    guard let actual = value[key] else { return }
    let reference = try PcraftJSON.parse(Data(expected.utf8))
    guard Self.equivalent(actual, reference) else {
      throw unsupported("Non-default '\(key)' is not yet editable.")
    }
  }
  private static func equivalent(_ a: PcraftJSON, _ b: PcraftJSON) -> Bool {
    switch (a, b) {
    case (.number(let x), .number(let y)): return Double(x) == Double(y)
    case (.array(let x), .array(let y)):
      return x.count == y.count && zip(x, y).allSatisfy { equivalent($0, $1) }
    case (.object(let x), .object(let y)):
      return x.count == y.count && x.allSatisfy { key, value in y[key].map { equivalent(value, $0) } == true }
    default: return a == b
    }
  }
}
