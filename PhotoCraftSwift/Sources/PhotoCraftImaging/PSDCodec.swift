import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

// Bounded native PSD v1 / PSB v2 RGB/Gray/CMYK/Lab interchange, based on Adobe's public
// file-format specification and PhotoCraft's Rust psd/header, layer and compression modules.
// Unrepresented rich layers fail explicitly. They are never flattened on import.
struct PSDReader {
  private let storage: PSDByteStorage
  private let start: Int
  private let count: Int
  private let metadataBudget: PSDMetadataBudget
  var byteCount: Int { count }
  private(set) var offset = 0
  var remaining: Int { offset >= 0 && offset <= count ? count - offset : 0 }
  // Materialize retained metadata only. Nested sections/channels use view(),
  // avoiding whole-file loads and repeated complete section copies.
  var data: Data { get throws {
    try metadataBudget.reserve(count)
    return try storage.bytes(at: start, count: count)
  } }
  init(data: Data, offset: Int = 0) {
    self.offset = offset
    storage = .memory(data)
    start = 0
    count = data.count
    metadataBudget = PSDMetadataBudget()
  }
  init(file: PSDFileSource) {
    storage = .file(file)
    start = 0
    count = file.count
    metadataBudget = PSDMetadataBudget()
  }
  func validateUnchanged() throws { try storage.validateUnchanged() }
  private init(storage: PSDByteStorage, start: Int, count: Int, metadataBudget: PSDMetadataBudget) {
    self.storage = storage
    self.start = start
    self.count = count
    self.metadataBudget = metadataBudget
  }
  mutating func view(_ count: Int) throws -> PSDReader {
    guard offset >= 0, offset <= self.count, count >= 0, count <= remaining else {
      throw CraftError.invalid("Truncated PSD section at byte \(offset).")
    }
    defer { offset += count }
    return PSDReader(storage: storage, start: start + offset, count: count, metadataBudget: metadataBudget)
  }
  mutating func bytes(_ count: Int) throws -> Data {
    guard offset >= 0, offset <= self.count, count >= 0, count <= remaining,
      count <= PSDCodec.maximumInputBytes else {
      throw CraftError.invalid("Truncated PSD section at byte \(offset).")
    }
    defer { offset += count }
    return try storage.bytes(at: start + offset, count: count)
  }
  mutating func retainedBytes(_ count: Int) throws -> Data {
    try metadataBudget.reserve(count)
    return try bytes(count)
  }
  mutating func retainSource(_ count: Int, in backing: RasterTileStore) throws -> FileBackedSource {
    let source = try view(count)
    return try backing.retainSource(byteCount: count) { offset, length in
      try source.storage.bytes(at: source.start + offset, count: length)
    }
  }
  mutating func consumePadding(_ byte: UInt8) throws -> Bool {
    guard offset >= 0, offset <= count else { return false }
    defer { offset = count }
    return try storage.padding(at: start + offset, count: count - offset, byte: byte)
  }
  mutating func number(_ count: Int) throws -> UInt64 {
    guard (1...8).contains(count), count <= remaining else {
      throw CraftError.invalid("Invalid or truncated PSD number at byte \(offset).")
    }
    let value = try storage.number(at: start + offset, count: count)
    offset += count
    return value
  }
  mutating func u8() throws -> UInt8 { UInt8(try number(1)) }
  mutating func u16() throws -> Int { Int(try number(2)) }
  mutating func i16() throws -> Int { Int(Int16(bitPattern: UInt16(try number(2)))) }
  mutating func u32() throws -> Int { Int(try number(4)) }
  mutating func i32() throws -> Int { Int(Int32(bitPattern: UInt32(try number(4)))) }
  mutating func string(_ count: Int) throws -> String {
    String(decoding: try bytes(count), as: UTF8.self)
  }
  mutating func length(_ count: Int) throws -> Int {
    let value = try number(count)
    guard let result = Int(exactly: value) else {
      throw CraftError.invalid("Photoshop section length exceeds the addressable size.")
    }
    return result
  }
  mutating func section(lengthBytes: Int = 4) throws -> PSDReader {
    try view(length(lengthBytes))
  }
}
struct PSDWriter {
  var data = Data()
  mutating func n(_ value: Int, _ count: Int) {
    let bits = UInt64(truncatingIfNeeded: value)
    for i in (0..<count).reversed() { data.append(UInt8(truncatingIfNeeded: bits >> (i * 8))) }
  }
  mutating func text(_ s: String) { data.append(contentsOf: s.utf8) }
  mutating func section(_ d: Data, lengthBytes: Int = 4) {
    n(d.count, lengthBytes)
    data.append(d)
  }
}
public enum PSDCodec {
  public static let maximumInputBytes = 512 * 1024 * 1024
  /// Implementation admission, not a claim about the PSB format's upper size.
  public static let maximumFileBytes = 4_398_046_511_104
  public static let maximumMetadataBytes = 512 * 1024 * 1024
  public static let maximumPSDFileBytes = 2_147_483_648
  public static let pagedWorkingHeapReserveBytes = 16 * 1024 * 1024
  public static let fileReadWindowBytes = PSDFileSource.pageBytes
  public static let maximumFileCacheBytes =
    PSDFileSource.pageBytes * PSDFileSource.maximumCachedPages

  public static func read(_ url: URL, name: String? = nil) throws -> CraftDocument {
    try PSDFileSource.withStableMetadata(url) { source in
      try read(
        PSDReader(file: source), name: name ?? url.deletingPathExtension().lastPathComponent,
        paging: PSDRasterPaging.Context())
    }
  }

  private static func storageBytes(width: Int, height: Int) -> Int {
    let side = Surface.tileSide
    return ((width + side - 1) / side) * ((height + side - 1) / side) * side * side * 16
  }
  static let keys = [
    "norm", "diss", "dark", "mul ", "idiv", "lbrn", "dkCl", "lite", "scrn", "div ", "lddg", "lgCl",
    "over", "sLit", "hLit", "vLit", "lLit", "pLit", "hMix", "diff", "smud", "fsub", "fdiv", "hue ",
    "sat ", "colr", "lum ",
  ]
  struct Record {
    var name: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var channels: [(Int, Int)]
    var blend: BlendMode
    var opacity: Float
    var visible: Bool
    var protection: LayerProtection
    var mask: PSDMaskRecord?
    var tags: [String: Data]
    var section: Int
    var passThrough: Bool
    var clipped: Bool
    var placedLayerID: UUID?
  }
  public static func decodePackBits(_ data: Data, expected: Int) throws -> [UInt8] {
    try decodePackBits(PSDReader(data: data), expected: expected)
  }
  static func decodePackBits(_ source: PSDReader, expected: Int) throws -> [UInt8] {
    guard expected >= 0, expected <= Surface.maxDimension * 4 else {
      throw CraftError.invalid("PSD row exceeds the size limit.")
    }
    var r = source
    var out: [UInt8] = []
    out.reserveCapacity(expected)
    while out.count < expected {
      let code = Int(Int8(bitPattern: try r.u8()))
      if code >= 0 {
        let count = code + 1
        guard count <= expected - out.count else {
          throw CraftError.invalid("PackBits literal exceeds the row.")
        }
        out.append(contentsOf: try r.bytes(count))
      } else if code != -128 {
        let count = 1 - code
        guard count <= expected - out.count else {
          throw CraftError.invalid("PackBits repeat exceeds the row.")
        }
        out.append(contentsOf: repeatElement(try r.u8(), count: count))
      }
    }
    if r.remaining > 0 {
      guard try r.consumePadding(128) else {
        throw CraftError.invalid("Unexpected trailing PackBits bytes.")
      }
    }
    return out
  }
  public static func read(_ data: Data, name: String = "Imported PSD") throws -> CraftDocument {
    guard data.count <= maximumInputBytes else {
      throw CraftError.invalid("PSD exceeds the 512 MiB input limit.")
    }
    return try read(PSDReader(data: data), name: name)
  }
  /// API Data retains its container and metadata/workspace heap admission. The
  /// same paged assembly serves native files; sample pages have separate disk bounds.
  public static func readPaged(_ data: Data, name: String = "Imported PSD",
    heapByteLimit: Int = 1_073_741_824,
    scratchByteLimit: Int = RasterTileStore.defaultMaximumBytes) throws -> CraftDocument {
    try readPaged(.memory(data), name: name, heapByteLimit: heapByteLimit, scratchByteLimit: scratchByteLimit)
  }
  public static func readPaged(_ source: EmbeddedSourceBytes, name: String = "Imported PSD",
    heapByteLimit: Int = 1_073_741_824,
    scratchByteLimit: Int = RasterTileStore.defaultMaximumBytes) throws -> CraftDocument {
    let data = source.data
    let limit = source.isFileBacked ? SmartObject.maximumFileBackedSourceBytes : maximumInputBytes
    guard data.count <= limit, (0...1_073_741_824).contains(heapByteLimit) else {
      throw CraftError.invalid("Invalid paged Photoshop input budget.")
    }
    return try read(PSDReader(data:data),name:name,
      paging:PSDRasterPaging.Context(heapByteLimit:heapByteLimit,scratchByteLimit:scratchByteLimit))
  }
  private struct DeferredPlacedLayers {
    let indices: [Int]
    let sources: [String: PSDSmartObjects.File]
    let filterMasks: [String: PSDSmartFilters.Mask]
  }

  private struct DecodedDocument {
    var document: CraftDocument
    var placedLayers: DeferredPlacedLayers?
    var readArtboards: Bool = false
  }

  private struct DecodeFrame {
    let source: PSDReader
    var decoded: DecodedDocument
    var nextPlacement = 0
  }

  private struct PendingParent {
    let frame: DecodeFrame
    let layerIndex: Int
    let placement: PSDSmartObjects.Placement
  }

  static func read(_ source: PSDReader, name: String, tiffComposite: Surface? = nil,
    tiffNativeComposite: NativeModeRaster? = nil, paging: PSDRasterPaging.Context? = nil) throws -> CraftDocument {
    var frame = DecodeFrame(source: source, decoded: try readContainer(source, name: name,
      tiffComposite: tiffComposite, tiffNativeComposite: tiffNativeComposite, paging: paging))
    let startingDepth = SmartObjectIO.nesting
    var parents: [PendingParent] = []
    // Parse each Photoshop container independently, then restore its sources in
    // postorder. Retain parent state in the array instead of the worker stack.
    while true {
      try Task.checkCancellation()
      if let assets = frame.decoded.placedLayers, frame.nextPlacement < assets.indices.count {
        let index = assets.indices[frame.nextPlacement]
        frame.nextPlacement += 1
        let placement = try PSDSmartObjects.placement(frame.decoded.document.layers[index], files: assets.sources)
        let depth = startingDepth + parents.count
        if let name = try SmartObjectIO.photoshopDocumentName(placement.file.source, fileName: placement.file.name) {
          try SmartObjectIO.checkNesting(depth)
          let reader = PSDReader(data: placement.file.data)
          let child = try readContainer(reader, name: name, tiffComposite: nil, tiffNativeComposite: nil,
            paging: PSDRasterPaging.Context(heapByteLimit: SmartObjectIO.maximumDecodedBytes,
              sharedBacking: paging?.backing))
          parents.append(PendingParent(frame: frame, layerIndex: index, placement: placement))
          frame = DecodeFrame(source: reader, decoded: child)
        } else {
          try restore(placement, at: index, in: &frame, nestingDepth: depth)
        }
      } else {
        if frame.decoded.placedLayers != nil {
          if frame.decoded.readArtboards { try PSDArtboards.read(into: &frame.decoded.document) }
          try PSDLayerComps.read(into: &frame.decoded.document)
          try frame.decoded.document.validate()
          try frame.source.validateUnchanged()
        }
        guard let parent = parents.popLast() else { return frame.decoded.document }
        let document = frame.decoded.document
        frame = parent.frame
        try restore(parent.placement, at: parent.layerIndex, in: &frame,
          nestingDepth: startingDepth + parents.count, decodedSource: document)
      }
    }
  }

  private static func restore(_ placement: PSDSmartObjects.Placement, at index: Int, in frame: inout DecodeFrame,
    nestingDepth: Int, decodedSource: CraftDocument? = nil) throws {
    var layer = frame.decoded.document.layers[index]
    try SmartObjectIO.$nesting.withValue(nestingDepth) {
      try PSDSmartObjects.restore(&layer, placement: placement, in: frame.decoded.document,
        filterMasks: frame.decoded.placedLayers?.filterMasks ?? [:], decodedSource: decodedSource)
    }
    try PSDText.restore(&layer, in: frame.decoded.document)
    frame.decoded.document.layers[index] = layer
  }

