import Foundation
import PhotoCraftCore

/// Lossless source-format intermediate representation, not a CraftDocument or
/// an editable-import capability. Unported source features remain in the graph.
struct PcraftProject: Sendable {
  struct Limits: Sendable {
    var manifestBytes = 16 * 1024 * 1024
    var blobBytes = 256 * 1024 * 1024
    var totalBytes = 512 * 1024 * 1024
    var nodes = 250_000
    var layers = LayerLimits.maximumLayers
    var surfaces = 16_384
    func validate() throws {
      guard (1...16 * 1024 * 1024).contains(manifestBytes),
        (0...256 * 1024 * 1024).contains(blobBytes),
        (0...512 * 1024 * 1024).contains(totalBytes), (1...250_000).contains(nodes),
        (1...LayerLimits.maximumLayers).contains(layers), (1...16_384).contains(surfaces) else {
        throw CraftError.invalid("Invalid PhotoCraft project limits.")
      }
    }
  }
  struct Coordinate: Hashable, Sendable { let x: Int32; let y: Int32 }
  struct Surface: Sendable {
    let mode: String
    let sample: String
    let alpha: Bool
    let bytesPerPixel: Int
    let defaultPixel: Data
    let tiles: [Coordinate: Data]

    /// Exact encoded samples, including negative/off-canvas coordinates and
    /// unbounded source defaults. No color conversion or quantization occurs.
    func pixel(x: Int64, y: Int64) -> Data {
      let tx = x / 256 - (x % 256 < 0 ? 1 : 0), ty = y / 256 - (y % 256 < 0 ? 1 : 0)
      guard let xx = Int32(exactly: tx), let yy = Int32(exactly: ty),
        let tile = tiles[Coordinate(x: xx, y: yy)] else { return defaultPixel }
      let px = Int((x % 256 + 256) % 256), py = Int((y % 256 + 256) % 256)
      let at = (py * 256 + px) * bytesPerPixel
      return tile.subdata(in: at..<(at + bytesPerPixel))
    }
  }
  let rawManifest: Data
  let manifest: PcraftJSON
  /// JSON-pointer locations identify surfaces without translating their roles.
  let surfaces: [String: Surface]
  let blobs: [String: Data]
  let layerIDs: [UInt64]
  let accountedBytes: Int

