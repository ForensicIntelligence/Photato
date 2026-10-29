import Foundation
import PhotoCraftCore

/// Adobe ImageSourceData (37724) and Photoshop resources (34377). Layer pixels,
/// groups and masks use the same decoder as PSD; the TIFF raster is only a cache.
enum TIFFLayers {
  static let signature = Data("Adobe Photoshop Document Data Block\0".utf8)

  static func read(_ data: Data, composite: CraftDocument) throws -> CraftDocument? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let tiff = try TIFFContainer(data, metadata: false, additionalTags: [34377, 34675, 37724])
    guard let field = tiff.root.fields[37724] else { return nil }
    guard [1, 7].contains(field.type), field.data.starts(with: signature) else {
      throw CraftError.unsupported("Unrecognized Photoshop TIFF layer container. Import cancelled to preserve its contents.")
    }
    let depth = composite.depth == .u8 ? 8 : composite.depth == .u16 ? 16 : 32
    let components = try tiff.scalar(277)
    let extra = try tiff.numbers(338, default: [])
    let colors = composite.colorMode.componentCount
    guard (components == colors && extra.isEmpty)
      || (components == colors + 1 && extra.count == 1 && [1, 2].contains(extra[0])) else {
      throw CraftError.unsupported("Layered TIFF saved alpha and spot channels are not yet supported.")
    }
    guard try TIFFModeStorage.mode(tiff.scalar(262)) == composite.colorMode,
      try tiff.scalar(274, default: 1) == 1,
      try tiff.scalar(256) == composite.width, try tiff.scalar(257) == composite.height,
      try tiff.numbers(258).allSatisfy({ $0 == depth }),
      composite.width <= 30_000, composite.height <= 30_000,
      case .raster(let pixels) = composite.layers.first?.content else {
      throw CraftError.unsupported("Layered TIFF requires an unrotated supported color mode/depth within PSD dimensions.")
    }
    var r = PSDReader(data: field.data, offset: signature.count)
    var globals = PSDWriter(), seen = Set<String>(), hasLayers = false
    let expectedLayerTag = depth == 16 ? "Lr16" : depth == 32 ? "Lr32" : "Layr"
    while r.remaining >= 12 {
      try Task.checkCancellation()
      guard seen.count < 4096 else { throw CraftError.invalid("Too many TIFF Photoshop blocks.") }
      let sig = try r.string(4)
      guard sig == (tiff.order == .big ? "8BIM" : "MIB8") else {
        throw CraftError.unsupported("Unsupported or inconsistent TIFF Photoshop layer framing.")
      }
      let keyBytes = try r.bytes(4)
      let tag = String(decoding: tiff.order == .big ? keyBytes : Data(keyBytes.reversed()), as: UTF8.self)
      let length = tiff.order.number(try r.bytes(4), 0, 4)
      var content = try r.bytes(length)
      let padding = try r.bytes((4 - length % 4) % 4)
      guard seen.insert(tag).inserted, padding.allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Duplicate TIFF Photoshop block or invalid padding.")
      }
      // Photoshop's observed TIFF-specific marker differs from PSD's Mtrn.
      // The TIFF raster/ExtraSamples determine cache alpha here; preserve the
      // marker separately rather than mislabel it as the PSD variant.
      if tag == "MTrn" {
        guard content.isEmpty, seen.count == 1 else {
          throw CraftError.unsupported("Unrecognized TIFF merged-transparency marker.")
        }
        continue
      }
      if ["Layr", "Lr16", "Lr32"].contains(tag) {
        guard tag == expectedLayerTag, !hasLayers else {
          throw CraftError.invalid("TIFF layer depth and composite disagree.")
        }
        content = try TIFFLayerEndian.layers(content, order: tiff.order)
        hasLayers = true
      } else if tiff.order == .little {
        content = try TIFFLayerEndian.payload(content, tag: tag, global: true)
      }
      globals.text("8BIM"); globals.text(tag); globals.section(content)
      globals.data.append(Data(repeating: 0, count: (4 - content.count % 4) % 4))
    }
    guard r.remaining <= 3, try r.consumePadding(0), hasLayers else {
      throw CraftError.invalid("Missing TIFF Photoshop layers or trailing container data.")
    }
    var resources = tiff.root.fields[34377]?.data ?? Data()
    if let resource = tiff.root.fields[34377], ![1, 7].contains(resource.type) {
      throw CraftError.invalid("Invalid TIFF Photoshop resources.")
    }
    let blocks = try PSDImageResources.blocks(resources)
    let profiles = blocks.filter { $0.id == 1039 }
    guard profiles.count <= 1 else { throw CraftError.invalid("Duplicate TIFF Photoshop profiles.") }
    if let icc = tiff.root.fields[34675], ![1, 7].contains(icc.type) {
      throw CraftError.invalid("Invalid TIFF ICC profile field.")
    }
    let profile = composite.profileIsUntagged == true ? nil : tiff.root.fields[34675]?.data ?? composite.modeDescriptor?.profile ?? composite.workingICC
    if let retained = profiles.first, let profile, retained.data != profile {
      throw CraftError.unsupported("TIFF composite and Photoshop layer profiles disagree.")
    }
    if profiles.isEmpty, let profile { resources.append(PSDImageResources.block(1039, data: profile)) }
    var layerSection = PSDWriter()
    layerSection.section(Data()); layerSection.section(Data()); layerSection.data.append(globals.data)
    var adapter = PSDWriter()
    adapter.text("8BPS"); adapter.n(1, 2); adapter.data.append(Data(repeating: 0, count: 6))
    // The external TIFF raster carries its own transparency convention.
    adapter.n(colors, 2); adapter.n(composite.height, 4); adapter.n(composite.width, 4)
    adapter.n(depth, 2); adapter.n(PSDModeStorage.code(composite.colorMode), 2); adapter.section(Data()); adapter.section(resources)
    adapter.section(layerSection.data)
    guard adapter.data.count <= PSDCodec.maximumInputBytes else {
      throw CraftError.invalid("TIFF Photoshop structures exceed the input budget.")
    }
    var result = try PSDCodec.read(PSDReader(data: adapter.data), name: composite.name, tiffComposite: pixels, tiffNativeComposite: composite.layers.first?.nativeMode)
    result.resolution = composite.resolution
    result.sourceICC = composite.sourceICC
    result.profileIsUntagged = composite.profileIsUntagged
    result.sourceMetadata = (composite.sourceMetadata ?? [:]).merging(result.sourceMetadata ?? [:]) { _, psd in psd }
    if seen.contains("MTrn") { result.sourceMetadata?["tiffGlobal_MTrn"] = Data() }
    try result.validate()
    return result
  }

  static func write(_ document: CraftDocument, composite: Data,
    compression: RasterEncodingOptions.TIFFLayerCompression) throws -> Data {
    try Task.checkCancellation()
    guard document.layers.count + document.layers.filter({ $0.group != nil }).count <= 1024 else {
      throw CraftError.invalid("TIFF exceeds the layer record limit.")
    }
    let tiff = try TIFFContainer(composite, metadata: true)
    let psd = PSDOutput()
    try PSDCodec.writeRasterLayers(document, compression: compression.codec, format: .psd,
      output: psd, includeComposite: false)
    var reader = PSDReader(data: psd.data, offset: 26)
    _ = try reader.section()
    let resources = try reader.section().data
    var section = try reader.section()
    let directLayers = try section.section().data
    _ = try section.section()
    guard reader.remaining == 0 else { throw CraftError.invalid("Unexpected TIFF layer intermediate.") }
    var blocks = signature
    func append(_ key: String, _ payload: Data) throws {
      try Task.checkCancellation()
      guard payload.count <= TIFFContainer.byteLimit - blocks.count - 16 else {
        throw CraftError.invalid("TIFF layers exceed the memory budget.")
      }
      blocks.append(Data(tiff.order == .big ? "8BIM".utf8 : "MIB8".utf8))
      let tag = Data(key.utf8)
      blocks.append(tiff.order == .big ? tag : Data(tag.reversed()))
      blocks.append(tiff.order.bytes(payload.count, 4)); blocks.append(payload)
      blocks.append(Data(repeating: 0, count: (4 - payload.count % 4) % 4))
    }
    // TIFF's transparency marker is distinct from PSD's Mtrn and precedes layers.
    if try tiff.scalar(277) == document.colorMode.componentCount + 1 { try append("MTrn", Data()) }
    if !directLayers.isEmpty {
      try append("Layr", TIFFLayerEndian.layers(directLayers, order: .big, target: tiff.order))
    }
    var count = directLayers.isEmpty ? 0 : 1
    while section.remaining >= 12 {
      guard try section.string(4) == "8BIM", count < 4095 else {
        throw CraftError.invalid("Invalid TIFF layer intermediate framing.")
      }
      let key = try section.string(4)
      let payload = try section.section().data
      _ = try section.bytes((4 - payload.count % 4) % 4)
      let converted: Data
      if ["Layr", "Lr16", "Lr32"].contains(key) {
        converted = try TIFFLayerEndian.layers(payload, order: .big, target: tiff.order)
      } else {
        converted = tiff.order == .big ? payload
          : try TIFFLayerEndian.payload(payload, tag: key, global: true, order: .big)
      }
      try append(key, converted); count += 1
    }
    guard try section.consumePadding(0) else { throw CraftError.invalid("Invalid TIFF layer tail.") }
    tiff.root.fields[34377] = .init(tag: 34377, type: 7, count: resources.count, data: resources)
    tiff.root.fields[37724] = .init(tag: 37724, type: 7, count: blocks.count, data: blocks)
    // Existing raster offsets stay valid. The header points to the new complete IFD.
    var result = composite
    try tiff.appendDirectories(to: &result, order: tiff.order)
    try Task.checkCancellation()
    return result
  }
}