  @inline(never)
  private static func readContainer(_ source: PSDReader, name: String, tiffComposite: Surface?,
    tiffNativeComposite: NativeModeRaster?, paging suppliedPaging: PSDRasterPaging.Context?) throws -> DecodedDocument {
    try Task.checkCancellation()
    var r = source
    guard try r.string(4) == "8BPS" else { throw CraftError.invalid("This is not a PSD file.") }
    guard let format = PSDFileFormat(rawValue: try r.u16()) else {
      throw CraftError.unsupported("Unsupported Photoshop file version; expected PSD or PSB.")
    }
    guard source.byteCount <= (format == .psd ? maximumPSDFileBytes:maximumFileBytes) else {
      throw CraftError.invalid("Photoshop file exceeds the selected container's file budget.")
    }
    guard try r.bytes(6).allSatisfy({ $0 == 0 }) else {
      throw CraftError.invalid("Invalid PSD reserved header.")
    }
    let channels = try r.u16()
    let height = try r.u32()
    let width = try r.u32()
    let depth = try r.u16()
    let mode = try r.u16()
    guard width <= format.maximumDimension, height <= format.maximumDimension else {
      throw CraftError.invalid("Photoshop dimensions exceed this container's format limit.")
    }
    if mode == 7 {
      guard tiffComposite == nil, tiffNativeComposite == nil else { throw CraftError.unsupported("Multichannel Photoshop layer payloads are not used inside TIFF.") }
      return DecodedDocument(document: try PSDMultichannelStorage.read(r, width: width, height: height, depth: depth,
        channels: channels, format: format, name: name, paging: suppliedPaging))
    }
    if mode == 0 || mode == 2 {
      guard tiffComposite == nil, tiffNativeComposite == nil else { throw CraftError.unsupported("Restricted Photoshop layer payloads are not used inside TIFF.") }
      return DecodedDocument(document: try PSDRestrictedStorage.read(r, width: width, height: height, depth: depth, mode: mode,
        channels: channels, format: format, name: name))
    }
    let colorMode = try PSDModeStorage.mode(mode), colorChannels = colorMode.componentCount
    let pixelDepth: PixelDepth = depth == 8 ? .u8 : depth == 16 ? .u16 : .f32
    guard [8, 16, 32].contains(depth), colorMode.depths.contains(pixelDepth),
      (colorChannels...56).contains(channels) else {
      throw CraftError.unsupported("Unsupported Photoshop mode/depth or total channel count.")
    }
    if colorMode != .rgb {
      guard height > 0, width > 0, width <= NativeModeRaster.maximumDocumentPixels / height else {
        throw CraftError.unsupported("Native mode PSD/PSB dimensions exceed the document limit.")
      }
    }
    // Data admission remains bounded; large compressed component images still
    // need paged decoded samples, including RasterIO and isolated API jobs.
    let paging = try suppliedPaging ?? (colorMode != .rgb ? PSDRasterPaging.Context():nil)
    var doc = try CraftDocument(width: width, height: height, depth: pixelDepth, name: name)
    let colorData = try r.section().data
    guard
      colorData.isEmpty || (depth == 32 && colorData.starts(with: Data("hdrt".utf8)))
    else {
      throw CraftError.unsupported("Unexpected color-mode data in this PSD.")
    }
    var resources = try r.section()
    let resourceData = try resources.data
    let resourceBlocks = try PSDImageResources.blocks(resourceData)
    let importedLight = try PSDGlobalLight.read(resourceBlocks)
    doc.globalLight = importedLight
    let styleGlobalAngle = importedLight?.angle ?? 120
    var profile: Data?
    while resources.remaining > 0 {
      guard try resources.string(4) == "8BIM" else {
        throw CraftError.invalid("Invalid image resource signature.")
      }
      let id = try resources.u16()
      let length = Int(try resources.u8())
      let resourceName = String(data: try resources.bytes(length), encoding: .macOSRoman) ?? "Path"
      if (length + 1) % 2 != 0 { _ = try resources.bytes(1) }
      let count = try resources.u32()
      let content = try resources.bytes(count)
      if count % 2 != 0 { _ = try resources.bytes(1) }
      if id == 1039 { profile = content }
      if id == 1041, content.first == 1 { doc.profileIsUntagged = true }
      if id == 1025 || (2000...2997).contains(id) {
        var paths = doc.paths ?? []
        paths.append(
          NamedPath(
            name: id == 1025 ? "Work Path" : (resourceName.isEmpty ? "Path" : resourceName),
            path: try PSDPaths.read(content, width: width, height: height), isWorkPath: id == 1025))
        doc.paths = paths
      }
      if id == 1005 {
        var resolution = PSDReader(data: content)
        let horizontal = Double(try resolution.u32()) / 65536
        let horizontalUnit = try resolution.u16()
        _ = try resolution.u16()
        let vertical = Double(try resolution.u32()) / 65536
        let verticalUnit = try resolution.u16()
        _ = try resolution.u16()
        // Resolution values are stored in pixels/inch; units select how the UI displays them.
        guard (1...2).contains(horizontalUnit), (1...2).contains(verticalUnit),
          horizontal >= 1, vertical >= 1, abs(horizontal - vertical) < 0.01
        else {
          throw CraftError.unsupported(
            "Unequal horizontal/vertical PSD resolutions are not supported yet.")
        }
        doc.resolution = horizontal
      }
    }
    // Preserve all image resource blocks in the development archive, including unknown metadata.
    doc.sourceMetadata = ["psdResources": resourceData, "psdColorModeData": colorData]
    try PSDGuides.read(into:&doc)
    doc.sourceICC = profile
    if colorMode == .rgb {
      doc.workingICC = try ColorManagement.importedProfile(profile, depth: doc.depth)
    } else {
      doc.modeDescriptor = try DocumentModeDescriptor(mode: colorMode, depth: pixelDepth,
        profile: PSDModeStorage.profile(profile, mode: colorMode, depth: pixelDepth))
    }
    var layerSection = try r.section(lengthBytes: format.sectionLengthBytes)
    var info =
      layerSection.remaining > 0
      ? try layerSection.section(lengthBytes: format.sectionLengthBytes) : PSDReader(data: Data())
    var mergedTransparency = false
    var filterCacheViews:[String:PSDReader]=[:]
    var linkViews: [String: PSDReader] = [:]
    if layerSection.remaining > 0 {
      let global = try layerSection.section()
      guard global.remaining == 0 || global.remaining >= 13 else {
        throw CraftError.invalid("Invalid global mask info.")
      }
      doc.sourceMetadata?["psdGlobalMask"] = try global.data
      var tags = Set<String>()
      while layerSection.remaining >= 12 {
        guard ["8BIM", "8B64"].contains(try layerSection.string(4)) else {
          throw CraftError.invalid("Invalid global PSD tag.")
        }
        let tag = try layerSection.string(4)
        let length = try layerSection.length(format.tagLengthBytes(tag))
        let contentView = try layerSection.view(length)
        _ = try layerSection.bytes((4 - length % 4) % 4)
        guard tags.insert(tag).inserted else {
          throw CraftError.invalid("Duplicate global PSD block.")
        }
        if ["Lr16", "Lr32", "Layr"].contains(tag) {
          let expectedTag = depth == 16 ? "Lr16" : depth == 32 ? "Lr32" : "Layr"
          guard tag == expectedTag, info.remaining == 0 else {
            throw CraftError.unsupported("Conflicting PSD layer-depth sections.")
          }
          info = contentView
          continue
        }
        if ["FEid","FXid"].contains(tag) {
          filterCacheViews[tag]=contentView
          if length<=PSDSmartFilters.maximumRetainedCacheBytes {doc.sourceMetadata?["psdGlobal_"+tag]=try contentView.data}
          continue
        }
        if PSDSmartObjects.linkKeys.contains(tag) {
          linkViews[tag] = contentView
          // The editable sources own their bytes. Keep legacy metadata for
          // small blocks without duplicating a large aggregate of originals.
          if length <= SmartObject.maximumSourceBytes {
            doc.sourceMetadata?["psdGlobal_" + tag] = try contentView.data
          }
          continue
        }
        let content = try contentView.data
        if ["Mt16", "Mt32", "Mtrn"].contains(tag) {
          mergedTransparency = true
          doc.sourceMetadata?["psdGlobal_" + tag] = content
        } else if tag == "pths" {
          let names = try PSDPaths.readNames(content)
          let indices = (doc.paths ?? []).indices.filter { doc.paths?[$0].isWorkPath == false }
          guard names.count == indices.count else {
            throw CraftError.invalid("PSD path names and resources disagree.")
          }
          for (i, name) in zip(indices, names) { doc.paths?[i].name = name }
        } else if tag == "LMsk" {
          // User-mask overlay color/opacity; not a layer coverage channel.
          guard (13...16).contains(content.count), content[12] == 128 else {
            throw CraftError.unsupported("Unrecognized PSD user-mask display metadata.")
          }
          doc.sourceMetadata?["psdGlobal_LMsk"] = content
        } else {
          if tag == "OCIO" {
            let icc=try PSDColorMetadata.usesICC(content)
            let unmanaged=try colorMode == .rgb && PSDColorMetadata.permitsUnmanagedRGB(
              content,untagged:doc.profileIsUntagged==true,hasEmbeddedICC:profile != nil)
            guard icc || unmanaged else {
              throw CraftError.unsupported("OpenColorIO-managed or unrepresented Photoshop color metadata is not ported yet.")
            }
          }
          if PSDArtboards.keys.contains(tag) { _ = try PSDArtboards.global(content) }
          guard ["Patt", "Pat2", "Pat3", "FMsk", "cinf", "CAI ", "OCIO", "GenI", "Anno"].contains(tag) || PSDArtboards.keys.contains(tag)
          else {
            throw CraftError.unsupported("Global PSD block '\(tag)' is not ported yet.")
          }
          doc.sourceMetadata?["psdGlobal_" + tag] = content
        }
      }
      guard try layerSection.consumePadding(0) else {
        throw CraftError.invalid("Invalid global PSD padding.")
      }
    }
    var patternBytes = 0
    for key in PSDPatterns.keys {
      guard let block = doc.sourceMetadata?["psdGlobal_" + key] else { continue }
      let patterns = try PSDPatterns.read(block, tileBudget: 536_870_912 - patternBytes)
      for pattern in patterns {
        if let previous = doc.pattern(pattern.id) {
          guard try PSDPatterns.exact([previous], [pattern]) else {
            throw CraftError.invalid("Conflicting embedded PSD pattern identifiers.")
          }
        } else {
          doc.patterns = (doc.patterns ?? []) + [pattern]
          patternBytes += pattern.surface.allocatedBytes
        }
      }
      try PatternArchive.validate(doc.patterns ?? [])
    }
    let signedCount = info.remaining == 0 ? 0 : try info.i16()
    mergedTransparency = mergedTransparency || signedCount < 0
    let count = abs(signedCount)
    guard count <= LayerLimits.maximumPhotoshopRecords else {
      throw CraftError.invalid("PSD exceeds the layer/group record limit.")
    }
    // TIFF's adapter contains layer records only. Its separately supplied raster
    // owns transparency; a negative Photoshop layer count does not add a PSD
    // merged plane to the adapter header. Ordinary PSD/PSB validation stays strict.
    let imageChannels=try PSDAuxiliaryChannels.imageChannels(channels,process:colorChannels,
      transparency:tiffComposite == nil && mergedTransparency)
    let auxiliaryCount=channels-imageChannels
    if tiffComposite != nil,auxiliaryCount>0 {throw CraftError.unsupported("TIFF auxiliary planes need TIFF ExtraSamples mapping; no channel is discarded.")}
    var records: [Record] = []
    var decodedBudget = patternBytes + (tiffComposite?.allocatedBytes ?? 0)
    for _ in 0..<count {
      let top = try info.i32()
      let left = try info.i32()
      let bottom = try info.i32()
      let right = try info.i32()
      let w = right - left
      let h = bottom - top
      guard w >= 0, h >= 0, (w == 0) == (h == 0) else {
        throw CraftError.invalid("Invalid PSD layer bounds.")
      }
      _ = try Surface(width: max(1, w), height: max(1, h))
      // Empty group/divider bounds carry no pixel samples. Charging a fake 1x1
      // tile for every record rejects a large hierarchy without owning that data.
      if w > 0 && h > 0 {
        if let paging {try paging.admitRaster(bytes:storageBytes(width:w,height:h))}
        else {decodedBudget += storageBytes(width:w,height:h)}
      }
      if colorMode != .rgb, paging == nil {
        decodedBudget += max(1, w) * max(1, h) * (colorChannels + 1) * (depth / 8)
      }
      guard decodedBudget <= 512 * 1024 * 1024, abs(Double(left)) <= 1_000_000,
        abs(Double(top)) <= 1_000_000
      else { throw CraftError.invalid("PSD layers exceed the memory or coordinate budget.") }
      let channelCount = try info.u16()
      guard (0...(colorChannels + 3)).contains(channelCount) else {
        throw CraftError.unsupported("Unsupported PSD layer channel count.")
      }
      var channelInfo: [(Int, Int)] = []
      var ids = Set<Int>()
      for _ in 0..<channelCount {
        let id = try info.i16()
        let length = try info.length(format.sectionLengthBytes)
        guard ((-3 ... -1).contains(id) || (0..<colorChannels).contains(id)), ids.insert(id).inserted else {
          throw CraftError.unsupported("Unsupported or duplicate PSD layer channel.")
        }
        channelInfo.append((id, length))
      }
      guard try info.string(4) == "8BIM" else {
        throw CraftError.invalid("Invalid PSD layer channels or blend signature.")
      }
      let key = try info.string(4)
      guard keys.contains(key) || key == "pass" else {
        throw CraftError.unsupported("PSD blend mode \(key) is not supported.")
      }
      let opacity = Float(try info.u8()) / 255
      let clipping = try info.u8()
      let flags = try info.u8()
      _ = try info.u8()
      guard clipping <= 1 else { throw CraftError.invalid("Invalid PSD clipping flag.") }
      var extra = try info.section()
      let mask = try PSDMaskRecord.read(extra.section().data)
      guard mask != nil || (!ids.contains(-2) && !ids.contains(-3)) else {
        throw CraftError.invalid("PSD mask record and channels disagree.")
      }
      let ranges = try extra.section().data
      guard
        ranges.isEmpty
          || (ranges.count % 8 == 0
            && ranges.enumerated().allSatisfy({ $0.element == ($0.offset % 4 < 2 ? 0 : 255) }))
      else { throw CraftError.unsupported("PSD Blend If ranges are not ported yet.") }
      let length = Int(try extra.u8())
      var layerName = String(data: try extra.bytes(length), encoding: .macOSRoman) ?? "Layer"
      let padding = (4 - (length + 1) % 4) % 4
      _ = try extra.bytes(padding)
      var protection = try PSDLayerProtection.decode(layerFlags: UInt8(flags), record: nil)
      var tags: [String: Data] = [:]
      var section = 0
      var sectionBlend = key
      var placedLayerID: UUID?
      while extra.remaining >= 12 {
        guard ["8BIM", "8B64"].contains(try extra.string(4)) else {
          throw CraftError.unsupported("Unknown PSD tagged-block signature.")
        }
        let tag = try extra.string(4)
        let size = try extra.length(format.tagLengthBytes(tag))
        let content = try extra.retainedBytes(size)
        if size % 2 != 0 { _ = try extra.bytes(1) }
        guard tags[tag] == nil else { throw CraftError.invalid("Duplicate PSD layer block.") }
        tags[tag] = content
        if colorMode != .rgb,
          ["TySh", "SoLd", "SoLE", "PlLd", "SoCo", "PtFl", "GdFl", "levl", "curv", "hue2", "blnc", "clrL", "vibA", "blwh", "phfl", "mixr", "selc", "expA", "thrs", "post", "grdm"].contains(tag) {
          throw CraftError.unsupported("Editable Photoshop content '\(tag)' in \(colorMode.title) is not ported yet; pixels are not silently flattened.")
        }
        switch tag {
        case "levl", "curv", "hue2", "blnc", "clrL", "vibA", "blwh", "phfl", "mixr", "selc", "expA", "thrs", "post", "grdm", "PtFl", "GdFl":
          if tag == "clrL" {
            _ = try PSDColorLookup.read(content)
          } else if PSDClassicAdjustment.keys.contains(tag) {
            _ = try PSDColorVibrance.readAdjustment(content, key: tag)
          } else if tag == "grdm" {
            _ = try PSDGradientMap.read(content)
          } else if tag == "GdFl" {
            _ = try PSDGradientFill.read(content)
          } else if tag == "PtFl" {
            _ = try PSDPatternFill.read(content)
          } else if tag == "levl" {
            _ = try PSDLevels.read(content)
          } else if tag == "curv" {
            _ = try PSDCurves.read(content)
          } else if tag == "hue2" {
            _ = try PSDHueSaturation.read(content)
          } else if tag == "thrs" || tag == "post" {
            _ = try PSDTonalSteps.read(content, kind: tag == "thrs" ? .threshold : .posterize)
          } else {
            _ = try PSDColorBalance.read(content)
          }
          // RGB gradient-stop components already use the retained document profile.
          // Admit this bounded 8/16-bit case independently of profile-dependent tone
          // layers and other gradient color models. RGB/32 descriptors remain separate.
          let profileCoordinateGradient: Bool
          if tag == "GdFl", depth != 32 {
            let fill = try PSDGradientFill.read(content)
            profileCoordinateGradient = fill.gradient.colors.allSatisfy {
              if case .rgb = $0.color { return true }; return false
            }
          } else { profileCoordinateGradient = false }
          if let profile, !profileCoordinateGradient {
            let source = CGColorSpace(iccData: profile as CFData)
            let linearLookup:Bool
            if tag == "clrL", depth == 32, source?.model == .rgb {linearLookup=try ICCProfile.isLinear(profile)}
            else {linearLookup=false}
            guard
              source == (try RasterIO.colorSpace())
                || (depth == 32 && source == CGColorSpace(name: CGColorSpace.linearSRGB))
                || linearLookup
            else {
              throw CraftError.unsupported(
                "Editable PSD fill and tone layers require an sRGB document profile.")
            }
          }
        case "SoCo":
          _ = try PSDSolidColor.read(content)
        case "vscg", "vstk", "vogk", "vowv", "sn2P":
          break // Validated together with the shape path and raster cache.
        case "vmsk", "vsms":
          _ = try PSDPaths.readMask(content, width: doc.width, height: doc.height)
        case "lsct", "lsdk":
          guard section == 0, [4, 12, 16].contains(content.count) else {
            throw CraftError.invalid("Invalid PSD group divider.")
          }
          var divider = PSDReader(data: content)
          section = try divider.u32()
          guard (0...3).contains(section) else {
            throw CraftError.invalid("Invalid PSD group kind.")
          }
          if divider.remaining >= 8 {
            guard try divider.string(4) == "8BIM" else {
              throw CraftError.invalid("Invalid group blend signature.")
            }
            sectionBlend = try divider.string(4)
            guard keys.contains(sectionBlend) || sectionBlend == "pass" else {
              throw CraftError.unsupported("Unsupported PSD group blend mode.")
            }
          }
          if divider.remaining == 4, try divider.u32() != 0 {
            throw CraftError.unsupported("PSD scene groups are not ported yet.")
          }
        case "luni":
          var unicode = PSDReader(data: content)
          let n = try unicode.u32()
          guard n <= 100_000 else { throw CraftError.invalid("PSD layer name is too long.") }
          var units: [UInt16] = []
          for _ in 0..<n { units.append(UInt16(try unicode.u16())) }
          layerName = String(decoding: units, as: UTF16.self)
        case "brst":
          let channels=try PSDChannelBlending.read(content)
          guard colorMode == .rgb || channels.isEmpty else{throw CraftError.unsupported("Non-RGB PSD channel restrictions are not implemented yet.")}
        case "lspf":
          protection = try PSDLayerProtection.decode(layerFlags: UInt8(flags), record: content)
        case "TySh": _ = try PSDText.descriptor(content)
        case "SoLd", "SoLE":
          let descriptor = try PSDSmartObjects.descriptor(content)
          if tag == "SoLd" || tags["SoLd"] == nil {
            placedLayerID = PSDSmartObjects.placedIdentifier(in: descriptor).flatMap(UUID.init(uuidString:))
          }
        case "PlLd": break
        case "artb", "artd", "abdd": _ = try PSDArtboards.layer(content,depth:pixelDepth)
        case "lyid", "lnsr", "lclr", "shmd", "fxrp", "lyvr": break
        case "clbl", "infx", "lmgm", "vmgm":
          guard content.count == 4, content.dropFirst().allSatisfy({ $0 == 0 }), content[0] <= 1
          else {
            throw CraftError.invalid("Invalid PSD blending flag.")
          }
        // Effect/group flags have no rendering effect on these plain raster layers.
        case "knko":
          guard content.count == 4, content.allSatisfy({ $0 == 0 }) else {
            throw CraftError.unsupported("PSD knockout blending is not ported yet.")
          }
        case "lfx2", "lmfx":
          _ = try PSDLayerStyles.read(content)
        case "lrFX":
          try PSDLayerStyles.validateInactiveLegacy(content)
        case "iOpa":
          guard content.count == 4, content.dropFirst().allSatisfy({ $0 == 0 }) else { throw CraftError.invalid("Invalid PSD fill opacity.") }
        default:
          throw CraftError.unsupported(
            "PSD layer '\(layerName)' contains unported data '\(tag)' (for example type, effects, groups or smart objects). Import cancelled to preserve its contents."
          )
        }
      }
      if extra.remaining > 0 {
        guard try extra.consumePadding(0) else {
          throw CraftError.invalid("Invalid layer padding.")
        }
      }
      if tags["lrFX"] != nil, tags["lfx2"] == nil, tags["lmfx"] == nil {
        throw CraftError.unsupported("Legacy Photoshop layer effects require a matching object-based record.")
      }
      let boardTags = PSDArtboards.keys.filter { tags[$0] != nil }
      guard boardTags.count<=1,boardTags.isEmpty || section==1 || section==2 else {
        throw CraftError.invalid("Artboard metadata requires one group header.")
      }
      guard
        section != 0
          || (key != "pass"
            && (tags["vscg"] != nil || tags["SoCo"] != nil || tags["PtFl"] != nil || tags["GdFl"] != nil
              || tags["clrL"] != nil || PSDClassicAdjustment.keys.contains(where: { tags[$0] != nil })
              || tags["levl"] != nil
              || tags["curv"] != nil
              || tags["hue2"] != nil || tags["blnc"] != nil || tags["thrs"] != nil
              || tags["post"] != nil || tags["grdm"] != nil
              || (flags & 16 == 0 && ids.isSuperset(of: Set(0..<colorChannels)))))
      else {
        throw CraftError.unsupported("Unsupported non-raster PSD layer.")
      }
      let contentBlocks = [
        "vscg", "clrL", "vibA", "blwh", "phfl", "mixr", "selc", "expA", "SoCo", "PtFl", "GdFl", "levl", "curv", "hue2", "blnc", "thrs", "post", "grdm",
      ]
      .filter {
        tags[$0] != nil
      }
      guard section == 0 || contentBlocks.isEmpty, contentBlocks.count <= 1
      else {
        throw CraftError.invalid("Conflicting PSD layer content blocks.")
      }
      guard !(tags["vmsk"] != nil && tags["vsms"] != nil) else {
        throw CraftError.invalid("Duplicate PSD vector masks.")
      }
      if mask != nil && !ids.contains(-2) && !ids.contains(-3)
        && tags["vmsk"] == nil && tags["vsms"] == nil
      {
        throw CraftError.invalid("PSD mask metadata without a mask.")
      }
      records.append(
        Record(
          name: layerName, x: left, y: top, w: w, h: h, channels: channelInfo,
          blend: BlendMode.allCases[keys.firstIndex(of: sectionBlend) ?? 0], opacity: opacity,
          visible: flags & 2 == 0,
          protection: protection, mask: mask, tags: tags, section: section,
          passThrough: sectionBlend == "pass", clipped: clipping == 1, placedLayerID: placedLayerID))
    }
    let embeddedFiles = try PSDSmartObjects.files(doc,
      readers: PSDSmartObjects.linkKeys.compactMap { linkViews[$0] }, paging: paging)
    let filterMasks = try PSDSmartFilters.masks(in:doc,readers:["FEid","FXid"].compactMap {filterCacheViews[$0]},paging:paging)
    var layers: [Layer] = []
    var placedIndices: [Int] = []
    var placedLayerIDs = Set<UUID>()
    var groupStack: [UUID] = []
    var linkInput=try PSDLayerLinks.Input(resourceBlocks,records:records.count),linkDividerFlags:[UUID:UInt8]=[:]
    for (recordIndex,record) in records.enumerated() {
      var planes: [Int: PSDChannelReader] = [:]
      let channelIDs = Set(record.channels.map { $0.0 })
      for (id, length) in record.channels {
        if id == -2 || id == -3 {
          guard let metadata = record.mask else {
            throw CraftError.invalid("Missing PSD mask record.")
          }
          let (b, _) = try metadata.selected(id)
          if let paging,colorMode == .rgb {try paging.admitRaster(bytes:storageBytes(width:max(1,b.width),height:max(1,b.height)))}
          else {decodedBudget += storageBytes(width: max(1, b.width), height: max(1, b.height))}
          guard decodedBudget <= 512 * 1024 * 1024 else {
            throw CraftError.invalid("PSD masks exceed the memory budget.")
          }
          let source = try info.view(length)
          if b.empty {
            let bytes = try source.data
            guard bytes == Data([0, 0]) || bytes == Data([0, 1]) else {
              throw CraftError.invalid("Invalid empty mask channel.")
            }
          } else {
            planes[id] = try PSDChannelReader(
              source, width: b.width, height: b.height, depth: depth, format: format)
          }
        } else if record.w == 0 {
          let bytes = try info.bytes(length)
          guard bytes == Data([0, 0]) || bytes == Data([0, 1]) else {
            throw CraftError.invalid("Invalid empty PSD layer channel.")
          }
        } else {
          planes[id] = try PSDChannelReader(
            info.view(length), width: record.w, height: record.h, depth: depth, format: format)
        }
      }
      if record.section == 3 {
        guard groupStack.count < 32, record.mask == nil else {
          throw CraftError.invalid("Invalid or excessive PSD group nesting.")
        }
        try planes.values.forEach { try $0.discardRemaining() }
        guard linkInput.groups[recordIndex]==0 else{throw CraftError.unsupported("Linked group-divider records require Photoshop boundary-link qualification.")}
        let group=UUID();groupStack.append(group);if linkInput.present{linkDividerFlags[group]=linkInput.flags[recordIndex]}
        continue
      }
      let hasLiveShape = PSDLiveShape.hasDefinition(record.tags)
      guard
        record.section != 0 || (!hasLiveShape && record.tags["SoCo"] != nil) || record.tags["PtFl"] != nil
          || record.tags["GdFl"] != nil
          || record.tags["clrL"] != nil || PSDClassicAdjustment.keys.contains(where: { record.tags[$0] != nil })
          || record.tags["levl"] != nil
          || record.tags["curv"] != nil || record.tags["hue2"] != nil || record.tags["blnc"] != nil
          || record.tags["thrs"] != nil || record.tags["post"] != nil || record.tags["grdm"] != nil
          || (0..<colorChannels).allSatisfy({ channelIDs.contains($0) })
      else {
        throw CraftError.invalid("Missing document color plane.")
      }
      var native: NativeModeRaster?
      if let descriptor = doc.modeDescriptor, record.section == 0 {
        native = try NativeModeRaster(width: max(1, record.w), height: max(1, record.h), mode: colorMode,
          depth: pixelDepth, profile: descriptor.profile, intent: descriptor.intent)
      }
      var surface = try Surface(
        width: native == nil ? max(1, record.w) : 1, height: native == nil ? max(1, record.h) : 1, depth: pixelDepth,
        colorEncoding: depth == 32 ? .linearRGB : .sRGB)
      let rasterRows = record.section == 0 && (hasLiveShape || record.tags["SoCo"] == nil) && record.tags["PtFl"] == nil
        && record.tags["GdFl"] == nil
        && record.tags["clrL"] == nil && !PSDClassicAdjustment.keys.contains(where: { record.tags[$0] != nil })
        && record.tags["levl"] == nil
        && record.tags["curv"] == nil && record.tags["hue2"] == nil && record.tags["blnc"] == nil
        && record.tags["thrs"] == nil && record.tags["post"] == nil && record.tags["grdm"] == nil
        ? record.h : 0
      if let paging,let descriptor=doc.modeDescriptor,native != nil,rasterRows>0 {
        native=try PSDModePaging.layer(width:record.w,height:record.h,depth:pixelDepth,
          descriptor:descriptor,planes:planes,context:paging)
      }
      if let paging,native == nil,rasterRows > 0 {
        var channels = (0..<3).map { planes[$0]! }
        if let alpha = planes[-1] { channels.append(alpha) }
        // Embedded RGB sources already composite in pages at this size.
        // Preserve implicit samples so aligned Smart Objects can stay sparse.
        if record.w > SmartObjectIO.maximumCanvasPixels / record.h {
          surface = try PSDRasterPaging.sparseLayer(width: record.w, height: record.h,
            depth: pixelDepth, channels: channels, context: paging)
        } else {
          surface = try PSDRasterPaging.layer(width: record.w, height: record.h, depth: pixelDepth,
            components: channels.count, context: paging) { _ in try channels.map { try $0.nextRow() } }
        }
      }
      for y in 0..<(paging != nil ? 0:rasterRows)
      {
        if native != nil {
          let rows = try (0..<colorChannels).map { try planes[$0]!.nextRow() }
          let alpha = try planes[-1]?.nextRow()
          for x in 0..<record.w {
            for c in 0..<colorChannels {
              let value = try PSDChannelCodec.sample(rows[c], x, depth: depth)
              try native!.set(PSDModeStorage.sample(value, mode: colorMode, component: c), component: c, index: y * record.w + x)
            }
            try native!.set(alpha.map { try PSDChannelCodec.sample($0, x, depth: depth) } ?? 1,
              component: colorChannels, index: y * record.w + x)
          }
          continue
        }
        let red = try planes[0]!.nextRow()
        let green = try planes[1]!.nextRow()
        let blue = try planes[2]!.nextRow()
        let alpha = try planes[-1]?.nextRow()
        for x in 0..<record.w {
          let i = x
          let sample = try Pixel(
            PSDChannelCodec.sample(red, i, depth: depth),
            PSDChannelCodec.sample(green, i, depth: depth),
            PSDChannelCodec.sample(blue, i, depth: depth),
            alpha.map { try PSDChannelCodec.sample($0, i, depth: depth) } ?? 1)
          if depth == 32 {
            surface.setLinearPixel(x: x, y: y, sample)
          } else {
            surface.setPixel(x: x, y: y, sample)
          }
        }
      }
      // Samples already use the retained document profile; masks are uncoloured.
      if let native { surface = try native.surface(backing:paging?.backing) }
      var layer = Layer(name: record.name, content: .raster(surface))
      if record.section == 0, let id = record.placedLayerID, placedLayerIDs.insert(id).inserted {
        layer.id = id
      }
      layer.nativeMode = native
      if let data = record.tags["GdFl"] {
        layer.content = .gradientFill(try PSDGradientFill.read(data))
      }
      if let data = record.tags["PtFl"] {
        layer.content = .patternFill(try PSDPatternFill.read(data).fill)
      }
      if let levels = record.tags["levl"] {
        layer.content = .adjustment(.levels(try PSDLevels.read(levels)))
      }
      if let curves = record.tags["curv"] {
        layer.content = .adjustment(.curves(try PSDCurves.read(curves)))
      }
      if let settings = record.tags["hue2"] {
        layer.content = .adjustment(.hueSaturation(try PSDHueSaturation.read(settings)))
      }
      for kind in TonalStepsAdjustment.Kind.allCases {
        if let settings = record.tags[PSDTonalSteps.key(kind)] {
          layer.content = .adjustment(.tonalSteps(try PSDTonalSteps.read(settings, kind: kind)))
        }
      }
      if let settings = record.tags["grdm"] {
        layer.content = .adjustment(.gradientMap(try PSDGradientMap.read(settings)))
      }
      if let data = record.tags["clrL"] { layer.content = .adjustment(.colorLookup(try PSDColorLookup.read(data))) }
      for key in PSDClassicAdjustment.keys {
        if let data = record.tags[key] { layer.content = .adjustment(try PSDColorVibrance.readAdjustment(data, key: key)) }
      }
      if let settings = record.tags["blnc"] {
        layer.content = .adjustment(.colorBalance(try PSDColorBalance.read(settings)))
      }
      if hasLiveShape {
        let shape = try PSDLiveShape.read(record.tags, x: record.x, y: record.y, cache: surface, document: doc)
        layer.content = .shape(shape)
      } else if let tag = ["vowv", "vogk", "vstk", "sn2P"].first(where: { record.tags[$0] != nil }) {
        throw CraftError.unsupported("Photoshop live shape block '\(tag)' requires a supported vector content generator.")
      } else if let fill = record.tags["SoCo"] {
        // RGB fill components use the document profile; RGB/32 uses linear light.
        let sample = try Surface(width: 1, height: 1, depth: .f32, fill: PSDSolidColor.read(fill))
        layer.content = .fill(
          try sample.interpretingSamples(as: depth == 32 ? .linearRGB : .sRGB).pixel(x: 0, y: 0))
      }
      if record.section == 1 || record.section == 2 {
        guard let id = groupStack.popLast() else {
          throw CraftError.invalid("Unbalanced PSD group divider.")
        }
        layer.id = id
        layer.content = .group(
          GroupContent(passThrough: record.passThrough, expanded: record.section == 1))
      }
      layer.parentID = groupStack.last
      layer.clipped = record.clipped
      layer.blendClippedAsGroup = record.tags["clbl"].map { $0[0] != 0 }
      layer.x = record.x
      layer.y = record.y
      layer.blendMode = record.blend
      layer.opacity = record.opacity
      layer.visible = record.visible
      layer.protection = record.protection
      layer.sourceTags = record.tags
      if let data = record.tags["lmfx"] ?? record.tags["lfx2"] { layer.style = try PSDLayerStyles.read(data, globalAngle: styleGlobalAngle, globalAltitude: importedLight?.altitude ?? 30) }
      if let fill = record.tags["iOpa"]?.first, fill != 255 {
        if layer.style == nil { layer.style = LayerStyle() }
        layer.style?.fillOpacity = Float(fill)/255
      }
      if let data=record.tags["brst"],colorMode == .rgb {
        if layer.style==nil{layer.style=LayerStyle()}
        layer.style?.restrictedChannels=try PSDChannelBlending.read(data)
      }
      if layer.shape == nil, let block = record.tags["vmsk"] ?? record.tags["vsms"] {
        layer.vectorMask = try PSDPaths.readMask(block, width: doc.width, height: doc.height)
        layer.vectorMask?.density = Float(record.mask?.vectorDensity ?? 255) / 255
        layer.vectorMask?.feather = record.mask?.vectorFeather ?? 0
      }
      if let metadata = record.mask, layer.vectorMask == nil {
        // Photoshop may save an empty, all-white generated mask even without a path.
        // Only this identity mask is safe to omit; nontrivial rasterized vectors still reject.
        let emptyOpaque =
          metadata.bounds.empty && metadata.background == 255
          && metadata.flags == 8 && metadata.real == nil
        guard metadata.vectorDensity == 255, metadata.vectorFeather == 0,
          metadata.flags & 8 == 0 || emptyOpaque
        else {
          throw CraftError.unsupported(
            "Rasterized vector-mask parameters are not yet editable in Photato.")
        }
      }
      if let metadata = record.mask,
        channelIDs.contains(-3) || (channelIDs.contains(-2) && metadata.flags & 8 == 0)
      {
        let id = channelIDs.contains(-3) ? -3 : -2
        let (b, properties) = try metadata.selected(id)
        var mask = try Surface(
          width: max(1, b.width), height: max(1, b.height), depth: pixelDepth,
          fill: Pixel(properties.outside, properties.outside, properties.outside))
        if !b.empty,let channel=planes[id],let paging,colorMode == .rgb {
          if b.width > Surface.maximumDensePixels / b.height {
            mask = try PSDRasterPaging.sparseLayer(width: b.width, height: b.height, depth: pixelDepth,
              channels: [channel], context: paging, clampMask: true)
          } else {
            mask = try PSDRasterPaging.layer(width: b.width, height: b.height, depth: pixelDepth, components: 1,
              fill: Pixel(properties.outside, properties.outside, properties.outside), mask: true, context: paging) { _ in
                [try channel.nextRow()]
              }
          }
        } else if !b.empty, let channel = planes[id] {
          for y in 0..<b.height {
            let values = try channel.nextRow()
            for x in 0..<b.width {
              let value = unit(try PSDChannelCodec.sample(values, x, depth: depth))
              mask.setPixel(x: x, y: y, Pixel(value, value, value))
            }
          }
        }
        layer.mask = mask
        layer.maskProperties = properties
        layer.maskProperties?.transform = .translation(Double(b.x - layer.x), Double(b.y - layer.y))
      }
      try planes.values.forEach { try $0.discardRemaining() }
      try PSDPatternFill.importPlacement(&layer, width: doc.width, height: doc.height)
      let placed = record.tags["SoLd"] != nil || record.tags["SoLE"] != nil || record.tags["PlLd"] != nil
      if placed {
        placedIndices.append(layers.count)
      } else {
        try PSDText.restore(&layer, in: doc)
      }
      let recognizesBackground = colorMode == .rgb || (colorMode == .grayscale && depth == 32 && tiffComposite == nil)
      if layers.isEmpty,recognizesBackground,!placed,layer.parentID==nil,!layer.isClipped,layer.x==0,layer.y==0,layer.opacity==1,layer.blendMode == .normal,
        layer.mask==nil,layer.vectorMask==nil,layer.style==nil,layer.smartObject==nil,layer.protection.locksTransparency,
        !record.channels.contains(where:{$0.0 == -1}),case .raster(let pixels)=layer.content,pixels.width==doc.width,pixels.height==doc.height,try pixels.isOpaque() {
        layer.background=true
      }
      linkInput.apply(recordIndex,to:&layer)
      if let flag=linkDividerFlags[layer.id]{layer.sourceTags?["PhLF"]=Data([flag])}
      layers.append(layer)
    }
    guard groupStack.isEmpty else { throw CraftError.invalid("Unclosed PSD layer group.") }
    // Photoshop records and the engine both store layers bottom-to-top.
    doc.layers = layers
    LayerLinks.prune(in:&doc)
    doc.activeLayerID = doc.layers.last?.id
    let deferred = DeferredPlacedLayers(indices: placedIndices, sources: embeddedFiles, filterMasks: filterMasks)
    if info.remaining > 0 {
      guard try info.consumePadding(0) else {
        throw CraftError.invalid("Unexpected layer channel tail.")
      }
    }
    // TIFF supplies its separately decoded composite. The adapter contains only
    // PSD metadata/layers; never invent a merged cache or skip unconsumed bytes.
    if let tiffComposite {
      guard r.remaining == 0, tiffComposite.width == width, tiffComposite.height == height,
        tiffComposite.depth == pixelDepth else {
        throw CraftError.invalid("TIFF composite and Photoshop layers disagree.")
      }
      if count == 0 {
        var layer = Layer(name: "Background", content: .raster(tiffComposite))
        layer.nativeMode = tiffNativeComposite
        doc.layers = [layer]; doc.activeLayerID = layer.id
      }
      return DecodedDocument(document: doc, placedLayers: deferred)
    }
    let hasNoMergedImage = PSDImageResources.hasRealMergedData(resourceBlocks) == false
    if hasNoMergedImage, count == 0 {
      throw CraftError.unsupported("This Photoshop file has neither a real merged image nor decoded layers.")
    }
    if hasNoMergedImage, auxiliaryCount == 0 {
      // An unused placeholder may be followed by embedded PSB backing capacity.
      // Saved auxiliary planes, when present, require a validated channel stream.
      _ = try r.view(r.remaining)
      return DecodedDocument(document: doc, placedLayers: deferred, readArtboards: true)
    }
    // Validate unused merged caches row-by-row, including checksum/end/trailing
    // bytes. Flattened inputs stream their planar samples into the final tiles.
    let merged = try PSDChannelReader(
      r.view(r.remaining), width: width, height: height, depth: depth, channels: channels,
      format: format)
    if count == 0, let descriptor = doc.modeDescriptor {
      if let paging {
        try paging.admitRaster(bytes:storageBytes(width:width,height:height))
        let native=try PSDModePaging.merged(width:width,height:height,depth:pixelDepth,descriptor:descriptor,
          imageChannels:imageChannels,transparency:mergedTransparency,reader:merged,context:paging)
        var layer=Layer(name:"Background",content:.raster(try native.surface(backing:paging.backing)))
        layer.nativeMode=native;doc.layers=[layer];doc.activeLayerID=layer.id
      } else {
      let cost = storageBytes(width: width, height: height) + width * height * (colorChannels + 1) * (depth / 8)
      guard cost <= 512 * 1024 * 1024 else { throw CraftError.invalid("PSD mode pixels exceed the memory budget.") }
      var native = try NativeModeRaster(width: width, height: height, mode: colorMode, depth: pixelDepth,
        profile: descriptor.profile, intent: descriptor.intent)
      for channel in 0..<imageChannels {
        for y in 0..<height {
          let row = try merged.nextRow()
          for x in 0..<width {
            let value = try PSDChannelCodec.sample(row, x, depth: depth)
            try native.set(PSDModeStorage.sample(value, mode: colorMode, component: channel), component: channel, index: y * width + x)
          }
        }
      }
      if imageChannels == colorChannels {
        for i in 0..<width * height { if i % 4096 == 0 { try Task.checkCancellation() }; try native.set(1, component: colorChannels, index: i) }
      } else if mergedTransparency, colorMode == .grayscale {
        for i in 0..<width * height {
          if i % 4096 == 0 { try Task.checkCancellation() }
          let value = native.value(component: 0, index: i), alpha = native.value(component: colorChannels, index: i)
          let p = PSDMergedSample.decode(Pixel(value, value, value, alpha))
          try native.set(p.r, component: 0, index: i)
        }
      }
      var layer = Layer(name: "Background", content: .raster(try native.surface())); layer.nativeMode = native
      doc.layers = [layer]; doc.activeLayerID = layer.id
      }
    } else if count == 0,let paging {
      try paging.admitRaster(bytes:storageBytes(width:width,height:height))
      let surface: Surface
      if width > Surface.maximumDensePixels / height, merged.hasSeekableRows {
        let channels = try merged.detachSeekablePlanes(count: imageChannels, height: height)
        surface = try PSDRasterPaging.sparseLayer(width: width, height: height, depth: pixelDepth,
          channels: channels, context: paging, mergedTransparency: mergedTransparency)
      } else {
        surface = try PSDRasterPaging.merged(width: width, height: height, depth: pixelDepth, components: imageChannels,
          transparency: mergedTransparency, context: paging, reader: merged)
      }
      let layer = Layer(name: "Background", content: .raster(surface))
      doc.layers = [layer]
      doc.activeLayerID = layer.id
    } else if count == 0 {
      guard storageBytes(width: width, height: height) <= 512 * 1024 * 1024 else {
        throw CraftError.invalid("PSD pixels exceed the memory budget.")
      }
      var surface = try Surface(
        width: width, height: height, depth: pixelDepth, fill: Pixel(0, 0, 0, 1),
        colorEncoding: depth == 32 ? .linearRGB : .sRGB)
      for channel in 0..<imageChannels {
        for y in 0..<height {
          let row = try merged.nextRow()
          for x in 0..<width {
            let value = try PSDChannelCodec.sample(row, x, depth: depth)
            var sample =
              depth == 32
              ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
            switch channel {
            case 0: sample.r = value
            case 1: sample.g = value
            case 2: sample.b = value
            default:
              sample.a = value
              if mergedTransparency { sample = PSDMergedSample.decode(sample) }
            }
            if depth == 32 {
              surface.setLinearPixel(x: x, y: y, sample)
            } else {
              surface.setPixel(x: x, y: y, sample)
            }
          }
        }
      }
      // Samples already use the retained document profile; masks are uncoloured.
      let layer = Layer(name: "Background", content: .raster(surface))
      doc.layers = [layer]
      doc.activeLayerID = layer.id
    }
    // Layered inputs do not use the merged process cache, but it remains validated.
    try merged.discardRows(merged.remainingRows - auxiliaryCount * height)
    try PSDAuxiliaryChannels.read(merged,first:imageChannels,count:auxiliaryCount,blocks:resourceBlocks,document:&doc,paging:paging)
    try merged.discardRemaining()
    return DecodedDocument(document: doc, placedLayers: deferred, readArtboards: true)
  }
  /// Editable layer documents whose process preview can be omitted.
  public static func canOmitMergedImage(_ doc: CraftDocument) -> Bool {
    doc.colorMode == .rgb && doc.inkMode == nil && doc.restrictedMode == nil
      && !doc.isChannelOnly && !doc.layers.isEmpty
  }

