import Foundation
import PhotoCraftCore

/// Flat mode7 planes retain their numeric samples. PSD gray0 means full ink;
/// native InkPlane zero means paper. Invert integers and swap16-bit byte order.
enum PSDMultichannelStorage {
  static func read(_ source: PSDReader, width: Int, height: Int, depth: Int,
    channels: Int, format: PSDFileFormat, name: String) throws -> CraftDocument {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= InkPlane.maximumPixels / height, [8,16].contains(depth), (1...56).contains(channels) else {
      throw CraftError.unsupported("Multichannel Photoshop files require1–56 channels,8/16-bit samples and at most8,388,608 pixels.")
    }
    var r = source
    guard try r.section().remaining == 0 else { throw CraftError.invalid("Unexpected Multichannel color-mode data.") }
    let resources = try r.section().data, blocks = try PSDImageResources.blocks(resources)
    for id in PSDInkChannels.resourceIDs.union([1005,1039,1022]) {
      guard blocks.filter({ $0.id == id }).count <= 1 else { throw CraftError.invalid("Duplicate Photoshop channel resource.") }
    }
    guard !blocks.contains(where: { $0.id == 1022 }) else { throw CraftError.unsupported("Multichannel Quick Mask import is not implemented yet.") }
    let names = try PSDInkChannels.names(blocks, count: channels), displays = try PSDInkChannels.displays(blocks, count: channels)
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
        let content=try section.bytes(length);_ = try section.bytes((4-length%4)%4)
        if tag == "OCIO",try !["icc","none"].contains(PSDColorMetadata.managementKind(content) ?? "") {throw CraftError.unsupported("OpenColorIO-managed Multichannel documents are unavailable.")}
        retained["psdGlobal_"+tag]=Data(content)
      }
      guard section.remaining <= 3, try section.consumePadding(0) else { throw CraftError.invalid("Invalid Multichannel global padding.") }
    }
    let pixelDepth: PixelDepth = depth == 8 ? .u8 : .u16
    let reader = try PSDChannelReader(r, width: width, height: height, depth: depth, channels: channels, format: format)
    var plates: [InkPlate] = [], alphas: [AlphaChannel] = []
    var metadata = retained;metadata["psdResources"]=resources
    for channel in 0..<channels {
      try Task.checkCancellation()
      let info = displays[channel], id = UUID()
      var bytes = Data(); bytes.reserveCapacity(width * height * (depth / 8))
      for _ in 0..<height {
        try Task.checkCancellation(); let row = try reader.nextRow()
        if depth == 8 { bytes.append(contentsOf: info.kind == 2 ? row.map { 255 - $0 } : row) }
        else { for x in 0..<width {
          let input = Int(row[x * 2]) << 8 | Int(row[x * 2 + 1]), value = info.kind == 2 ? 65535 - input : input
          bytes.append(UInt8(value & 255)); bytes.append(UInt8(value >> 8))
        } }
      }
      let plane = try InkPlane(width: width, height: height, depth: pixelDepth, bytes: bytes)
      if info.kind == 2 { plates.append(.init(id: id, name: names[channel], color: info.color, solidity: info.opacity, samples: plane)) }
      else {
        var options = ChannelDisplayOptions(); options.color = info.color; options.opacity = info.opacity
        options.indicates = info.kind == 0 ? .selectedAreas : .maskedAreas
        alphas.append(.init(id: id, name: names[channel], pixels: try plane.surface(), options: options))
      }
      if !info.raw.isEmpty { metadata[PSDInkChannels.key(id)] = info.raw }
    }
    var document = try CraftDocument(width: width, height: height, depth: pixelDepth, name: name)
    if plates.isEmpty {
      guard !alphas.isEmpty else{throw CraftError.invalid("Multichannel document has no channels.")}
      document.channelOnly=true;document.layers=[];document.activeLayerID=nil
    } else {document=try document.replacingInkMode(.multichannel(MultichannelRaster(plates:plates)))}
    document.alphaChannels = alphas.isEmpty ? nil : alphas
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
    guard document.depth != .f32,document.quickMask == nil,
      document.vanishingPoint == nil, document.width <= format.maximumDimension,
      document.height <= format.maximumDimension, document.pixelsPerInch < 65536 else {
      throw CraftError.unsupported("Multichannel PSD/PSB cannot retain active Quick Mask or unsupported geometry/plane metadata. Save as Photato.")
    }
    let alphas = document.alphaChannels ?? [], count = plates.count + alphas.count
    guard count <= 56 else { throw CraftError.invalid("Photoshop files support at most56 channels.") }
    try output.text("8BPS"); try output.n(format.rawValue, 2); try output.append(Data(repeating: 0, count: 6))
    try output.n(count, 2); try output.n(document.height, 4); try output.n(document.width, 4)
    try output.n(document.bitsPerChannel, 2); try output.n(7, 2)
    try output.section(Data()); try output.section(PSDGuides.applying(try PSDGlobalLight.applying(PSDInkChannels.resources(document, plates: plates), document: document),document:document))
    let globalKeys=["CAI ","OCIO","GenI","FMsk","cinf"].filter{document.sourceMetadata?["psdGlobal_"+$0] != nil}
    if globalKeys.isEmpty {try output.section(Data(),lengthBytes:format.sectionLengthBytes)}
    else {
      let mark=try output.reserveLength(format.sectionLengthBytes)
      try output.section(Data(),lengthBytes:format.sectionLengthBytes);try output.section(Data())
      for key in globalKeys {
        let data=document.sourceMetadata!["psdGlobal_"+key]!
        try output.text("8BIM");try output.text(key);try output.section(data,lengthBytes:format.tagLengthBytes(key))
        for _ in 0..<((4-data.count%4)%4) {try output.n(0,1)}
      }
      try output.finishLength(mark,width:format.sectionLengthBytes)
    }
    try PSDChannelWriter.write(width: document.width, height: document.height, depth: document.bitsPerChannel,
      compression: compression, channels: count, format: format, to: output) { row in
      let channel = row / document.height, y = row % document.height
      var bytes: [UInt8] = []; bytes.reserveCapacity(document.width * (document.bitsPerChannel / 8))
      for x in 0..<document.width {
        let value: Int
        if channel < plates.count {
          let plane = plates[channel].samples, i = y * document.width + x
          value = document.depth == .u8 ? 255 - Int(plane.bytes[i]) : 65535 - (Int(plane.bytes[2*i]) | Int(plane.bytes[2*i+1]) << 8)
        } else {
          let sample = alphas[channel - plates.count].pixels.pixel(x: x, y: y).r
          value = Int((sample * (document.depth == .u8 ? 255 : 65535)).rounded())
        }
        if document.depth == .u16 { bytes.append(UInt8(value >> 8)) }
        bytes.append(UInt8(value & 255))
      }
      return bytes
    }
  }
}
