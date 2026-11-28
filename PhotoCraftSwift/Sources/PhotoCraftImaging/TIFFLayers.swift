import Foundation
import PhotoCraftCore

/// Adobe ImageSourceData (37724) and Photoshop resources (34377). Layer pixels,
/// groups and masks use the same decoder as PSD; the TIFF raster is only a cache.
enum TIFFLayers {
  static let signature = Data("Adobe Photoshop Document Data Block\0".utf8)

  static func read(_ data: Data, composite: CraftDocument, backing: RasterTileStore? = nil,
    storedAlpha: [Surface]? = nil) throws -> CraftDocument? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let tiff = try TIFFContainer(data, metadata: false, additionalTags: [34377, 34675, 37724])
    return try read(tiff, composite: composite, backing: backing, storedAlpha: storedAlpha)
  }
  static func read(_ tiff: TIFFContainer, composite: CraftDocument, backing: RasterTileStore?,
    storedAlpha: [Surface]? = nil) throws -> CraftDocument? {
    guard let field = tiff.root.fields[37724] else { return nil }
    let fieldSource = try tiff.reader(for: field)
    var r = fieldSource
    guard [1, 7].contains(field.type), r.remaining >= signature.count,
      try r.bytes(signature.count) == signature else {
      throw CraftError.unsupported("Unrecognized Photoshop TIFF layer container. Import cancelled to preserve its contents.")
    }
    let depth = composite.depth == .u8 ? 8 : composite.depth == .u16 ? 16 : 32
    let components = try tiff.scalar(277)
    let extra = try tiff.numbers(338, default: [])
    let colors = composite.colorMode.componentCount
    let ordinarySamples = (components == colors && extra.isEmpty)
      || (components == colors + 1 && extra.count == 1 && [1, 2].contains(extra[0]))
    let savedAlpha: TIFFStorage.Geometry?
    if ordinarySamples {
      savedAlpha = nil
    } else {
      guard composite.colorMode == .rgb, depth == 8,
        let geometry = try TIFFStorage.Geometry(tiff, allowAssociatedAlpha: true, allowSavedAlpha: true),
        !geometry.savedAlphaSamples.isEmpty else {
        throw CraftError.unsupported("Unsupported layered TIFF auxiliary sample layout.")
      }
      savedAlpha = geometry
    }
    guard try TIFFModeStorage.mode(tiff.scalar(262)) == composite.colorMode,
      try tiff.scalar(274, default: 1) == 1,
      try tiff.scalar(256) == composite.width, try tiff.scalar(257) == composite.height,
      try tiff.numbers(258).allSatisfy({ $0 == depth }),
      composite.width <= 30_000, composite.height <= 30_000,
      case .raster(let pixels) = composite.layers.first?.content else {
      throw CraftError.unsupported("Layered TIFF requires an unrotated supported color mode/depth within PSD dimensions.")
    }
    var globalViews: [PSDReader] = [], globalLength = 0, seen = Set<String>()
    var hasLayers = false, hasEditableLayers = false
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
      var content = try r.view(length)
      let padding = try r.bytes((4 - length % 4) % 4)
      guard seen.insert(tag).inserted, padding.allSatisfy({ $0 == 0 }) else {
        throw CraftError.invalid("Duplicate TIFF Photoshop block or invalid padding.")
      }
      // Photoshop's observed TIFF-specific marker differs from PSD's Mtrn.
      // The TIFF raster/ExtraSamples determine cache alpha here; preserve the
      // marker separately rather than mislabel it as the PSD variant.
      if tag == "MTrn" {
        guard content.remaining == 0, seen.count == 1 else {
          throw CraftError.unsupported("Unrecognized TIFF merged-transparency marker.")
        }
        continue
      }
      let isLayerBlock = ["Layr", "Lr16", "Lr32"].contains(tag)
      if isLayerBlock {
        guard tag == expectedLayerTag, !hasLayers else {
          throw CraftError.invalid("TIFF layer depth and composite disagree.")
        }
        hasLayers = true
        var countView = content
        hasEditableLayers = countView.remaining >= 2 ? try countView.u16() != 0 : false
      }
      let normalized: [PSDReader]
      if isLayerBlock {
        normalized = try TIFFLayerEndian.layerViews(content, order: tiff.order)
      } else if tiff.order == .little {
        let payload = try TIFFLayerEndian.payload(content.retainedBytes(length), tag: tag, global: true)
        normalized = [PSDReader(data: payload)]
      } else {
        normalized = [content]
      }
      guard normalized.reduce(0, { $0 + $1.remaining }) == length else {
        throw CraftError.invalid("TIFF layer normalization changed its payload length.")
      }
      var header = PSDWriter()
      header.text("8BIM"); header.text(tag); header.n(length, 4)
      globalViews.append(PSDReader(data: header.data))
      globalViews.append(contentsOf: normalized)
      globalViews.append(PSDReader(data: Data(repeating: 0, count: padding.count)))
      globalLength += header.data.count + length + padding.count
    }
    guard r.remaining <= 3, try r.consumePadding(0), hasLayers else {
      throw CraftError.invalid("Missing TIFF Photoshop layers or trailing container data.")
    }
    var resources = tiff.root.fields[34377]?.data ?? Data()
    if let resource = tiff.root.fields[34377], ![1, 7].contains(resource.type) {
      throw CraftError.invalid("Invalid TIFF Photoshop resources.")
    }
    let blocks = try PSDImageResources.blocks(resources)
    if savedAlpha != nil {
      guard hasEditableLayers,
        blocks.contains(where: { [1006, 1045].contains($0.id) && !$0.data.isEmpty }),
        !blocks.contains(where: { $0.id == 1022 }) else {
        throw CraftError.unsupported("Layered TIFF auxiliary samples require named channels and editable layers.")
      }
    }
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
    guard globalLength <= Int(UInt32.max) - 8 else {
      throw CraftError.invalid("TIFF Photoshop layer section exceeds its classic file range.")
    }
    var adapter = PSDWriter()
    adapter.text("8BPS"); adapter.n(1, 2); adapter.data.append(Data(repeating: 0, count: 6))
    // The external TIFF raster carries its own transparency convention.
    adapter.n(colors, 2); adapter.n(composite.height, 4); adapter.n(composite.width, 4)
    adapter.n(depth, 2); adapter.n(PSDModeStorage.code(composite.colorMode), 2); adapter.section(Data()); adapter.section(resources)
    adapter.n(8 + globalLength, 4)
    adapter.n(0, 4); adapter.n(0, 4)
    let psd = try PSDReader.joining([PSDReader(data: adapter.data)] + globalViews, validating: fieldSource)
    let paging = try backing.map { try PSDRasterPaging.Context(sharedBacking: $0) }
    var result = try PSDCodec.read(psd, name: composite.name, tiffComposite: pixels,
      tiffNativeComposite: composite.layers.first?.nativeMode, paging: paging)
    if let savedAlpha {
      let count = savedAlpha.savedAlphaSamples.count
      // Photoshop's MTrn marks the leading opacity sample. Some TIFF writers
      // describe only saved channels, while Photoshop also names that sample.
      let transparencyRecord = seen.contains("MTrn") && (extra.first == 1 || extra.first == 2)
        && (try? PSDAuxiliaryChannels.names(blocks, count: count + 1)) != nil
      if let storedAlpha {
        guard storedAlpha.count == count else { throw CraftError.invalid("TIFF saved-selection planes disagree with the layer metadata.") }
        try PSDAuxiliaryChannels.read(storedAlpha, first: components-count, blocks: blocks,
          document: &result, paging: paging, leadingTransparency: transparencyRecord)
      } else {
        let reader = try TIFFStorage.savedAlphaReader(tiff, geometry: savedAlpha)
        try PSDAuxiliaryChannels.read(reader, first: components-count, count: count,
          blocks: blocks, document: &result, paging: nil, leadingTransparency: transparencyRecord)
      }
      guard result.alphaChannels?.allSatisfy({ $0.spot == nil }) == true else {
        throw CraftError.unsupported("Layered TIFF spot channels are not yet supported.")
      }
    }
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
    let tiff = try TIFFContainer(composite, metadata: true)
    try attach(document, to: tiff, order: tiff.order, compression: compression)
    // Existing raster offsets stay valid. The header points to the new complete IFD.
    var result = composite
    try tiff.appendDirectories(to: &result, order: tiff.order)
    try Task.checkCancellation()
    return result
  }

  static func write(_ document: CraftDocument, composite: Data, to url: URL,
    compression: RasterEncodingOptions.TIFFLayerCompression) throws {
    let tiff = try TIFFContainer(composite, metadata: true)
    try attach(document, to: tiff, order: tiff.order, compression: compression, fileBacked: true)
    let limit = TIFFContainer.classicFileMaximumBytes
    let output = try AtomicFileWriter(to: url, maximumBytes: limit)
    try output.append(composite)
    let offset = try tiff.writeDirectories(order: tiff.order, maximumOutput: limit,
      extent: { output.count }, emit: output.append, patch: output.patch)
    try output.patch(offset, at: 4)
    try output.commit()
  }

  static func attach(_ document: CraftDocument, to tiff: TIFFContainer, order: TIFFContainer.Order,
    compression: RasterEncodingOptions.TIFFLayerCompression, fileBacked: Bool = false) throws {
    try Task.checkCancellation()
    guard document.layers.count + document.layers.filter({ $0.group != nil }).count <= 1024 else {
      throw CraftError.invalid("TIFF exceeds the layer record limit.")
    }
    let savedAlpha = document.alphaChannels ?? []
    var layerDocument = document
    let componentCount = try tiff.scalar(277)
    let hasTransparency: Bool
    if savedAlpha.isEmpty {
      hasTransparency = componentCount == document.colorMode.componentCount+1
    } else {
      let extra = try tiff.numbers(338)
      let remaining = extra.dropLast(savedAlpha.count)
      guard document.colorMode == .rgb, document.depth == .u8, document.quickMask == nil,
        savedAlpha.allSatisfy({ $0.spot == nil }), extra.count == componentCount-3, extra.count >= savedAlpha.count,
        extra.suffix(savedAlpha.count).allSatisfy({ $0 == 0 }),
        remaining.isEmpty || remaining == [1] || remaining == [2] else {
        throw CraftError.invalid("TIFF saved-alpha samples disagree with the selected channels.")
      }
      hasTransparency = !remaining.isEmpty
      // The PSD intermediate contributes layer records. The TIFF carries the saved samples.
      layerDocument.alphaChannels = nil
    }
    func serializeLayers(_ output: PSDOutput) throws {
      try PSDCodec.writeRasterLayers(layerDocument, compression: compression.codec, format: .psd,
        output: output, includeComposite: false)
    }
    let layerBytes: Data
    if fileBacked {
      let limit = TIFFContainer.classicFileMaximumBytes
      let intermediate = try FileBackedSource.writing(maximumBytes: limit) { url in
        let file = try AtomicFileWriter(to: url, maximumBytes: limit)
        try serializeLayers(PSDOutput(file: file, maximumBytes: limit))
        try file.commit()
      }
      layerBytes = intermediate.data
    } else {
      let output = PSDOutput()
      try serializeLayers(output)
      layerBytes = output.data
    }
    let payloadSource = PSDReader(data: layerBytes, offset: 26)
    var reader = payloadSource
    _ = try reader.section()
    var resources = try reader.section().data
    if !savedAlpha.isEmpty {
      resources.append(try PSDAuxiliaryChannels.resources(document,first:componentCount-savedAlpha.count,
        leadingTransparency:hasTransparency))
    }
    var section = try reader.section()
    let directLayers = try section.section()
    _ = try section.section()
    guard reader.remaining == 0 else { throw CraftError.invalid("Unexpected TIFF layer intermediate.") }
    var blocks = [PSDReader(data: signature)], payloadBytes = signature.count
    let limit = fileBacked ? TIFFContainer.classicFileMaximumBytes : TIFFContainer.byteLimit
    func append(_ key: String, _ payload: [PSDReader]) throws {
      try Task.checkCancellation()
      let length = payload.reduce(0) { $0 + $1.remaining }
      let tail = (4 - length % 4) % 4
      guard payloadBytes <= limit - 12 - tail, length <= limit - payloadBytes - 12 - tail else {
        throw CraftError.invalid("TIFF layers exceed the selected output size limit.")
      }
      let tag = Data(key.utf8)
      var header = Data(order == .big ? "8BIM".utf8 : "MIB8".utf8)
      header.append(order == .big ? tag : Data(tag.reversed()))
      header.append(order.bytes(length, 4))
      blocks.append(PSDReader(data: header))
      blocks.append(contentsOf: payload)
      blocks.append(PSDReader(data: Data(repeating: 0, count: tail)))
      payloadBytes += header.count + length + tail
    }
    // TIFF's transparency marker is distinct from PSD's Mtrn and precedes layers.
    if hasTransparency { try append("MTrn", []) }
    if directLayers.remaining > 0 {
      try append("Layr", TIFFLayerEndian.layerViews(directLayers, order: .big, target: order))
    }
    var count = directLayers.remaining == 0 ? 0 : 1
    while section.remaining >= 12 {
      guard try section.string(4) == "8BIM", count < 4095 else {
        throw CraftError.invalid("Invalid TIFF layer intermediate framing.")
      }
      let key = try section.string(4)
      var payload = try section.section()
      _ = try section.bytes((4 - payload.remaining % 4) % 4)
      if ["Layr", "Lr16", "Lr32"].contains(key) {
        try append(key, TIFFLayerEndian.layerViews(payload, order: .big, target: order))
      } else if order == .little {
        let bytes = try TIFFLayerEndian.payload(payload.retainedBytes(payload.remaining),
          tag: key, global: true, order: .big)
        try append(key, [PSDReader(data: bytes)])
      } else { try append(key, [payload]) }
      count += 1
    }
    guard try section.consumePadding(0) else { throw CraftError.invalid("Invalid TIFF layer tail.") }
    tiff.root.fields[34377] = .init(tag: 34377, type: 7, count: resources.count, data: resources)
    let payload = try PSDReader.joining(blocks, validating: payloadSource)
    if fileBacked {
      tiff.root.fields[37724] = .init(tag: 37724, type: 7, count: payloadBytes, data: Data(), serialized: payload)
    } else {
      tiff.root.fields[37724] = .init(tag: 37724, type: 7, count: payloadBytes, data: try payload.data)
    }
  }
}