  public static func writeRasterLayers(
    _ doc: CraftDocument, compression: PSDCompression = .zipPrediction,
    format: PSDFileFormat = .psd, compositeCompression: PSDCompression = .raw,
    maximumBytes: Int = maximumInputBytes, maximizeCompatibility: Bool = true
  ) throws -> Data {
    guard (1...maximumInputBytes).contains(maximumBytes) else {
      throw CraftError.invalid("Invalid Photoshop Data output budget.")
    }
    let output = PSDOutput(maximumBytes: maximumBytes)
    try writeRasterLayers(doc, compression: compression, format: format,
      compositeCompression: compositeCompression, output: output, maximizeCompatibility: maximizeCompatibility)
    return output.data
  }

  /// Atomic native file output using the same serialization as API Data responses.
  public static func writeRasterLayers(
    _ doc: CraftDocument, to url: URL, compression: PSDCompression = .zipPrediction,
    format: PSDFileFormat = .psd, compositeCompression: PSDCompression = .raw,
    maximizeCompatibility: Bool = true
  ) throws {
    let maximumBytes=format == .psd ? maximumPSDFileBytes:maximumFileBytes
    let file = try AtomicFileWriter(to: url, maximumBytes: maximumBytes)
    try writeRasterLayers(
      doc, compression: compression, format: format,
      compositeCompression: compositeCompression, output: PSDOutput(file: file,maximumBytes:maximumBytes),
      maximizeCompatibility: maximizeCompatibility)
    try file.commit()
  }

