import Foundation
import PhotoCraftCore

/// Flat mode7 planes retain their numeric samples. PSD gray0 means full ink;
/// native InkPlane zero means paper. Invert integers and swap16-bit byte order.
enum PSDMultichannelStorage {
  static func read(_ source: PSDReader, width: Int, height: Int, depth: Int,
    channels: Int, format: PSDFileFormat, name: String, paging: PSDRasterPaging.Context? = nil) throws -> CraftDocument {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height, [8,16].contains(depth), (1...56).contains(channels) else {
      throw CraftError.unsupported("Multichannel Photoshop files require1–56 channels,8/16-bit samples and supported Photoshop dimensions.")
    }
    var r = source
    guard try r.section().remaining == 0 else { throw CraftError.invalid("Unexpected Multichannel color-mode data.") }
    let resources = try r.section().data, blocks = try PSDImageResources.blocks(resources)
    for id in PSDInkChannels.resourceIDs.union([1005,1039,1022]) {
      guard blocks.filter({ $0.id == id }).count <= 1 else { throw CraftError.invalid("Duplicate Photoshop channel resource.") }
    }
    let (quickIndex,initiallyEmpty)=try PSDAuxiliaryChannels.quickMaskInfo(blocks,first:0,count:channels)
    let names = try PSDInkChannels.names(blocks, count: channels), displays = try PSDInkChannels.displays(blocks, count: channels)
    let large = width > InkPlane.maximumPixels / height
    let context = try paging ?? PSDRasterPaging.Context(heapByteLimit: 512 * 1024 * 1024)
    var identifiers: [UInt32] = []
    if let block = blocks.first(where: { $0.id == 1053 }) {
      guard block.data.count == channels * 4 else { throw CraftError.invalid("Channel identifiers disagree with the plane count.") }
      var input = PSDReader(data: block.data)
      identifiers = try (0..<channels).map { _ in UInt32(try input.u32()) }
      guard Set(identifiers).count == identifiers.count else { throw CraftError.invalid("Duplicate Photoshop channel identifier.") }
    }
    var retained:[String:Data]=[:]
    var section = try r.section(lengthBytes: format.sectionLengthBytes)
    if section.remaining > 0 {
      var info = try section.section(lengthBytes: format.sectionLengthBytes)
      if info.remaining > 0 {
        guard try info.i16() == 0, info.remaining <= 3, try info.consumePadding(0) else {
          throw CraftError.unsupported("Layer records cannot be represented by a flat Multichannel document.")
        }
      }
      if section.remaining > 0 { guard try section.section().remaining == 0 else { throw CraftError.unsupported("Multichannel global masks are not implemented.") } }
      while section.remaining >= 12 {
        guard ["8BIM","8B64"].contains(try section.string(4)) else {throw CraftError.invalid("Invalid Multichannel global tag.")}
        let tag=try section.string(4),length=try section.length(format.tagLengthBytes(tag))
        guard ["CAI ","OCIO","GenI","FMsk","cinf"].contains(tag) else {throw CraftError.unsupported("Unrepresented Multichannel global metadata: \(tag).")}
        guard retained["psdGlobal_"+tag] == nil else {throw CraftError.invalid("Duplicate Multichannel global tag.")}
        let content=try section.retainedBytes(length);_ = try section.bytes((4-length%4)%4)
        if tag == "OCIO",try !["icc","none"].contains(PSDColorMetadata.managementKind(content) ?? "") {throw CraftError.unsupported("OpenColorIO-managed Multichannel documents are unavailable.")}
        retained["psdGlobal_"+tag]=Data(content)
      }
      guard section.remaining <= 3, try section.consumePadding(0) else { throw CraftError.invalid("Invalid Multichannel global padding.") }
    }
    let pixelDepth: PixelDepth = depth == 8 ? .u8 : .u16
    if let quickIndex,displays[quickIndex].kind==2 {throw CraftError.invalid("Quick Mask cannot be a printing separation.")}
    let reader = try PSDChannelReader(r, width: width, height: height, depth: depth, channels: channels, format: format)
    var plates: [InkPlate] = [], alphas: [AlphaChannel] = [], quickMask:AlphaChannel?, order: [UUID] = []
    var metadata = retained;metadata["psdResources"]=resources
    for channel in 0..<channels {
      try Task.checkCancellation()
      let info = displays[channel], id = UUID()
      if channel != quickIndex { order.append(id) }
      // Inspection of a seekable channel must start within that plane's own
      // row table. Sequential compression already advances plane by plane.
      let input = large && reader.hasSeekableRows ? try reader.detachSeekablePlanes(count: 1, height: height)[0] : reader
      if info.kind == 2 {
        let plane: InkPlane
        if large {
          plane = try PSDModePaging.inkPlane(input, width: width, height: height, depth: pixelDepth, context: context)
        } else {
          var bytes = Data()
          bytes.reserveCapacity(width * height * (depth / 8))
          for _ in 0..<height {
            try Task.checkCancellation()
            let row = try input.nextRow()
            if depth == 8 {
              bytes.append(contentsOf: row.map { 255 - $0 })
            } else {
              for x in 0..<width {
                let word = UInt16(row[x * 2]) << 8 | UInt16(row[x * 2 + 1])
                let density = UInt16.max - word
                bytes.append(UInt8(truncatingIfNeeded: density))
                bytes.append(UInt8(density >> 8))
              }
            }
          }
          plane = try InkPlane(width: width, height: height, depth: pixelDepth, bytes: bytes)
        }
        plates.append(.init(id: id, name: names[channel], color: info.color, solidity: info.opacity, samples: plane))
        if !identifiers.isEmpty {var value=PSDWriter();value.n(Int(identifiers[channel]),4);metadata[PSDInkChannels.identifierKey(id)]=value.data}
      } else {
        let tiles = ((width + 63) / 64) * ((height + 63) / 64)
        try context.admitRaster(bytes: tiles * 65536)
        let pixels: Surface
        if large {
          pixels = try PSDRasterPaging.sparseLayer(width: width, height: height, depth: pixelDepth,
            channels: [input], context: context, invertMask: info.kind == 0)
        } else {
          pixels = try PSDRasterPaging.layer(width: width, height: height, depth: pixelDepth,
            components: 1, fill: .black, mask: true, clampMask: false, skipImplicitDefault: true, context: context) { _ in
              var row = try input.nextRow()
              if info.kind == 0 {
                if depth == 8 { row = row.map { 255 - $0 } }
                else { for x in 0..<width {
                  let at = x * 2, value = 65535 - (Int(row[at]) << 8 | Int(row[at + 1]))
                  row[at] = UInt8(value >> 8); row[at + 1] = UInt8(value & 255)
                } }
              }
              return [row]
            }
        }
        var options = ChannelDisplayOptions(); options.color = info.color; options.opacity = info.opacity
        options.indicates = info.kind == 0 ? .selectedAreas : .maskedAreas
        var alpha = AlphaChannel(id: id, name: names[channel], pixels: pixels, options: options)
        alpha.psdDisplay = info.raw.isEmpty ? nil : info.raw
        if !identifiers.isEmpty { alpha.psdIdentifier = identifiers[channel] }
        if channel==quickIndex {alpha.psdQuickMaskInitiallyEmpty=initiallyEmpty;quickMask=alpha}
        else {alphas.append(alpha)}
      }
      if !info.raw.isEmpty { metadata[PSDInkChannels.key(id)] = info.raw }
    }
    try reader.discardRemaining()
    var document = try CraftDocument(width: width, height: height, depth: pixelDepth, name: name)
    if plates.isEmpty {
      guard !alphas.isEmpty else{throw CraftError.invalid("Multichannel document has no channels.")}
      document.channelOnly=true;document.layers=[];document.activeLayerID=nil
    } else {document=try document.replacingInkMode(.multichannel(MultichannelRaster(plates:plates)))}
    document.alphaChannels = alphas.isEmpty ? nil : alphas;document.quickMask=quickMask
    if !plates.isEmpty { try document.setMultichannelChannelOrder(order) }
    document.sourceMetadata = metadata; document.sourceICC = blocks.first { $0.id == 1039 }?.data
    if let block = blocks.first(where: { $0.id == 1005 }) {
      guard block.data.count == 16 else { throw CraftError.invalid("Invalid Photoshop resolution resource.") }
      var value = PSDReader(data: block.data)
      let x = Double(try value.u32()) / 65536, xu = try value.u16(); _ = try value.u16()
      let y = Double(try value.u32()) / 65536, yu = try value.u16(); _ = try value.u16()
      guard (1...2).contains(xu), (1...2).contains(yu), x >= 1, abs(x-y) < 0.01 else {
        throw CraftError.unsupported("Non-square Photoshop resolution is not represented by this document.")
      }; document.resolution = x
    }
    let paths = try PSDRestrictedStorage.paths(blocks, width: width, height: height)
    document.paths = paths.isEmpty ? nil : paths
    document.globalLight = try PSDGlobalLight.read(blocks)
    try PSDGuides.read(into:&document)
    try r.validateUnchanged(); try document.validate(); return document
  }

