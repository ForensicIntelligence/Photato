import Foundation

extension ChannelCommand {
  func apply(to d: inout CraftDocument) throws {
    switch self {
    case .create(let channel):
      try channel.validate(width:d.width,height:d.height,depth:d.depth)
      guard (d.alphaChannels?.count ?? 0) < CraftDocument.maximumAlphaChannels,
        !(d.alphaChannels ?? []).contains(where:{ $0.id == channel.id }), d.quickMask?.id != channel.id else { throw CraftError.invalid("Channel limit reached or duplicate channel ID.") }
      d.alphaChannels = (d.alphaChannels ?? [])+[channel]
    case .delete(let id):
      guard !LensBlurEngine.usesChannel(id,in:d) else { throw CraftError.invalid("This channel supplies Lens Blur depth. Change the filter depth source before deleting it.") }
      guard d.alphaChannels?.contains(where:{ $0.id == id }) == true else { throw CraftError.invalid("Channel not found.") }
      d.alphaChannels?.removeAll(where:{ $0.id == id }); if d.alphaChannels?.isEmpty == true { d.alphaChannels = nil }
    case .duplicate(let id,let name):
      var value = try d.channel(.alpha(id)); value.id = UUID(); value.name = name ?? value.name+" copy"
      try ChannelCommand.create(value).apply(to:&d)
    case .rename(let id,let name):
      var value = try d.channel(.alpha(id)); value.name = name; try d.setChannel(value,at:.alpha(id))
    case .move(let id,let index):
      guard let old = d.alphaChannels?.firstIndex(where:{ $0.id == id }), let count = d.alphaChannels?.count, (0..<count).contains(index) else { throw CraftError.invalid("Invalid channel order.") }
      let value = d.alphaChannels!.remove(at:old); d.alphaChannels!.insert(value,at:index)
    case .options(let target,let options):
      try options.validate(); var value = try d.channel(target); value.options = options; try d.setChannel(value,at:target)
    case .saveSelection(let id,let name,let mode):
      let pixels = try AlphaChannel.coverage(d.coverageSelection(),width:d.width,height:d.height,depth:d.depth)
      try ChannelCommand.storeSelection(pixels,id,name,mode).apply(to:&d)
    case .storeSelection(let pixels,let id,let name,let mode):
      guard pixels.width == d.width, pixels.height == d.height else { throw CraftError.invalid("Selection/channel canvas sizes differ.") }
      var value = try id.map { try d.channel(.alpha($0)) } ?? AlphaChannel(name:name ?? d.suggestedChannelName,pixels:Surface(width:d.width,height:d.height,depth:d.depth,fill:.black))
      if let name { value.name = name }
      var out = value.pixels
      for y in 0..<d.height { try Task.checkCancellation(); for x in 0..<d.width {
        let old = value.pixels.pixel(x:x,y:y).r, new = unit(pixels.pixel(x:x,y:y).r)
        let v: Float
        switch mode { case .replace: v = new; case .add: v = max(old,new); case .subtract: v = max(0,old-new); case .intersect: v = min(old,new) }
        out.setPixel(x:x,y:y,Pixel(v,v,v))
      } }
      value.pixels = out
      if let id { try d.setChannel(value,at:.alpha(id)) } else { try ChannelCommand.create(value).apply(to:&d) }
    case .load(let target,let mode,let invert):
      let mask = try d.channel(target).selection(invert:invert)
      d.setCoverageSelection(try mask.combined(with:d.coverageSelection(),mode:mode))
    case .quickMask(let on,let options):
      try options.validate(); guard on != (d.quickMask != nil) else { return }
      if on {
        d.quickMask = try AlphaChannel(name:"Quick Mask",pixels:AlphaChannel.coverage(d.coverageSelection(),width:d.width,height:d.height,depth:d.depth),options:options)
        d.setCoverageSelection(nil)
      } else if let channel = d.quickMask {
        let mask = try channel.selection(); d.quickMask = nil
        d.setCoverageSelection(mask.bytes.allSatisfy { $0 == 255 } ? nil:mask)
      }
    case .stroke(let target,let points,let brush):
      var value = try d.channel(target), brush = brush
      let ink = brush.erase ? brush.backgroundColor ?? .white : brush.color
      let gray = value.options.display(unit(0.2126*ink.r+0.7152*ink.g+0.0722*ink.b))
      brush.color = Pixel(gray,gray,gray,ink.a); brush.erase = false
      try Painter.stroke(surface:&value.pixels,points:points,brush:brush,selection:d.selection,selectionMask:d.selectionMask,grayscaleMask:true)
      try d.setChannel(value,at:target)
    case .fill(let target,let amount,let opacity):
      guard amount.isFinite, opacity.isFinite, (0...1).contains(amount), (0...1).contains(opacity) else { throw CraftError.invalid("Invalid channel fill.") }
      var value = try d.channel(target); let before = d
      let ink = value.options.display(amount)
      try value.pixels.mapPixels(in:d.selection ?? IntRect(x:0,y:0,width:d.width,height:d.height)) { x,y,p in
        let k = before.selectionCoverage(x:x,y:y)*opacity, v = unit(p.r*(1-k)+ink*k)
        return Pixel(v,v,v)
      }
      try d.setChannel(value,at:target)
    case .invert(let target):
      var value = try d.channel(target); let before = d
      try value.pixels.mapPixels(in:d.selection ?? IntRect(x:0,y:0,width:d.width,height:d.height)) { x,y,p in
        let k = before.selectionCoverage(x:x,y:y), v = unit(p.r*(1-k)+(1-p.r)*k); return Pixel(v,v,v)
      }
      try d.setChannel(value,at:target)
    case .filter(let target,let filter):
      guard filter.kind != .shadowsHighlights && !filter.kind.isClassicDetail && !filter.kind.isOtherVideo && !filter.kind.isRender && !filter.kind.isStylize && !filter.kind.isPixelate && !filter.kind.isDistortion && filter.kind != .lensBlur && filter.kind != .smartSharpen && filter.kind != .reduceNoise && filter.kind != .filterGallery && filter.kind != .adaptiveWideAngle && filter.kind != .lensCorrection && filter.kind != .blurGallery && filter.kind != .cameraRaw && filter.kind != .puppetWarp && filter.kind != .perspectiveWarp else { throw CraftError.unsupported("This filter requires an RGB image target.") }
      var value = try d.channel(target)
      var proxy = try CraftDocument(width:d.width,height:d.height,depth:d.depth)
      var numeric = try Surface(width:d.width,height:d.height,depth:d.depth,fill:.black,colorEncoding:d.depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<d.height { try Task.checkCancellation(); for x in 0..<d.width {
        let v = unit(value.pixels.pixel(x:x,y:y).r), p = Pixel(v,v,v)
        if d.depth == .f32 { numeric.setLinearPixel(x:x,y:y,p) } else { numeric.setPixel(x:x,y:y,p) }
      } }
      proxy.layers[0].content = .raster(numeric); proxy.selection = d.selection; proxy.selectionMask = d.selectionMask
      try RasterFilterEngine.apply(filter,to:proxy.layers[0].id,in:&proxy)
      guard case .raster(let rendered) = proxy.layers[0].content else { throw CraftError.invalid("Invalid filtered channel.") }
      var output = value.pixels
      for y in 0..<d.height { try Task.checkCancellation(); for x in 0..<d.width {
        let v = unit(d.depth == .f32 ? rendered.linearPixel(x:x,y:y).r:rendered.pixel(x:x,y:y).r)
        output.setPixel(x:x,y:y,Pixel(v,v,v))
      } }
      value.pixels = output; try d.setChannel(value,at:target)
    }
  }
}