  static func writeRasterLayers(
    _ doc: CraftDocument, compression: PSDCompression, format: PSDFileFormat,
    compositeCompression requestedCompositeCompression: PSDCompression = .raw,
    output: PSDOutput, includeComposite: Bool = true, maximizeCompatibility: Bool = true
  ) throws {
    try Task.checkCancellation()
    try doc.validate()
    // Resolve native sources to their embedded PSB data before the parent
    // container writer reserves its frame. The conversion can call this method.
    let linkedSources = try doc.requiresSmartObjectArchive ? PSDSmartObjects.linkedData(doc) : nil
    try writeContainer(doc, compression: compression, format: format,
      compositeCompression: requestedCompositeCompression, output: output,
      includeComposite: includeComposite, maximizeCompatibility: maximizeCompatibility,
      linkedSources: linkedSources)
  }

  private static func embeddedPreviewEncodings(_ doc: CraftDocument) -> [(compression: PSDCompression, maximizeCompatibility: Bool)] {
    var encodings: [(PSDCompression, Bool)] = [(.raw, true), (.rle, true)]
    if canOmitMergedImage(doc) { encodings.append((.rle, false)) }
    return encodings
  }

  static func writeFileBackedEmbeddedSmartObject(_ doc: CraftDocument) throws -> FileBackedSource {
    try Task.checkCancellation()
    try doc.validate()
    let linkedSources = try doc.requiresSmartObjectArchive ? PSDSmartObjects.linkedData(doc) : nil
    let limit = SmartObject.maximumFileBackedSourceBytes
    return try FileBackedSource.writing(maximumBytes: limit) { url in
      for encoding in embeddedPreviewEncodings(doc) {
        let file = try AtomicFileWriter(to: url, maximumBytes: limit)
        let output = PSDOutput(file: file, maximumBytes: limit)
        do {
          try writeContainer(doc, compression: .zipPrediction, format: .psb,
            compositeCompression: encoding.compression, output: output, includeComposite: true,
            maximizeCompatibility: encoding.maximizeCompatibility, linkedSources: linkedSources)
          try file.commit()
          return
        } catch where output.exceededByteLimit {
          file.discard()
        }
      }
      throw CraftError.unsupported("Generated PSB exceeds the file-backed embedded source limit.")
    }
  }

