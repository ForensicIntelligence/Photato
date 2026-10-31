import Foundation
import PhotoCraftCore

/// Native translation of PhotoCraft smart_map.rs and filter_effects.rs (MIT OR Apache-2.0).
/// Unsupported filter descriptors reject instead of substituting a cached appearance.
enum PSDSmartFilters {
  static let maximumRetainedCacheBytes=8*1_024*1_024
  static let classes: [RasterFilter.Kind: String] = [.gaussianBlur: "GsnB", .boxBlur: "boxblur", .motionBlur: "MtnB",
    .unsharpMask: "UnsM", .highPass: "HghP", .addNoise: "AdNs", .mosaic: "Msc ", .emboss: "Embs"]
  static func number(_ d: PSDDescriptor, _ key: String, unit: String? = nil) throws -> Double {
    let result: Double?
    if let unit, case .unit(let code, let bits) = d[key], code == Data(unit.utf8) { result = Double(bitPattern: bits) }
    else if unit == nil { result = d[key]?.number }
    else { result = nil }
    guard let result, result.isFinite else { throw CraftError.invalid("Invalid Smart Filter parameter \(key).") }
    return result
  }
  static func flag(_ d: PSDDescriptor, _ key: String, _ fallback: Bool) throws -> Bool {
    guard let value = d[key] else { return fallback }
    guard case .boolean(let result) = value else { throw CraftError.invalid("Invalid Smart Filter flag.") }
    return result
  }
  static func read(_ value: PSDValue) throws -> SmartFilterStack {
    guard case .object(let d) = value, d.classID.text == "filterFXStyle",
      case .list(let list) = d["filterFXList"], list.count <= SmartFilterStack.maximumFilters else {
      throw CraftError.invalid("Invalid Smart Filter stack.")
    }
    var stack = SmartFilterStack()
    stack.enabled = try flag(d, "enab", true)
    stack.maskProperties.enabled = try flag(d, "filterMaskEnable", true)
    stack.maskProperties.linked = try flag(d, "filterMaskLinked", false)
    stack.maskProperties.outside = try flag(d, "filterMaskExtendWithWhite", true) ? 1 : 0
    stack.filters = try list.map { value in
      guard case .object(let item) = value, case .object(let f) = item["Fltr"],
        let kind = classes.first(where: { $0.value == f.classID.text })?.key else {
        throw CraftError.unsupported("This Photoshop Smart Filter is not implemented yet.")
      }
      var filter = RasterFilter(kind)
      let known: Set<String>
      switch kind {
      case .gaussianBlur, .boxBlur, .highPass:
        known = ["Rds "]; filter.radius = try number(f, "Rds ", unit: "#Pxl")
      case .motionBlur:
        known = ["Angl", "Dstn"]; filter.angle = try number(f, "Angl"); filter.distance = try number(f, "Dstn", unit: "#Pxl")
      case .unsharpMask:
        known = ["Amnt", "Rds ", "Thsh"]; filter.amount = try number(f, "Amnt", unit: "#Prc")
        filter.radius = try number(f, "Rds ", unit: "#Pxl"); filter.threshold = try number(f, "Thsh")
      case .emboss:
        known=["Angl","Hght","Amnt"]
        for key in known {guard case .integer = f[key] else {throw CraftError.invalid("Emboss descriptor fields must be integers.")}}
        filter.stylize?.angle=try number(f,"Angl");filter.stylize?.height=try number(f,"Hght");filter.stylize?.amount=try number(f,"Amnt")
      case .mosaic: known = ["ClSz"]; filter.cellSize = try number(f, "ClSz", unit: "#Pxl")
      case .addNoise:
        known = ["Dstr", "Nose", "Mnch", "FlRs"]
        filter.amount = try number(f, "Nose", unit: "#Prc"); filter.monochromatic = try flag(f, "Mnch", false)
        guard case .enumerated(_, let distribution) = f["Dstr"], ["Gsn ", "Unfr"].contains(distribution.text) else {
          throw CraftError.unsupported("Unknown Smart Filter noise distribution.")
        }
        filter.distribution = distribution.text == "Gsn " ? .gaussian : .uniform
        if case .integer(let seed) = f["FlRs"] { filter.seed = UInt32(bitPattern: seed) }
      case .cameraRaw: throw CraftError.unsupported("Save editable Camera Raw filters in native Photato format; Photoshop Camera Raw descriptor interchange is not implemented.")
      case .shadowsHighlights, .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore, .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors, .clouds, .differenceClouds, .fibers, .lensFlare, .diffuse, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind: throw CraftError.unsupported("Stylize Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize: throw CraftError.unsupported("Pixelate Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag: throw CraftError.unsupported("Distortion Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .lensBlur: throw CraftError.unsupported("Lens Blur Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .smartSharpen, .reduceNoise: throw CraftError.unsupported("Smart Sharpen / Reduce Noise Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .filterGallery: throw CraftError.unsupported("Save editable Filter Gallery in Photato format or rasterize before PSD/PSB export.")
      case .adaptiveWideAngle: throw CraftError.unsupported("Save editable Adaptive Wide Angle in Photato format or rasterize before PSD/PSB export.")
      case .lensCorrection: throw CraftError.unsupported("Save editable Lens Correction in Photato format or rasterize before PSD/PSB export.")
      case .blurGallery: throw CraftError.unsupported("Save editable Blur Gallery in Photato format or rasterize before PSD/PSB export.")
      case .perspectiveWarp: throw CraftError.unsupported("Save editable Perspective Warp in Photato format or rasterize before PSD/PSB export. Perspective descriptor interchange is not implemented.")
      case .puppetWarp: throw CraftError.unsupported("Save editable Puppet Warp in Photato format or rasterize before PSD/PSB export. Puppet descriptor interchange is not implemented.")
      case .liquify: throw CraftError.unsupported("Save editable Liquify in native Photato format; Photoshop mesh interchange is not implemented.")
      case .average: throw CraftError.unsupported("Average Smart Filter PSD mapping is not qualified.")
      }
      guard Set(f.items.map { $0.key.text }).isSubset(of: known) else { throw CraftError.unsupported("Unrepresented Smart Filter options.") }
      var result = SmartFilter(filter: filter, enabled: try flag(item, "enab", true))
      if case .object(let blend) = item["blendOptions"] {
        result.opacity = Float(try number(blend, "Opct", unit: "#Prc") / 100)
        guard case .enumerated(_, let mode) = blend["Md  "],
          let i = PSDLayerStyles.blends.firstIndex(of: mode.text) else { throw CraftError.unsupported("Unrepresented Smart Filter blend.") }
        result.blendMode = BlendMode.allCases[i]
      }
      return result
    }
    try stack.validate(); return stack
  }
  static func write(_ stack: SmartFilterStack) throws -> PSDValue {
    try stack.validate()
    guard stack.maskProperties.density == 1, stack.maskProperties.feather == 0, !stack.maskProperties.inverted,
      [Float(0), Float(1)].contains(stack.maskProperties.outside) else {
      throw CraftError.unsupported("Save filter-mask density, feather, inversion or fractional outside coverage in native Photato format.")
    }
    func u(_ x: Double, _ code: String) -> PSDValue { PSDLayerStyles.unit(x, code) }
    let list = try stack.filters.map { item -> PSDValue in
      let f = item.filter
      guard let code = classes[f.kind] else { throw CraftError.unsupported("\(f.kind.title) Smart Filter PSD mapping is not qualified; save as Photato.") }
      var settings: [PSDDescriptor.Item] = []
      switch f.kind {
      case .gaussianBlur, .boxBlur, .highPass: settings = [.init("Rds ", u(f.radius, "#Pxl"))]
      case .motionBlur:
        guard f.angle.rounded() == f.angle else { throw CraftError.unsupported("PSD Motion Blur requires an integer angle.") }
        settings = [.init("Angl", .integer(Int32(f.angle))), .init("Dstn", u(f.distance, "#Pxl"))]
      case .unsharpMask: settings = [.init("Amnt", u(f.amount, "#Prc")), .init("Rds ", u(f.radius, "#Pxl")), .init("Thsh", .integer(Int32(f.threshold)))]
      case .emboss:
        guard let s=f.stylize else {throw CraftError.invalid("Missing Emboss settings.")}
        settings=[.init("Angl",.integer(Int32(s.angle))),.init("Hght",.integer(Int32(s.height))),.init("Amnt",.integer(Int32(s.amount)))]
      case .mosaic: settings = [.init("ClSz", u(f.cellSize, "#Pxl"))]
      case .addNoise: settings = [.init("Dstr", .enumerated(PSDID("Dstr"), PSDID(f.distribution == .gaussian ? "Gsn " : "Unfr"))),
        .init("Nose", u(f.amount, "#Prc")), .init("Mnch", .boolean(f.monochromatic)), .init("FlRs", .integer(Int32(bitPattern: f.seed)))]
      case .shadowsHighlights, .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore, .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors, .clouds, .differenceClouds, .fibers, .lensFlare, .diffuse, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind, .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize, .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag, .average, .liquify, .cameraRaw, .puppetWarp, .perspectiveWarp, .blurGallery, .lensCorrection, .adaptiveWideAngle, .filterGallery, .smartSharpen, .reduceNoise, .lensBlur: break
      }
      let filterID = f.kind == .boxBlur ? Int32(840) : Int32(bitPattern: code.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
      return .object(PSDDescriptor("filterFX", items: [.init("Nm  ", .text(Array((f.kind.title + "...\0").utf16))),
        .init("enab", .boolean(item.enabled)), .init("hasoptions", .boolean(true)),
        .init("FrgC", try PSDLayerStyles.color(.black)), .init("BckC", try PSDLayerStyles.color(.white)),
        .init("blendOptions", .object(PSDDescriptor("blendOptions", items: [.init("Opct", u(Double(item.opacity) * 100, "#Prc")),
          .init("Md  ", .enumerated(PSDID("BlnM"), PSDID(PSDLayerStyles.blends[BlendMode.allCases.firstIndex(of: item.blendMode)!])))]))),
        .init("Fltr", .object(PSDDescriptor(code, items: settings))), .init("filterID", .integer(filterID))]))
    }
    return .object(PSDDescriptor("filterFXStyle", items: [.init("enab", .boolean(stack.enabled)), .init("validAtPosition", .boolean(true)),
      .init("filterMaskEnable", .boolean(stack.maskProperties.enabled)), .init("filterMaskLinked", .boolean(stack.maskProperties.linked)),
      .init("filterMaskExtendWithWhite", .boolean(stack.mask == nil || stack.maskProperties.outside == 1)), .init("filterFXList", .list(list))]))
  }

  struct Mask { var pixels: Surface; var transform: Transform2D }
  static func masks(in document: CraftDocument,readers:[PSDReader]? = nil,paging:PSDRasterPaging.Context? = nil) throws -> [String: Mask] {
    var masks: [String: Mask] = [:], seen: Set<String> = []
    var context=paging
    let sources:[PSDReader]=readers ?? ["FEid","FXid"].compactMap {key in
      guard let bytes=document.sourceMetadata?["psdGlobal_"+key] else{return nil}
      return PSDReader(data:bytes)
    }
    for source in sources {
      var reader=source
      guard (1...3).contains(try reader.u32()) else { throw CraftError.unsupported("Unsupported filter cache version.") }
      while reader.remaining > 0 {
        if reader.remaining < 8 { guard try reader.consumePadding(0) else { throw CraftError.invalid("Invalid filter cache tail.") }; break }
        let length = try reader.length(8); var section = try reader.view(length)
        while section.remaining > 0 {
          let id = try section.string(Int(section.u8()))
          guard seen.insert(id).inserted, seen.count <= 512, try section.u32() == 1 else { throw CraftError.invalid("Invalid filter cache identifier or version.") }
          var planes = try section.view(section.length(8))
          _ = try readRect(&planes); let depth = try planes.u32(), channels = try planes.u32()
          guard [8, 16, 32].contains(depth), channels <= 64 else { throw CraftError.invalid("Invalid filter cache depth or channels.") }
          for _ in 0..<(channels + 2) {
            if try planes.u32() != 0 { _ = try planes.view(planes.length(8)) }
          }
          guard planes.remaining == 0 else { throw CraftError.invalid("Invalid filter cache planes.") }
          if section.remaining > 0, try section.u8() != 0 {
            let rect = try readRect(&section), plane = try section.view(section.length(8))
            _ = try Surface(width:rect.width,height:rect.height)
            if paging != nil || rect.width>RasterFilterEngine.maximumPixels/rect.height {
              if context==nil {context=try PSDRasterPaging.Context()}
              let context=context!,channel=try PSDChannelReader(plane,width:rect.width,height:rect.height,depth:depth,format:.psb)
              try context.admitRaster(bytes:((rect.width+63)/64)*((rect.height+63)/64)*65536)
              let pixels=try PSDRasterPaging.layer(width:rect.width,height:rect.height,depth:document.depth,components:1,
                mask:true,sourceDepth:depth,clampMask:false,context:context){_ in [try channel.nextRow()]}
              masks[id]=Mask(pixels:pixels,transform:.translation(Double(rect.x),Double(rect.y)));continue
            }
            var packed=plane
            let raw = try PSDChannelCodec.decode(packed.bytes(packed.remaining), width: rect.width, height: rect.height, depth: depth, format: .psb)
            var pixels = try Surface(width: rect.width, height: rect.height, depth: document.depth)
            for y in 0..<rect.height {
              try Task.checkCancellation()
              for x in 0..<rect.width {
                let v = try PSDChannelCodec.sample(raw, y * rect.width + x, depth: depth)
                pixels.setPixel(x: x, y: y, Pixel(v, v, v, 1))
              }
            }
            masks[id] = Mask(pixels: pixels, transform: .translation(Double(rect.x), Double(rect.y)))
          }
        }
        _ = try reader.bytes(min(reader.remaining, (4 - length % 4) % 4))
      }
    }
    return masks
  }
  private static func readRect(_ r: inout PSDReader) throws -> IntRect {
    let top = try r.i32(), left = try r.i32(), bottom = try r.i32(), right = try r.i32()
    guard top >= -1_000_000, left >= -1_000_000, bottom <= 1_000_000, right <= 1_000_000,
      right > left, bottom > top else { throw CraftError.invalid("Invalid filter cache bounds.") }
    return IntRect(x: left, y: top, width: right - left, height: bottom - top)
  }
  private static func rect(_ bounds: IntRect, to w: inout PSDWriter) {
    for value in [bounds.y, bounds.x, bounds.y + bounds.height, bounds.x + bounds.width] { w.n(value, 4) }
  }
  static func cacheData(_ document:CraftDocument)throws->Data {
    let output=PSDOutput();try writeCache(document,to:output);return output.data
  }
  static func writeCache(_ document:CraftDocument,to out:PSDOutput,compression:PSDCompression = .zipPrediction)throws {
    try out.n(3,4)
    for original in document.layers where original.smartFilters != nil {
      try Task.checkCancellation()
      var layer=original;layer.smartFilters?.enabled=false
      let base=try SmartFilterEngine.renderedLayer(layer,in:document)
      guard case .raster(let pixels)=base.content,let stack=original.smartFilters else {throw CraftError.invalid("Missing Smart Filter source.")}
      let bounds=IntRect(x:base.x,y:base.y,width:pixels.width,height:pixels.height)
      let depth=document.depth == .u8 ? 8:document.depth == .u16 ? 16:32
      let itemLength=try out.reserveLength(8),id=original.id.uuidString
      try out.n(id.utf8.count,1);try out.text(id);try out.n(1,4)
      let planesLength=try out.reserveLength(8)
      try writeRect(bounds,to:out);try out.n(depth,4);try out.n(24,4)
      for slot in 0..<26 {
        guard slot<3 || slot==25 else {try out.n(0,4);continue}
        try out.n(1,4);let planeLength=try out.reserveLength(8)
        try PSDChannelWriter.write(width:bounds.width,height:bounds.height,depth:depth,compression:compression,format:.psb,to:out){y in
          var bytes:[UInt8]=[];bytes.reserveCapacity(bounds.width*(depth/8))
          for x in 0..<bounds.width {
            let p=depth==32 ? pixels.linearPixel(x:x,y:y):pixels.pixel(x:x,y:y)
            let value=slot==25 ? p.a:p.a==0 ? 1:slot==0 ? p.r:slot==1 ? p.g:p.b
            try PSDChannelCodec.append(value,depth:depth,to:&bytes)
          };return bytes
        }
        try out.finishLength(planeLength,width:8)
      }
      try out.finishLength(planesLength,width:8)
      if let sourceMask=stack.mask {
        var projected=try original.filterMaskProjection();projected.maskProperties?.enabled=true
        let sampler=try MaskSampler(layer:projected,feather:false)
        let maskBounds=try stack.maskProperties.transform.bounds(width:sourceMask.width,height:sourceMask.height)
        let x=min(bounds.x,maskBounds.x),y=min(bounds.y,maskBounds.y)
        let area=IntRect(x:x,y:y,width:max(bounds.x+bounds.width,maskBounds.x+maskBounds.width)-x,
          height:max(bounds.y+bounds.height,maskBounds.y+maskBounds.height)-y)
        _ = try Surface(width:area.width,height:area.height)
        try out.n(1,1);try writeRect(area,to:out);let maskLength=try out.reserveLength(8)
        try PSDChannelWriter.write(width:area.width,height:area.height,depth:depth,compression:compression,format:.psb,to:out){y in
          var bytes:[UInt8]=[];bytes.reserveCapacity(area.width*(depth/8))
          for x in 0..<area.width {
            try PSDChannelCodec.append(sampler.coverage(x:Double(x+area.x)+0.5,y:Double(y+area.y)+0.5),depth:depth,to:&bytes)
          };return bytes
        }
        try out.finishLength(maskLength,width:8)
      }else{try out.n(0,1)}
      try out.finishLength(itemLength,width:8)
      while out.count%4 != 0 {try out.n(0,1)}
    }
  }
  private static func writeRect(_ bounds:IntRect,to out:PSDOutput)throws {
    for value in [bounds.y,bounds.x,bounds.y+bounds.height,bounds.x+bounds.width]{try out.n(value,4)}
  }
}