  static func read(_ data: Data, limits: Limits = Limits()) throws -> Self {
    try limits.validate()
    let zip = try PcraftZIP(data)
    return try read(limits: limits) { try zip.read($0, limit: $1) }
  }
  static func read(_ url: URL, limits: Limits = Limits()) throws -> Self {
    try limits.validate()
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    if values.isDirectory == true {
      let source = try PcraftDirectory(url)
      let result = try read(limits: limits) { try source.read($0, limit: $1) }
      try source.validateUnchanged()
      return result
    }
    let source = try PSDFileSource(url, maximumBytes: PcraftZIP.maximumArchiveBytes)
    let result = try read(source.bytes(at: 0, count: source.count), limits: limits)
    try source.validateUnchanged()
    return result
  }
  /// Injected byte source also permits isolated corruption/budget testing.
  static func read(limits: Limits = Limits(), fetch: @escaping (String, Int) throws -> Data) throws -> Self {
    try limits.validate(); try Task.checkCancellation()
    let raw = try fetch("manifest.json", limits.manifestBytes)
    guard raw.count <= limits.manifestBytes, raw.count <= limits.totalBytes else { throw invalid }
    let root = try PcraftJSON.parse(raw, maximumNodes: limits.nodes)
    guard root["format_version"]?.uint == 1, root["generator"]?.string != nil,
      let doc = root["document"], doc["id"]?.uint != nil, doc["name"]?.string != nil,
      let size = doc["size"], let width = size["width"]?.uint, let height = size["height"]?.uint,
      width > 0, height > 0, width <= UInt32.max, height <= UInt32.max,
      let mode = doc["mode"]?.string, colorChannels[mode] != nil,
      let depth = doc["depth"]?.string, sampleBytes[depth] != nil else { throw invalid }
    var loader = Loader(limits: limits, fetch: fetch, total: raw.count)
    try loader.layers(doc["layers"], path: "/document/layers", depth: 0)
    try loader.optionalSurface(doc["selection"], "/document/selection")
    for (index, channel) in try list(doc["channels"]).enumerated() {
      try loader.surface(channel["surface"], "/document/channels/\(index)/surface")
    }
    if let quick = optional(doc["quick_mask"]) {
      try loader.surface(quick["surface"], "/document/quick_mask/surface")
    }
    for (index, pattern) in try list(doc["patterns"], optional: true).enumerated() {
      try loader.surface(pattern["surface"], "/document/patterns/\(index)/surface")
    }
    try loader.blob(doc["icc_profile"])
    guard let metadata = doc["metadata"], case .object = metadata else { throw invalid }
    try loader.blob(metadata["exif"])
    try loader.tuples(metadata["psd_resources"], count: 3)
    try loader.tuples(metadata["psd_global_blocks"], count: 3)
    for path in try list(doc["paths"], optional: true) { try loader.blob(path["psd_raw"]) }
    for comp in try list(doc["layer_comps"], optional: true) { try loader.comp(comp) }
    if let comp = optional(doc["last_document_state"]) { try loader.comp(comp) }
    return Self(rawManifest: raw, manifest: root, surfaces: loader.surfaces, blobs: loader.blobs,
      layerIDs: loader.ids, accountedBytes: loader.total)
  }
  private static let colorChannels = ["Bitmap": 1, "Grayscale": 1, "Duotone": 1,
    "Indexed": 3, "Rgb": 3, "Lab": 3, "Cmyk": 4, "Multichannel": 3]
  private static let sampleBytes = ["U8": 1, "U16": 2, "F32": 4]
  private static var invalid: CraftError { .invalid("Invalid, unsupported, or excessive PhotoCraft project data.") }
  private static func optional(_ value: PcraftJSON?) -> PcraftJSON? { value == .null ? nil : value }
  private static func list(_ value: PcraftJSON?, optional: Bool = false) throws -> [PcraftJSON] {
    if value == nil && optional { return [] }
    guard let items = value?.array else { throw invalid }
    return items
  }
  private static func hash(_ value: PcraftJSON?) throws -> String {
    guard let hash = value?.string, hash.utf8.count == 64,
      hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw invalid }
    return hash
  }
  private struct Loader {
    let limits: Limits
    let fetch: (String, Int) throws -> Data
    var total: Int
    var surfaces: [String: Surface] = [:]
    var blobs: [String: Data] = [:]
    var tiles: [String: Data] = [:]
    var ids: [UInt64] = []
    var idSet: Set<UInt64> = []
    mutating func account(_ count: Int) throws {
      guard count >= 0, count <= limits.totalBytes - total else { throw invalid }
      total += count
    }
    func payload(_ hash: String, folder: String, limit: Int, expected: Int? = nil) throws -> Data {
      let compressedLimit = min(256 * 1024 * 1024, limit + limit / 8 + 4096)
      let compressed = try fetch("\(folder)/\(hash).zst", compressedLimit)
      guard compressed.count <= compressedLimit else { throw invalid }
      let bytes = try PcraftZstd.decode(compressed, limit: limit, expectedBytes: expected)
      guard try PcraftBLAKE3.hex(bytes) == hash else { throw invalid }
      return bytes
    }
    mutating func blob(_ value: PcraftJSON?) throws {
      guard let value = optional(value) else { return }
      try Task.checkCancellation()
      let name = try hash(value)
      if blobs[name] != nil { return }
      let bytes = try payload(name, folder: "blobs", limit: min(limits.blobBytes, limits.totalBytes - total))
      try account(bytes.count); blobs[name] = bytes
    }
    mutating func tuples(_ value: PcraftJSON?, count: Int) throws {
      for item in try list(value) {
        guard let values = item.array, values.count == count else { throw invalid }
        // A null at a required reference must not silently become an omitted blob.
        _ = try hash(values[count - 1]); try blob(values[count - 1])
      }
    }
    mutating func surface(_ value: PcraftJSON?, _ path: String) throws {
      try Task.checkCancellation()
      guard surfaces.count < limits.surfaces, let value, let format = value["format"],
        let mode = format["mode"]?.string, let channels = colorChannels[mode],
        let sample = format["sample"]?.string, let bytes = sampleBytes[sample],
        let alpha = format["alpha"]?.bool, let encoded = value["default"]?.string else { throw invalid }
      let pixelBytes = (channels + (alpha ? 1 : 0)) * bytes
      let hex = Array(encoded.utf8)
      guard hex.count == pixelBytes * 2,
        hex.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
      else { throw invalid }
      var defaultPixel = Data()
      for at in stride(from: 0, to: hex.count, by: 2) {
        guard let byte = UInt8(String(decoding: hex[at..<(at + 2)], as: UTF8.self), radix: 16) else { throw invalid }
        defaultPixel.append(byte)
      }
      let length = 256 * 256 * pixelBytes
      var result: [Coordinate: Data] = [:]
      for tile in try list(value["tiles"]) {
        try Task.checkCancellation()
        guard let x = tile["tx"]?.int, let y = tile["ty"]?.int,
          let xx = Int32(exactly: x), let yy = Int32(exactly: y) else { throw invalid }
        let coordinate = Coordinate(x: xx, y: yy)
        guard result[coordinate] == nil else { throw invalid }
        let name = try hash(tile["hash"])
        try account(length) // Count logical uses even when payload storage is shared.
        if let cached = tiles[name] {
          guard cached.count == length else { throw invalid }
          result[coordinate] = cached
        } else {
          let bytes = try payload(name, folder: "tiles", limit: length, expected: length)
          tiles[name] = bytes; result[coordinate] = bytes
        }
      }
      surfaces[path] = Surface(mode: mode, sample: sample, alpha: alpha,
        bytesPerPixel: pixelBytes, defaultPixel: defaultPixel, tiles: result)
    }
    mutating func optionalSurface(_ value: PcraftJSON?, _ path: String) throws {
      if let value = optional(value) { try surface(value, path) }
    }
    mutating func mask(_ value: PcraftJSON?, _ path: String) throws {
      if let value = optional(value) { try surface(value["surface"], path + "/surface") }
    }
    mutating func comp(_ value: PcraftJSON) throws {
      for state in try list(value["states"], optional: true) {
        try blob(state["appearance"]?["effects"]?["psd_raw"])
      }
    }
    mutating func layers(_ value: PcraftJSON?, path: String, depth: Int) throws {
      let items = try list(value)
      guard depth <= 100 || items.isEmpty else { throw invalid }
      for (index, layer) in items.enumerated() {
        try Task.checkCancellation()
        guard ids.count < limits.layers, let id = layer["id"]?.uint,
          idSet.insert(id).inserted, layer["name"]?.string != nil,
          let content = layer["content"], let kind = content["kind"]?.string else { throw invalid }
        ids.append(id)
        let at = "\(path)/\(index)"
        try mask(layer["mask"], at + "/mask")
        try blob(layer["effects"]?["psd_raw"])
        try tuples(layer["psd_blocks"], count: 2)
        if let cache = optional(layer["fill_cache"]) { try surface(cache["surface"], at + "/fill_cache/surface") }
        if let video = optional(layer["video"]) {
          for (frame, surfaceValue) in try list(video["frames"]).enumerated() {
            try surface(surfaceValue, at + "/video/frames/\(frame)")
          }
        }
        switch kind {
        case "raster": try surface(content["surface"], at + "/content/surface")
        case "group": try layers(content["children"], path: at + "/content/children", depth: depth + 1)
        case "text", "shape", "smart":
          try optionalSurface(content["cache"], at + "/content/cache")
          try blob(content["psd_raw"])
          if kind == "smart" {
            guard let source = content["source"] else { throw invalid }
            switch source["kind"]?.string {
            case "embedded":
              _ = try hash(source["blob"]); try blob(source["blob"])
            case "linked":
              guard source["path"]?.string != nil else { throw invalid }
            default: throw invalid
            }
            try mask(content["filter_mask"], at + "/content/filter_mask")
          }
        case "adjustment", "fill": break
        default: throw invalid
        }
      }
    }
  }
}