  /// Prefer its complete composite whenever possible and retain all layer data
  /// when an eligible child needs the compatibility-off representation.
  static func writeEmbeddedSmartObject(_ doc: CraftDocument,
    maximumBytes: Int = SmartObject.maximumArchive95SourceBytes) throws -> Data {
    try Task.checkCancellation()
    try doc.validate()
    let linkedSources = try doc.requiresSmartObjectArchive ? PSDSmartObjects.linkedData(doc) : nil
    let encodings = embeddedPreviewEncodings(doc)
    var capacities = [min(maximumBytes, SmartObject.maximumSourceBytes)]
    if maximumBytes > SmartObject.maximumSourceBytes { capacities.append(maximumBytes) }
    for capacity in capacities {
      for encoding in encodings {
        let output = PSDOutput(maximumBytes: capacity)
        do {
          try writeContainer(doc, compression: .zipPrediction, format: .psb,
            compositeCompression: encoding.compression, output: output, includeComposite: true,
            maximizeCompatibility: encoding.maximizeCompatibility, linkedSources: linkedSources)
          return output.data
        } catch where output.exceededByteLimit {
          // Retry only an overflow of this writer. Validation, corruption and
          // cancellation always propagate through the same transaction.
        }
      }
    }
    let limit = maximumBytes <= SmartObject.maximumSourceBytes ? 64 : 256
    throw CraftError.unsupported("PSD embedded source exceeds \(limit) MiB.")
  }

