import Foundation
import ImageIO
import PhotoCraftCore

/// Adobe's public mode0/mode2 framing and resource1046/1047 layout. The merged
/// plane is the document; no synthetic RGB layers are emitted for these modes.
enum PSDRestrictedStorage {
  static func read(_ source: PSDReader, width: Int, height: Int, depth: Int, mode: Int,
    channels: Int, format: PSDFileFormat, name: String) throws -> CraftDocument {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= PaletteQuantization.maximumPixels / height, channels == 1,
      (mode == 0 && depth == 1) || (mode == 2 && depth == 8) else {
      throw CraftError.unsupported("Indexed/Bitmap Photoshop files require one bounded8-bit index or1-bit plane; auxiliary channels remain unsupported.")
    }
    var r = source, color = try r.section()
    guard color.remaining == (mode == 2 ? 768 : 0) else { throw CraftError.invalid("Invalid Photoshop palette section.") }
    let colorData = try color.data
    let resources = try r.section()
    guard resources.remaining <= PSDImageResources.maximumBytes else { throw CraftError.invalid("Excessive Photoshop image resources.") }
    let resourceData = try resources.data, blocks = try PSDImageResources.blocks(resourceData)
    for id in [1005, 1039, 1046, 1047] {
      guard blocks.filter({ $0.id == id }).count <= 1 else { throw CraftError.invalid("Duplicate Photoshop restricted-mode resource.") }
    }
    var layerSection = try r.section(lengthBytes: format.sectionLengthBytes)
    if layerSection.remaining > 0 {
      var info = try layerSection.section(lengthBytes: format.sectionLengthBytes)
      if info.remaining > 0 {
        guard try info.i16() == 0, info.remaining <= 3, try info.consumePadding(0) else {
          throw CraftError.unsupported("Layered Indexed/Bitmap Photoshop files are not represented by a flat restricted document.")
        }
      }
      if layerSection.remaining > 0 {
        let mask = try layerSection.section()
        guard mask.remaining == 0 else { throw CraftError.unsupported("Restricted Photoshop global masks are not supported yet.") }
      }
      guard layerSection.remaining <= 3, try layerSection.consumePadding(0) else {
        throw CraftError.unsupported("Additional restricted Photoshop layer records are not supported yet.")
      }
    }
    let rowBytes = mode == 0 ? (width + 7) / 8 : width
    var compression = r
    if mode == 0, try compression.u16() == PSDCompression.zipPrediction.rawValue {
      throw CraftError.unsupported("ZIP prediction is not defined for1-bit Photoshop samples.")
    }
    // Packed bits are compressed as bytes, with row lengths rounded up.
    let reader = try PSDChannelReader(r, width: rowBytes, height: height, depth: 8, format: format)
    var data = Data(); data.reserveCapacity(rowBytes * height)
    while reader.remainingRows > 0 { try Task.checkCancellation(); data.append(contentsOf: try reader.nextRow()) }
    let profile = blocks.first { $0.id == 1039 }?.data
    var document = try CraftDocument(width: width, height: height, name: name)
    if mode == 2 {
      var count = 256, transparent: Int?
      if let block = blocks.first(where: { $0.id == 1046 }) {
        guard block.data.count == 2 else { throw CraftError.invalid("Invalid indexed palette count resource.") }
        var value = PSDReader(data: block.data); count = try value.u16()
        guard (1...256).contains(count) else { throw CraftError.invalid("Invalid indexed palette count.") }
      }
      if let block = blocks.first(where: { $0.id == 1047 }) {
        guard block.data.count == 2 else { throw CraftError.invalid("Invalid indexed transparency resource.") }
        var value = PSDReader(data: block.data); let index = try value.u16()
        if index != 65535 { guard index < count else { throw CraftError.invalid("Indexed transparency is outside the palette.") }; transparent = index }
      }
      let palette = (0..<count).map { PaletteColor(colorData[$0], colorData[256 + $0], colorData[512 + $0]) }
      document = try document.replacingRestrictedMode(.indexed(IndexedRaster(width: width, height: height,
        palette: palette, indices: data, transparentIndex: transparent, profile: profile)))
    } else {
      if width % 8 != 0 { for y in 0..<height { data[(y + 1) * rowBytes - 1] &= UInt8(truncatingIfNeeded: 0xff << (8 - width % 8)) } }
      if let profile { try NativeModeProfile.validate(profile, mode: .grayscale, depth: .u8) }
      document = try document.replacingRestrictedMode(.bitmap(BitmapRaster(width: width, height: height, bits: data)))
    }
    document.sourceICC = profile; document.sourceMetadata = ["psdResources": resourceData, "psdColorModeData": colorData]
    for block in blocks {
      if block.id == 1005 {
        guard block.data.count == 16 else { throw CraftError.invalid("Invalid Photoshop resolution resource.") }
        var value = PSDReader(data: block.data)
        let x = Double(try value.u32()) / 65536, xu = try value.u16(); _ = try value.u16()
        let y = Double(try value.u32()) / 65536, yu = try value.u16(); _ = try value.u16()
        guard (1...2).contains(xu), (1...2).contains(yu), x >= 1, abs(x - y) < 0.01 else {
          throw CraftError.unsupported("Non-square Photoshop resolution is not represented by this document.")
        }; document.resolution = x
      }
    }
    let savedPaths = try paths(blocks, width: width, height: height)
    document.paths = savedPaths.isEmpty ? nil : savedPaths
    document.globalLight = try PSDGlobalLight.read(blocks)
    try PSDGuides.read(into:&document)
    try r.validateUnchanged(); try document.validate(); return document
  }
  static func write(_ document: CraftDocument, format: PSDFileFormat, compression: PSDCompression, to output: PSDOutput) throws {
    try document.validate()
    guard let raster = document.restrictedMode, document.width <= format.maximumDimension,
      document.height <= format.maximumDimension, document.pixelsPerInch < 65536,
      document.vanishingPoint == nil else { throw CraftError.unsupported("Restricted Photoshop output exceeds supported geometry or metadata.") }
    if case .bitmap = raster, compression == .zipPrediction { throw CraftError.unsupported("Use Raw, RLE or ZIP for1-bit Photoshop files.") }
    try output.text("8BPS"); try output.n(format.rawValue, 2); try output.append(Data(repeating: 0, count: 6))
    try output.n(1, 2); try output.n(document.height, 4); try output.n(document.width, 4)
    try output.n(document.bitsPerChannel, 2); try output.n(document.colorMode == .indexed ? 2 : 0, 2)
    var color = Data()
    let resources = try PSDGlobalLight.applying(resources(document), document: document)
    var bytes: Data, rowBytes: Int
    switch raster {
    case .indexed(let r):
      color = Data(count: 768)
      for (i, c) in r.palette.enumerated() { color[i] = c.red; color[256 + i] = c.green; color[512 + i] = c.blue }
      bytes = r.indices; rowBytes = r.width
    case .bitmap(let r): bytes = r.bits; rowBytes = r.rowStride
    }
    try output.section(color); try output.section(resources); try output.section(Data(), lengthBytes: format.sectionLengthBytes)
    try PSDChannelWriter.write(width: rowBytes, height: document.height, depth: 8,
      compression: compression, format: format, to: output) { row in Array(bytes[row * rowBytes..<(row + 1) * rowBytes]) }
  }
  static func resources(_ document: CraftDocument, includeResolution: Bool = true) throws -> Data {
    var resources = try PSDImageResources.preserved(document.sourceMetadata?["psdResources"] ?? Data())
    if case .indexed(let r) = document.restrictedMode {
      var count = PSDWriter(); count.n(r.palette.count, 2); resources += PSDImageResources.block(1046, data: count.data)
      if let t = r.transparentIndex { var value = PSDWriter(); value.n(t, 2); resources += PSDImageResources.block(1047, data: value.data) }
      resources += PSDImageResources.block(1039, data: r.profile)
    }
    if includeResolution {
      guard document.pixelsPerInch < 65536 else { throw CraftError.invalid("Photoshop resource resolution exceeds16.16 range.") }
      var resolution = PSDWriter()
      for _ in 0..<2 { resolution.n(Int((document.pixelsPerInch * 65536).rounded()), 4); resolution.n(1, 2); resolution.n(1, 2) }
      resources += PSDImageResources.block(1005, data: resolution.data)
    }
    if let metadata = try RasterMetadata.metadata(document.sourceMetadata, width: document.width, height: document.height,
      resolution: document.pixelsPerInch, linear: false, profileName: document.colorMode.title, isSRGB: false,
      photoshopMode: PSDModeStorage.code(document.colorMode)), let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data? {
      resources += PSDImageResources.block(1060, data: xmp)
    }
    var pathID = 2000
    for saved in document.paths ?? [] {
      var block = PSDWriter(); block.text("8BIM"); block.n(saved.isWorkPath ? 1025 : pathID, 2)
      let title = saved.isWorkPath ? Data() : Data((saved.name.data(using: .macOSRoman, allowLossyConversion: true) ?? Data("Path".utf8)).prefix(255))
      block.n(title.count, 1); block.data += title; if (title.count + 1) % 2 != 0 { block.n(0, 1) }
      let path = try PSDPaths.write(saved.path, width: document.width, height: document.height)
      block.section(path); if path.count % 2 != 0 { block.n(0, 1) }; resources += block.data
      if !saved.isWorkPath { pathID += 1 }
    }
    guard resources.count <= PSDImageResources.maximumBytes else { throw CraftError.invalid("Restricted image resources exceed the metadata budget.") }
    return try PSDGuides.applying(resources,document:document)
  }
  static func paths(_ blocks: [PSDImageResources.Block], width: Int, height: Int) throws -> [NamedPath] {
    try blocks.filter { $0.id == 1025 || (2000...2997).contains($0.id) }.map { block in
      var raw = PSDReader(data: block.raw); _ = try raw.bytes(6)
      let count = Int(try raw.u8()), title = String(data: try raw.bytes(count), encoding: .macOSRoman) ?? "Path"
      return NamedPath(name: block.id == 1025 ? "Work Path" : title.isEmpty ? "Path" : title,
        path: try PSDPaths.read(block.data, width: width, height: height), isWorkPath: block.id == 1025)
    }
  }

}