  static func write(_ document: CraftDocument, format: PSDFileFormat, compression: PSDCompression, to output: PSDOutput) throws {
    try document.validate()
    let plates:[InkPlate]
    if case .multichannel(let raster)=document.inkMode {plates=raster.plates}
    else if document.isChannelOnly {plates=[]}
    else{throw CraftError.invalid("Expected a Multichannel document.")}
    guard document.depth != .f32,
      document.vanishingPoint == nil, document.width <= format.maximumDimension,
      document.height <= format.maximumDimension, document.pixelsPerInch < 65536 else {
      throw CraftError.unsupported("Multichannel PSD/PSB requires8/16-bit samples and supported geometry/plane metadata. Save as Photato.")
    }
    let alphas = PSDAuxiliaryChannels.all(document), count = plates.count + alphas.count
    guard count <= 56 else { throw CraftError.invalid("Photoshop files support at most56 channels.") }
    let order: [PSDInkChannels.Plane]
    if document.isChannelOnly { order = alphas.indices.map(PSDInkChannels.Plane.auxiliary) }
    else {
      let rows = Dictionary(uniqueKeysWithValues: plates.enumerated().map { ($0.element.id, PSDInkChannels.Plane.plate($0.offset)) }
        + alphas.enumerated().map { ($0.element.id, PSDInkChannels.Plane.auxiliary($0.offset)) })
      let ids = document.multichannelChannelOrder + (document.quickMask.map { [$0.id] } ?? [])
      order = ids.compactMap { rows[$0] }
      guard order.count == count else { throw CraftError.invalid("Photoshop channel rows disagree with the document order.") }
    }
    try output.text("8BPS"); try output.n(format.rawValue, 2); try output.append(Data(repeating: 0, count: 6))
    try output.n(count, 2); try output.n(document.height, 4); try output.n(document.width, 4)
    try output.n(document.bitsPerChannel, 2); try output.n(7, 2)
    try output.section(Data()); try output.section(PSDGuides.applying(try PSDGlobalLight.applying(
      PSDInkChannels.resources(document, plates: plates, alphas: alphas, order: order), document: document), document: document))
    let globalKeys=["CAI ","OCIO","GenI","FMsk","cinf"].filter{document.sourceMetadata?["psdGlobal_"+$0] != nil}
    if globalKeys.isEmpty {try output.section(Data(),lengthBytes:format.sectionLengthBytes)}
    else {
      let mark=try output.reserveLength(format.sectionLengthBytes)
      try output.section(Data(),lengthBytes:format.sectionLengthBytes);try output.section(Data())
      for key in globalKeys {
        let data=document.sourceMetadata!["psdGlobal_"+key]!
        try output.text(format.tagSignature(key));try output.text(key);try output.section(data,lengthBytes:format.tagLengthBytes(key))
        for _ in 0..<((4-data.count%4)%4) {try output.n(0,1)}
      }
      try output.finishLength(mark,width:format.sectionLengthBytes)
    }
    let storedAuxiliary = alphas.map(PSDAuxiliaryChannels.storedRows)
    let storedInk: [PSDNativeRowSupport?] = try plates.map { plate in
      try plate.samples.requiresPagedArchive ? PSDNativeRowSupport(width: document.width, height: document.height,
        streams: [plate.samples.storedSampleRanges]) : nil
    }
    let repeatedRows: ((Int) -> Int)?
    if storedInk.contains(where: { $0 != nil }) || storedAuxiliary.contains(where: { $0 != nil }) {
      repeatedRows = { row in
        let channel = row / document.height, y = row % document.height
        switch order[channel] {
        case .plate(let index): return storedInk[index]?.repeatedRows(from: y) ?? 1
        case .auxiliary(let index): return storedAuxiliary[index]?.repeatedRows(from: y) ?? 1
        }
      }
    } else { repeatedRows = nil }
    try PSDChannelWriter.write(width: document.width, height: document.height, depth: document.bitsPerChannel,
      compression: compression, channels: count, format: format, to: output, repeatedRows: repeatedRows) { row in
      let channel = row / document.height, y = row % document.height
      switch order[channel] {
      case .auxiliary(let index):
        if let stored = storedAuxiliary[index] { return try stored.row(y, channel: 0, depth: document.bitsPerChannel) }
        return try PSDAuxiliaryChannels.row(alphas[index], y: y, depth: document.bitsPerChannel)
      case .plate(let index):
        let plane = plates[index].samples
        let maximum: UInt32 = document.depth == .u8 ? 255 : 65535
        if let stored = storedInk[index] {
          return try stored.row(y, depth: document.bitsPerChannel) { index in Float(maximum - plane.rawWord(at: index)) / Float(maximum) }
        }
        var bytes: [UInt8] = []; bytes.reserveCapacity(document.width * (document.bitsPerChannel / 8))
        for x in 0..<document.width {
          let value = maximum - plane.rawWord(at: y * document.width + x)
          if document.depth == .u16 { bytes.append(UInt8(value >> 8)) }
          bytes.append(UInt8(value & 255))
        }
        return bytes
      }
    }
  }
}