  @inline(never)
  private static func writeContainer(
    _ doc: CraftDocument, compression: PSDCompression, format: PSDFileFormat,
    compositeCompression requestedCompositeCompression: PSDCompression, output: PSDOutput,
    includeComposite: Bool, maximizeCompatibility: Bool, linkedSources: [Data]?
  ) throws {
    // Photoshop rejects ZIP markers in the final Image Data section.
    // Preserve RLE and raw requests, and retain Bitmap's predictor validation.
    let compositeCompression: PSDCompression
    switch requestedCompositeCompression {
    case .zip: compositeCompression = .raw
    case .zipPrediction where doc.colorMode != .bitmap: compositeCompression = .raw
    default: compositeCompression = requestedCompositeCompression
    }
    if !maximizeCompatibility, !includeComposite || !canOmitMergedImage(doc) {
      throw CraftError.unsupported("Disabling Maximize Compatibility currently requires an editable RGB PSD or PSB document.")
    }
    let unmanagedColorMetadata=try PSDColorMetadata.unmanagedRGBOutput(doc)
    let exportedLight = try PSDGlobalLight.exportLight(doc)
    guard doc.variables == nil else { throw CraftError.unsupported("Save the editable variables and data sets in Photato format. Export a data-set variation to create a PSD without template definitions.") }
    guard doc.videoTimeline == nil else { throw CraftError.unsupported("Editable video requires Photato format; PSD video interchange remains unavailable.") }
    guard doc.animation == nil else { throw CraftError.unsupported("Editable animation requires Photato format; PSD animation interchange remains unavailable.") }
    if doc.isChannelOnly {
      guard includeComposite else{throw CraftError.unsupported("A channel-only document requires its saved mask planes.")}
      try PSDMultichannelStorage.write(doc,format:format,compression:compositeCompression,to:output);return
    }
    if case .multichannel = doc.inkMode {
      guard includeComposite else { throw CraftError.unsupported("Multichannel Photoshop files require their ink planes.") }
      try PSDMultichannelStorage.write(doc, format: format, compression: compositeCompression, to: output); return
    }
    guard doc.inkMode == nil else { throw CraftError.unsupported("Editable Duotone PSD/PSB interchange is still being implemented. Save as Photato to retain ink curves.") }
    if doc.restrictedMode != nil {
      guard includeComposite else { throw CraftError.unsupported("Restricted Photoshop files require their merged index/bit plane.") }
      try PSDRestrictedStorage.write(doc, format: format, compression: compositeCompression, to: output); return
    }
    guard doc.vanishingPoint == nil else { throw CraftError.unsupported("Vanishing Point plane metadata requires Photato format. Export a rendered copy for other formats.") }
    try PSDModeStorage.validateExport(doc)
    guard !doc.hasFrames else { throw CraftError.unsupported("Editable frame PSD/PSB interchange is not implemented. Save as Photato or export a rendered image.") }
    guard includeComposite || !doc.hasArtboards else { throw CraftError.unsupported("Editable artboard TIFF interchange remains unqualified. Save as Photato, PSD or PSB.") }
    let artboardOutput = try PSDArtboards.prepare(doc)
    let compOutput = try PSDLayerComps.prepare(doc)
    let auxiliaryChannels=PSDAuxiliaryChannels.all(doc)
    guard includeComposite || auxiliaryChannels.isEmpty else {throw CraftError.unsupported("Auxiliary channel export requires complete PSD/PSB merged planes; TIFF mapping remains separate.")}
    let gray32Composite = try includeComposite && maximizeCompatibility ? PSDGray32CompositeRows(doc) : nil
    let mergedTransparency = try maximizeCompatibility && gray32Composite?.hasOpaqueBackground != true
      && PSDAuxiliaryChannels.mergedTransparency(doc)
    guard !doc.layers.isEmpty, doc.width <= format.maximumDimension,
      doc.height <= format.maximumDimension
    else {
      throw CraftError.unsupported(
        "Photoshop export requires an editable layer and dimensions within the selected format's limit."
      )
    }
    let depth = doc.depth == .u8 ? 8 : doc.depth == .u16 ? 16 : 32
    let colorChannels = doc.colorMode.componentCount
    let exportSpace = try doc.modeDescriptor.flatMap { CGColorSpace(iccData: $0.profile as CFData) } ?? ColorManagement.space(for: doc)
    var entries: [(Layer, Int)] = []
    let indexedChildren = Dictionary(grouping: doc.layers, by: \.parentID)
    func collect(_ parent: UUID?) {
      for layer in indexedChildren[parent] ?? [] {
        if let group = layer.group {
          var marker = Layer(name: "</Layer group>", content: .group(GroupContent()))
          marker.visible = false;marker.sourceTags=["PhLF":layer.sourceTags?["PhLF"] ?? Data([1])]
          entries.append((marker, 3))
          collect(layer.id)
          entries.append((layer, group.expanded ? 1 : 2))
        } else {
          entries.append((layer, 0))
        }
      }
    }
    collect(nil)
    entries = try entries.map { original, section in
      var layer = original
      if compOutput.layerIDs[layer.id] != nil {
        if layer.sourceTags == nil { layer.sourceTags = [:] }
        layer.sourceTags?["shmd"] = compOutput.tags[layer.id]
      }
      let preview: Layer
      if case .text = layer.content { preview = try PSDText.preview(layer,in:doc) }
      else if layer.shape != nil { preview = try PSDLiveShape.prepared(layer, in: doc) }
      else { preview = layer.smartObject == nil ? layer : try PSDSmartObjects.bakedPreview(layer,in:doc) }
      return (try PSDMaskExport.prepared(preview),section)
    }
    try output.text("8BPS")
    try output.n(format.rawValue, 2)
    try output.append(Data(repeating: 0, count: 6))
    try output.n(colorChannels + (mergedTransparency ? 1:0) + auxiliaryChannels.count, 2)
    try output.n(doc.height, 4)
    try output.n(doc.width, 4)
    try output.n(depth, 2)
    try output.n(PSDModeStorage.code(doc.colorMode), 2)
    // Photoshop requires HDR toning metadata for both RGB32 and Gray32 files.
    // Retain the source block on re-export, as with existing RGB32 behavior.
    try output.section(
      depth == 32 && (doc.colorMode == .rgb || doc.colorMode == .grayscale)
        ? (doc.sourceMetadata?["psdColorModeData"].flatMap { $0.isEmpty ? nil : $0 }
          ?? PSDColorMetadata.defaultHDRToning()) : Data())
    // Embed the actual working profile, independently of original-source provenance.
    var resources = PSDWriter()
    let originalResources = doc.sourceMetadata?["psdResources"] ?? Data()
    let retainedResources = compOutput.layerIDs.isEmpty ? originalResources : try PSDImageResources.blocks(originalResources).filter { $0.id != 1065 }.reduce(into: Data()) { $0.append($1.raw) }
    resources.data = try PSDImageResources.preserved(retainedResources,preservingLayerLinks:true)
    if !maximizeCompatibility { resources.data.append(PSDImageResources.versionInfo(hasRealMergedData: false)) }
    if let compResource = compOutput.resource { resources.data.append(compResource) }
    resources.data.append(try PSDAuxiliaryChannels.resources(doc,first:colorChannels+(mergedTransparency ? 1:0)))
    if let metadata = try RasterMetadata.metadata(
      doc.sourceMetadata, width: doc.width, height: doc.height, resolution: doc.pixelsPerInch,
      linear: doc.depth == .f32, profileName: doc.hasNativeModeStorage ? doc.colorMode.title : ColorManagement.name(doc),
      isSRGB: exportSpace == (try RasterIO.colorSpace())),
      let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data?
    {
      resources.data.append(PSDImageResources.block(1060, data: xmp))
    }
    guard doc.pixelsPerInch < 65536 else {
      throw CraftError.unsupported("PSD resolution exceeds its 16.16 fixed-point range.")
    }
    var resolution = PSDWriter()
    for _ in 0..<2 {
      resolution.n(Int((doc.pixelsPerInch * 65536).rounded()), 4)
      resolution.n(1, 2)
      resolution.n(1, 2)
    }
    resources.text("8BIM")
    resources.n(1005, 2)
    resources.n(0, 2)
    resources.section(resolution.data)
    if doc.profileIsUntagged == true { resources.data.append(PSDImageResources.block(1041, data: Data([1]))) }
    if doc.profileIsUntagged != true, let profile = doc.modeDescriptor?.profile ?? doc.workingICC ?? (exportSpace.copyICCData() as Data?) {
      resources.text("8BIM")
      resources.n(1039, 2)
      resources.n(0, 2)
      let data = profile as Data
      resources.section(data)
      if data.count % 2 != 0 { resources.n(0, 1) }
    }
    var pathID = 2000
    for saved in doc.paths ?? [] {
      let name = Data(
        (saved.name.data(using: .macOSRoman, allowLossyConversion: true) ?? Data("Path".utf8))
          .prefix(255))
      resources.text("8BIM")
      resources.n(saved.isWorkPath ? 1025 : pathID, 2)
      let bytes = saved.isWorkPath ? Data() : name
      resources.n(bytes.count, 1)
      resources.data.append(bytes)
      if (bytes.count + 1) % 2 != 0 { resources.n(0, 1) }
      let data = try PSDPaths.write(saved.path, width: doc.width, height: doc.height)
      resources.section(data)
      if data.count % 2 != 0 { resources.n(0, 1) }
      if !saved.isWorkPath { pathID += 1 }
    }
    try output.section(PSDGuides.applying(try PSDGlobalLight.applying(try PSDLayerLinks.applying(resources.data,entries:entries), document: doc),document:artboardOutput.guideDocument))
    guard entries.count <= Int(Int16.max) else {
      throw CraftError.invalid("PSD has too many layer records.")
    }
    let maskLength = try output.reserveLength(format.sectionLengthBytes)
    if depth != 8 {
      try output.n(0, format.sectionLengthBytes)
      try output.n(0, 4)
      try output.text(format.tagSignature(depth == 16 ? "Lr16" : "Lr32"))
      try output.text(depth == 16 ? "Lr16" : "Lr32")
    }
    let records = output
    let recordsLength = try output.reserveLength(format.sectionLengthBytes)
    let recordsStart = output.count
    var channelLengthOffsets: [[Int]] = []
    try records.n(mergedTransparency ? -entries.count:entries.count, 2)  // Negative count declares merged transparency.
    for (layer, section) in entries {
      let shapeTags = try layer.shape == nil ? [] : PSDLiveShape.write(layer, document: doc)
      let shapeBounds = try layer.shape?.renderBounds()
      let surface: Surface?
      let isFill: Bool
      isFill = layer.isCanvasFill
      if case .raster(let pixels) = layer.content, layer.affine == nil {
        surface = pixels
      } else if shapeBounds != nil {
        surface = nil
      } else if case .fill(let color) = layer.content {
        _ = try PSDSolidColor.write(color)
        surface = nil
      } else if case .gradientFill(let fill) = layer.content {
        _ = try PSDGradientFill.write(fill)
        surface = nil
      } else if case .patternFill(let fill) = layer.content {
        guard let pattern = doc.pattern(fill.patternID) else {
          throw CraftError.invalid("Missing embedded pattern.")
        }
        _ = try PSDPatternFill.write(fill, pattern: pattern)
        surface = nil
      } else if layer.isGroup {
        surface = nil
      } else if case .adjustment(.levels(let levels)) = layer.content {
        _ = try PSDLevels.write(levels)
        surface = nil
      } else if case .adjustment(.curves(let curves)) = layer.content {
        _ = try PSDCurves.write(curves)
        surface = nil
      } else if case .adjustment(.hueSaturation(let settings)) = layer.content {
        _ = try PSDHueSaturation.write(settings)
        surface = nil
      } else if case .adjustment(.gradientMap(let settings)) = layer.content {
        guard depth != 32 else {
          throw CraftError.unsupported(
            "Photoshop does not support editable Gradient Map layers in 32-bit documents. Export a flattened image or use an 8- or 16-bit document."
          )
        }
        _ = try PSDGradientMap.write(settings)
        surface = nil
      } else if case .adjustment(.tonalSteps(let settings)) = layer.content {
        _ = try PSDTonalSteps.write(settings)
        surface = nil
      } else if case .adjustment(.colorLookup(let settings)) = layer.content {
        _ = try PSDColorLookup.write(settings); surface = nil
      } else if case .adjustment(.modern) = layer.content {
        throw CraftError.unsupported("Modern adjustment descriptors are not yet qualified for editable PSD/PSB. Save the Photato65 original or explicitly export a flattened copy.")
      } else if case .adjustment(.classic(let settings)) = layer.content {
        _ = try PSDClassicAdjustment.write(settings)
        surface = nil
      } else if case .adjustment(.colorBalance(let settings)) = layer.content {
        _ = try PSDColorBalance.write(settings)
        surface = nil
      } else {
        throw CraftError.unsupported(
          "PSD export currently preserves pixel layers, solid-color, gradient and pattern fills, Levels, Curves, Hue/Saturation, Color Balance, Threshold, Posterize, Gradient Map, groups and masks. Keep the .photato original; other live layers are not yet supported."
        )
      }
      let originX = isFill ? 0 : layer.x
      let originY = isFill ? 0 : layer.y
      let width = isFill ? doc.width : (shapeBounds?.width ?? surface?.width ?? 0)
      let height = isFill ? doc.height : (shapeBounds?.height ?? surface?.height ?? 0)
      try records.n(height == 0 ? 0 : originY, 4)
      try records.n(width == 0 ? 0 : originX, 4)
      try records.n(height == 0 ? 0 : originY + height, 4)
      try records.n(width == 0 ? 0 : originX + width, 4)
      let channelIDs = Array(0..<colorChannels) + (layer.isBackground ? []:[-1]) + (layer.mask == nil ? [] : [-2])
      try records.n(channelIDs.count, 2)
      var lengths: [Int] = []
      for id in channelIDs {
        try records.n(id, 2)
        lengths.append(try records.reserveLength(format.sectionLengthBytes))
      }
      channelLengthOffsets.append(lengths)
      try records.text("8BIM")
      let blendKey =
        section != 3 && layer.group?.passThrough == true
        ? "pass" : keys[BlendMode.allCases.firstIndex(of: layer.blendMode) ?? 0]
      try records.text(blendKey)
      try records.n(Int((unit(layer.opacity) * 255).rounded()), 1)
      try records.n(layer.isClipped ? 1 : 0, 1)
      let adjustmentFlags: Int
      if case .adjustment = layer.content { adjustmentFlags = 24 } else { adjustmentFlags = 0 }
      try records.n((layer.visible ? 0 : 2) | (layer.protection.locksTransparency ? 1 : 0) | adjustmentFlags, 1)
      try records.n(0, 1)
      var extra = PSDWriter()
      if layer.mask != nil || layer.vectorMask != nil {
        let mask = layer.mask
        let p = layer.effectiveMaskProperties
        let t = layer.maskCoordinateTransform
        guard t.a == 1, t.b == 0, t.c == 0, t.d == 1, t.tx == t.tx.rounded(),
          t.ty == t.ty.rounded(), p.outside == 0 || p.outside == 1
        else {
          throw CraftError.unsupported(
            "PSD export of resampled or transformed mask bounds is not ported yet. Save the editable .photato original."
          )
        }
        var m = PSDWriter()
        m.n(Int(t.ty), 4)
        m.n(Int(t.tx), 4)
        m.n(Int(t.ty) + (mask?.height ?? 0), 4)
        m.n(Int(t.tx) + (mask?.width ?? 0), 4)
        m.n(p.outside == 0 ? 0 : 255, 1)
        let parameters = p.density != 1 || p.feather != 0 || layer.vectorMask != nil
        m.n(
          (p.linked ? 0 : 1) | (p.enabled ? 0 : 2) | (p.inverted ? 4 : 0) | (parameters ? 16 : 0), 1
        )
        if parameters {
          m.n(layer.vectorMask == nil ? 3 : 15, 1)
          m.n(Int((p.density * 255).rounded()), 1)
          m.n(Int(truncatingIfNeeded: p.feather.bitPattern), 8)
          if let vector = layer.vectorMask {
            m.n(Int((vector.density * 255).rounded()), 1)
            m.n(Int(truncatingIfNeeded: vector.feather.bitPattern), 8)
          }
        } else {
          m.n(0, 2)
        }
        extra.section(m.data)
      } else {
        extra.n(0, 4)
      }
      extra.n(0, 4)
      let name = Data(layer.name.utf8.prefix(255))
      extra.n(name.count, 1)
      extra.data.append(name)
      for _ in 0..<((4 - (name.count + 1) % 4) % 4) { extra.n(0, 1) }
      let unicode = Array(layer.name.utf16)
      var text = PSDWriter()
      text.n(unicode.count, 4)
      for unit in unicode { text.n(Int(unit), 2) }
      extra.text("8BIM")
      extra.text("luni")
      extra.section(text.data)
      if section != 0 {
        var divider = PSDWriter()
        divider.n(section, 4)
        divider.text("8BIM")
        divider.text(blendKey)
        extra.text("8BIM")
        extra.text("lsct")
        extra.section(divider.data)
      }
      if let (key,data) = artboardOutput.layers[layer.id] {
        extra.text(format.tagSignature(key)+key)
        extra.section(data,lengthBytes:format.tagLengthBytes(key))
        if data.count%2 != 0 { extra.n(0,1) }
      }
      extra.text("8BIM")
      extra.text("clbl")
      extra.section(Data([layer.clipsBlendAsGroup ? 1 : 0, 0, 0, 0]))
      if let mask = layer.vectorMask {
        extra.text("8BIM")
        extra.text("vmsk")
        extra.section(try PSDPaths.writeMask(mask, width: doc.width, height: doc.height))
      }
      for (key, data) in shapeTags {
        extra.text(format.tagSignature(key) + key)
        extra.section(data, lengthBytes: format.tagLengthBytes(key))
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if let channels=layer.style?.restrictedChannels {
        extra.text("8BIM");extra.text("brst");extra.section(try PSDChannelBlending.write(channels))
      }
      if let style = layer.style {
        let original = layer.sourceTags?["lmfx"] ?? layer.sourceTags?["lfx2"]
        let data = try PSDLayerStyles.write(style, sharedLight: exportedLight, original: original)
        extra.text("8BIM"); extra.text("lfx2"); extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
        extra.text("8BIM"); extra.text("iOpa"); extra.section(Data([UInt8((style.fillOpacity * 255).rounded()), 0, 0, 0]))
      }
      if case .gradientFill(let fill) = layer.content {
        let data = try PSDGradientFill.write(fill, original: layer.sourceTags?["GdFl"])
        extra.text("8BIM")
        extra.text("GdFl")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .patternFill(let fill) = layer.content, let pattern = doc.pattern(fill.patternID) {
        let placement = try PSDPatternFill.exportPlacement(
          layer, width: doc.width, height: doc.height)
        let data = try PSDPatternFill.write(
          placement, pattern: pattern, original: layer.sourceTags?["PtFl"])
        extra.text("8BIM")
        extra.text("PtFl")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .fill(let color) = layer.content {
        let fill = try PSDSolidColor.write(
          depth == 32 ? SRGBTransfer.linear(color) : color,
          original: layer.sourceTags?["SoCo"])
        extra.text("8BIM")
        extra.text("SoCo")
        extra.section(fill)
        if fill.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.levels(let levels)) = layer.content {
        extra.text("8BIM")
        extra.text("levl")
        extra.section(try PSDLevels.write(levels, original: layer.sourceTags?["levl"]))
      }
      if case .adjustment(.curves(let curves)) = layer.content {
        let data = try PSDCurves.write(curves, original: layer.sourceTags?["curv"])
        extra.text("8BIM")
        extra.text("curv")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.hueSaturation(let settings)) = layer.content {
        extra.text("8BIM")
        extra.text("hue2")
        extra.section(
          try PSDHueSaturation.write(
            settings, original: layer.sourceTags?["hue2"], includeRangeColors: true))
      }
      if case .adjustment(.gradientMap(let settings)) = layer.content {
        extra.text("8BIMgrdm")
        extra.section(try PSDGradientMap.write(settings, original: layer.sourceTags?["grdm"]))
      }
      if case .adjustment(.tonalSteps(let settings)) = layer.content {
        let key = PSDTonalSteps.key(settings.kind)
        extra.text("8BIM")
        extra.text(key)
        extra.section(try PSDTonalSteps.write(settings, original: layer.sourceTags?[key]))
      }
      if case .adjustment(.colorLookup(let settings)) = layer.content {
        let data = try PSDColorLookup.write(settings, original: layer.sourceTags?["clrL"])
        extra.text("8BIMclrL"); extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.classic(let settings)) = layer.content {
        let key = PSDClassicAdjustment.key(settings.kind)
        let data = try PSDClassicAdjustment.write(settings, original: layer.sourceTags?[key])
        extra.text("8BIM"); extra.text(key); extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      if case .adjustment(.colorBalance(let settings)) = layer.content {
        let data = try PSDColorBalance.write(settings, original: layer.sourceTags?["blnc"])
        extra.text("8BIM")
        extra.text("blnc")
        extra.section(data)
        if data.count % 2 != 0 { extra.n(0, 1) }
      }
      for (tag, content) in (layer.sourceTags ?? [:]).sorted(by: { $0.key < $1.key })
      where ![
        "PhLG", "PhLF", "PhFE", "artb", "artd", "abdd", "luni", "lspf", "lyid", "lsct", "lsdk", "clbl", "vmsk", "vsms", "SoCo", "levl", "curv",
        "hue2", "blnc", "clrL", "vibA", "blwh", "phfl", "mixr", "selc", "expA", "thrs", "post", "grdm", "PtFl", "GdFl", "lfx2", "lmfx", "iOpa",
      ]
      .contains(tag) && !shapeTags.contains(where: { $0.0 == tag }) {
        extra.text(format.tagSignature(tag))
        extra.text(tag)
        extra.section(content, lengthBytes: format.tagLengthBytes(tag))
        if content.count % 2 != 0 { extra.n(0, 1) }
      }
      if let id = compOutput.layerIDs[layer.id] {
        var identifier = PSDWriter(); identifier.n(Int(id), 4)
        extra.text("8BIMlyid"); extra.section(identifier.data)
      } else if let identifier = layer.sourceTags?["lyid"], identifier.count == 4 {
        extra.text("8BIMlyid"); extra.section(identifier)
      }
      var lock = PSDWriter()
      lock.data.append(try PSDLayerProtection.encode(layer.protection))
      extra.text("8BIM")
      extra.text("lspf")
      extra.section(lock.data)
      try records.section(extra.data)
    }
    // Write each channel directly, then patch its declared size in the earlier record.
    for (entryIndex, entry) in entries.enumerated() {
      try Task.checkCancellation()
      let layer = entry.0
      let surface: Surface?
      if case .raster(let pixels) = layer.content {
        surface = pixels
      } else if layer.isCanvasFill || layer.shape != nil {
        surface = try Renderer.layerSurface(layer, in: doc)
      } else {
        surface = nil
      }
      let storedLayerRows = layer.nativeMode == nil ? surface.flatMap {
        PSDStoredRows($0, kind: .layer,
          minimumPixels: $0.tileCount == 0 ? SmartObjectIO.maximumCanvasPixels : Surface.maximumDensePixels)
      } : nil
      let storedMaskRows = layer.mask.flatMap { PSDStoredRows($0, kind: .mask) }
      let nativeSupports: [PSDNativeRowSupport?]
      if let native = layer.nativeMode, native.requiresPagedArchive {
        nativeSupports = try (0...native.mode.componentCount).map { component in
          try PSDNativeRowSupport(width: native.width, height: native.height,
            streams: [native.storedComponentRanges(component)])
        }
      } else { nativeSupports = [] }
      for channel in 0..<channelLengthOffsets[entryIndex].count {
        let start = output.count
        let isMask = channel == colorChannels + 1
        let source = isMask ? layer.mask : surface
        if let source {
          let storedRows = isMask ? storedMaskRows : storedLayerRows
          let nativeSupport = !isMask && nativeSupports.indices.contains(channel) ? nativeSupports[channel] : nil
          let repeatedRows: ((Int) -> Int)?
          if let storedRows { repeatedRows = { storedRows.repeatedRows(from: $0) } }
          else if let nativeSupport { repeatedRows = { nativeSupport.repeatedRows(from: $0) } }
          else { repeatedRows = nil }
          try PSDChannelWriter.write(
            width: source.width, height: source.height, depth: depth,
            compression: compression, format: format, to: output,
            repeatedRows: repeatedRows
          ) { y in
            if let storedRows { return try storedRows.row(y, channel: channel, depth: depth) }
            if let nativeSupport, let native = layer.nativeMode {
              return try nativeSupport.row(y, depth: depth) { index in
                PSDModeStorage.sample(native.value(component: channel, index: index), mode: native.mode, component: channel)
              }
            }
            var row: [UInt8] = []
            row.reserveCapacity(source.width * (depth / 8))
            for x in 0..<source.width {
              let value: Float
              if !isMask, let native = layer.nativeMode {
                value = PSDModeStorage.sample(native.value(component: channel, index: y * source.width + x), mode: native.mode, component: channel)
              } else {
                let p = !isMask && depth == 32 ? source.linearPixel(x: x, y: y) : source.pixel(x: x, y: y)
                value = isMask ? unit(p.r) : [p.r, p.g, p.b, p.a][channel]
              }
              try PSDChannelCodec.append(value, depth: depth, to: &row)
            }
            return row
          }
        } else {
          try output.n(0, 2)
        }
        try output.patchLength(
          output.count - start, at: channelLengthOffsets[entryIndex][channel],
          width: format.sectionLengthBytes)
      }
    }
    while (output.count - recordsStart) % 4 != 0 { try output.n(0, 1) }
    try output.finishLength(recordsLength, width: format.sectionLengthBytes)
    if depth == 8 { try output.n(0, 4) }
    let layerMask = output
    let savedNames = (doc.paths ?? []).filter { !$0.isWorkPath }.map(\.name)
    for (key, data) in try PSDPatterns.exportBlocks(doc) {
      try layerMask.text(format.tagSignature(key))
      try layerMask.text(key)
      try layerMask.section(data, lengthBytes: format.tagLengthBytes(key))
      for _ in 0..<((4 - data.count % 4) % 4) { try layerMask.n(0, 1) }
    }
    if !savedNames.isEmpty {
      let names = PSDPaths.writeNames(savedNames)
      try layerMask.text(format.tagSignature("pths"))
      try layerMask.text("pths")
      try layerMask.section(names, lengthBytes: format.tagLengthBytes("pths"))
      for _ in 0..<((4 - names.count % 4) % 4) { try layerMask.n(0, 1) }
    }
    // Annotations do not participate in raster rendering. Retain their original
    // bytes, including unknown annotation kinds, until native note editing exists.
    if let annotations = doc.sourceMetadata?["psdGlobal_Anno"] {
      try layerMask.text(format.tagSignature("Anno") + "Anno")
      try layerMask.section(annotations, lengthBytes: format.tagLengthBytes("Anno"))
      for _ in 0..<((4 - annotations.count % 4) % 4) { try layerMask.n(0, 1) }
    }
    if let metadata=unmanagedColorMetadata {
      try layerMask.text(format.tagSignature("OCIO") + "OCIO")
      try layerMask.section(metadata,lengthBytes:format.tagLengthBytes("OCIO"))
      for _ in 0..<((4-metadata.count%4)%4){try layerMask.n(0,1)}
    }
    if let overlay = doc.sourceMetadata?["psdGlobal_LMsk"] {
      guard (13...16).contains(overlay.count), overlay[12] == 128 else {
        throw CraftError.unsupported("Unrecognized PSD user-mask display metadata.")
      }
      try layerMask.text(format.tagSignature("LMsk"))
      try layerMask.text("LMsk")
      try layerMask.section(overlay, lengthBytes: format.tagLengthBytes("LMsk"))
      for _ in 0..<((4 - overlay.count % 4) % 4) { try layerMask.n(0, 1) }
    }
    if let linked = linkedSources {
      try layerMask.text(format.tagSignature("lnk2") + "lnk2")
      let width = format.tagLengthBytes("lnk2"), mark = try layerMask.reserveLength(width)
      for chunk in linked { try layerMask.append(chunk) }
      let length = layerMask.count - mark - width
      try layerMask.finishLength(mark, width: width)
      for _ in 0..<((4 - length % 4) % 4) { try layerMask.n(0, 1) }
    }
    if doc.layers.contains(where: { $0.smartFilters != nil }) {
      try layerMask.text(format.tagSignature("FEid") + "FEid")
      let width=format.tagLengthBytes("FEid"),mark=try layerMask.reserveLength(width),start=layerMask.count
      try PSDSmartFilters.writeCache(doc,to:layerMask)
      let length=layerMask.count-start;try layerMask.finishLength(mark,width:width)
      for _ in 0..<((4 - length % 4) % 4) {try layerMask.n(0,1)}
    }
    if let (key,data) = artboardOutput.global {
      try layerMask.text(format.tagSignature(key)+key)
      try layerMask.section(data,lengthBytes:format.tagLengthBytes(key))
      for _ in 0..<((4-data.count%4)%4) { try layerMask.n(0,1) }
    }
    try output.finishLength(maskLength, width: format.sectionLengthBytes)
    if !includeComposite { return }
    let storedAuxiliary = auxiliaryChannels.map(PSDAuxiliaryChannels.storedRows)
    func auxiliaryRow(_ index: Int, _ y: Int) throws -> [UInt8] {
      if let stored = storedAuxiliary[index] { return try stored.row(y, channel: 0, depth: depth) }
      return try PSDAuxiliaryChannels.row(auxiliaryChannels[index], y: y, depth: depth)
    }
    if !maximizeCompatibility {
      // Retain the observed white RGB/8 placeholder. Integer white and floating
      // zero both PackBits-encode as single-byte runs. No process preview is used.
      let widthBytes = doc.width * (depth / 8)
      let placeholder = [UInt8](repeating: depth == 32 ? 0 : 255, count: widthBytes)
      let largestPackedRow = widthBytes + (widthBytes + 127) / 128
      // A wide, textured float auxiliary row can exceed the PSD RLE field.
      let storage: PSDCompression = format == .psd && !auxiliaryChannels.isEmpty
        && largestPackedRow > Int(UInt16.max) ? .raw : .rle
      try PSDChannelWriter.write(width: doc.width, height: doc.height, depth: depth, compression: storage,
        channels: colorChannels + auxiliaryChannels.count, format: format, to: output, repeatedRows: { index in
          let channel = index / doc.height, y = index % doc.height
          if channel < colorChannels { return doc.height - y }
          return storedAuxiliary[channel - colorChannels]?.repeatedRows(from: y) ?? 1
        }) { index in
          let channel = index / doc.height
          return channel < colorChannels ? placeholder : try auxiliaryRow(channel - colorChannels, index % doc.height)
        }
      return
    }
    let imageChannels = colorChannels + (mergedTransparency ? 1 : 0)
    if compositeCompression == .raw {
      let compositeBytes = try PSDChannelCodec.streamByteCount(width: doc.width, height: doc.height,
        depth: depth, channels: imageChannels + auxiliaryChannels.count)
      try output.requireCapacity(compositeBytes + 2)
    }
    let pagedComposite = doc.colorMode == .rgb && (doc.width*doc.height > Surface.maximumDensePixels
      || Renderer.groupCompositionExceedsBudget(doc,region:.init(x:0,y:0,width:doc.width,height:doc.height)))
      ? PSDCompositeRows(doc,transparency:mergedTransparency):nil
    let sparseComposite = try pagedComposite?.sparseRows()
    // An aligned opaque CMYK layer already is the composite in its native space.
    // Separate spot channels are emitted independently below.
    let retainedCMYK = doc.colorMode == .cmyk && doc.layers.count == 1
      && InkModeInput.isAlignedRaster(doc.layers[0], in: doc)
      && doc.layers[0].nativeMode?.isOpaque == true ? doc.layers[0].nativeMode : nil
    let retainedCMYKRows: PSDNativeRowSupport?
    if let retainedCMYK, retainedCMYK.requiresPagedArchive {
      retainedCMYKRows = try PSDNativeRowSupport(width: doc.width, height: doc.height,
        streams: (0..<colorChannels).map(retainedCMYK.storedComponentRanges))
    } else { retainedCMYKRows = nil }
    let pagedModeComposite = try gray32Composite == nil && retainedCMYK == nil && doc.modeDescriptor != nil
      && (doc.width > NativeModeRaster.maximumPixels / doc.height || doc.layers.contains(where: { $0.nativeMode?.requiresPagedArchive == true }))
      ? PSDModeCompositeRows(doc) : nil
    let composite = try gray32Composite == nil && pagedComposite == nil && pagedModeComposite == nil && retainedCMYK == nil
      ? Renderer.composite(doc) : nil
    let nativeComposite: NativeModeRaster?
    if let retainedCMYK {
      nativeComposite = retainedCMYK
    } else if let composite, let descriptor = doc.modeDescriptor {
      nativeComposite = try NativeModeRaster.converting(composite, to: descriptor.mode,
        depth: doc.depth, profile: descriptor.profile, intent: descriptor.intent)
    } else {
      nativeComposite = nil
    }
    let repeatedRows: ((Int) -> Int)?
    if sparseComposite != nil || gray32Composite?.usesSparseRows == true || retainedCMYKRows != nil
      || storedAuxiliary.contains(where: { $0 != nil }) {
      repeatedRows = { index in
        let channel = index / doc.height, y = index % doc.height
        if channel >= imageChannels {
          return storedAuxiliary[channel - imageChannels]?.repeatedRows(from: y) ?? 1
        }
        return gray32Composite?.repeatedRows(from: y) ?? sparseComposite?.repeatedRows(from: y)
          ?? retainedCMYKRows?.repeatedRows(from: y) ?? 1
      }
    } else { repeatedRows = nil }
    try PSDChannelWriter.write(width: doc.width, height: doc.height, depth: depth,
      compression: compositeCompression, channels: imageChannels + auxiliaryChannels.count,
      format: format, to: output, repeatedRows: repeatedRows) { index in
        let channel = index / doc.height, y = index % doc.height
        try Task.checkCancellation()
        if channel >= imageChannels { return try auxiliaryRow(channel - imageChannels, y) }
        if let gray32Composite { return try gray32Composite.row(y, channel: channel, transparency: mergedTransparency) }
        if let sparseComposite { return try sparseComposite.row(y, channel: channel, depth: depth) }
        if let pagedComposite {return try pagedComposite.row(y,channel:channel,depth:depth)}
        if let pagedModeComposite {return try pagedModeComposite.row(y,channel:channel,depth:depth)}
        if let retainedCMYK, let retainedCMYKRows {
          return try retainedCMYKRows.row(y, depth: depth) { position in
            PSDModeStorage.mergedSample(retainedCMYK, component: channel, index: position)
          }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(doc.width * (depth / 8))
        for x in 0..<doc.width {
          let value: Float
          if let nativeComposite {
            value = PSDModeStorage.mergedSample(nativeComposite, component: channel, index: y * doc.width + x)
          } else {
            let p = depth == 32
              ? PSDMergedSample.encodeLinear(composite!.linearPixel(x: x, y: y),transparency:mergedTransparency)
              : PSDMergedSample.encode(composite!.pixel(x: x, y: y), depth: depth)
            value = [p.r, p.g, p.b, p.a][channel]
          }
          try PSDChannelCodec.append(
            value, depth: depth,
            to: &bytes)
        }
        return bytes
    }
  }

  package static func supportsLiveShape(_ layer: Layer, in document: CraftDocument) -> Bool {
    PSDLiveShape.supported(layer, in: document)
  }
}
