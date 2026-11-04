import Foundation

private struct ChannelArithmeticTransfer {
  let mode: BlendMode
  let add: Bool
  let subtract: Bool
  let scale: Float
  let offset: Float
  init(_ options: ChannelArithmeticOptions) {
    mode = BlendMode.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "").lowercased() == options.blending.lowercased() } ?? .multiply
    add = options.blending == "add"; subtract = options.blending == "subtract"
    scale = options.scale; offset = options.offset / 255
  }
  func blend(_ b: Float, _ t: Float, extended: Bool) -> Float {
    let value = add ? (b+t)/scale+offset : subtract ? (b-t)/scale+offset
      : extended && mode == .linearDodge ? b+t : mode.channel(b,t)
    return extended ? value : unit(value)
  }
}

public enum ChannelArithmeticEngine {
  /// Source1 is above Source2. Coverage results are always normalized numerical masks.
  public static func calculate(_ first: Surface, _ second: Surface, mask: Surface? = nil,
    options: ChannelArithmeticOptions, depth: PixelDepth) throws -> Surface {
    try options.validate(); try first.validated(); try second.validated()
    guard first.width == second.width, first.height == second.height,
      first.colorEncoding == .sRGB, second.colorEncoding == .sRGB else {
      throw CraftError.invalid("Calculation channel layouts differ.")
    }
    let transfer = ChannelArithmeticTransfer(options)
    let weighted = try weightedSource(first, mask: mask, selection: nil, opacity: options.opacity)
    return try second.combiningStoredSamples(with: weighted) { b,t in
      let v = unit(b.r + (transfer.blend(b.r,t.r,extended:false)-b.r)*t.a)
      return Pixel(v,v,v)
    }.quantizedStoredDepth(depth)
  }

  private static func weightedSource(_ samples: Surface, mask: Surface?, selection: Surface?,
    opacity: Float) throws -> Surface {
    var weighted = try samples.mappedStoredSamples(encoding: .sRGB) { Pixel($0.r,$0.g,$0.b,opacity) }
    for coverage in [mask,selection].compactMap({$0}) {
      guard coverage.width == samples.width, coverage.height == samples.height,
        coverage.colorEncoding == .sRGB else { throw CraftError.invalid("Channel mask dimensions differ.") }
      weighted = try weighted.combiningStoredSamples(with: coverage) { p,m in
        Pixel(p.r,p.g,p.b,p.a*unit(m.r))
      }
    }
    return weighted
  }
  private static func project(_ samples: Surface, transform: Transform2D,
    width: Int, height: Int) throws -> Surface {
    try RasterGeometry.render(samples,transform:transform.inverted(),
      bounds:.init(x:0,y:0,width:width,height:height),method:.nearest)
  }
  private static func color(_ p: Pixel, _ c: Int) -> Float {
    switch c { case 0: p.r; case 1: p.g; case 2: p.b; default: p.a }
  }

  @inline(never)
  public static func apply(_ input: ChannelArithmeticInput, mask: Surface? = nil,
    options: ChannelArithmeticOptions, target: ChannelArithmeticTarget,
    to document: inout CraftDocument) throws {
    try document.validate(); try options.validate()
    try input.validate(width:document.width,height:document.height)
    if let mask {
      guard mask.width==document.width,mask.height==document.height,mask.colorEncoding == .sRGB else {
        throw CraftError.invalid("Channel mask dimensions differ.")
      }
      try mask.validated()
    }
    guard !document.colorMode.isRestricted else { throw CraftError.unsupported("Convert Indexed/Bitmap images before channel blending.") }
    var result = document
    let selection = try AlphaChannel.coverage(document.coverageSelection(),
      width:document.width,height:document.height,depth:.f32)
    let transfer = ChannelArithmeticTransfer(options)
    switch target {
    case .alpha(let id):
      var channel = try result.channel(.alpha(id))
      channel.pixels = try plane(channel.pixels, input:input, mask:mask, selection:selection,
        options:options, transfer:transfer)
      try result.setChannel(channel,at:.alpha(id))
    case .quickMask:
      var channel = try result.channel(.quickMask)
      channel.pixels = try plane(channel.pixels,input:input,mask:mask,selection:selection,
        options:options,transfer:transfer)
      try result.setChannel(channel,at:.quickMask)
    case .ink(let target):
      let original = try result.inkChannel(target)
      let display = try original.surface().mappedStoredSamples { p in
        let v = target.inverted ? 1-p.r : p.r; return Pixel(v,v,v)
      }
      let output = try plane(display,input:input,mask:mask,selection:selection,
        options:options,transfer:transfer)
      var values = [Float](); values.reserveCapacity(original.count)
      for y in 0..<original.height { try Task.checkCancellation(); for x in 0..<original.width {
        let v = output.pixel(x:x,y:y).r; values.append(target.inverted ? 1-v : v)
      } }
      try result.setInkChannel(original.replacing(offset:0,values:values),at:target)
    case .layerMask(let id):
      guard let i = result.layers.firstIndex(where:{$0.id==id}), !result.isLocked(id),
        result.layers[i].mask != nil else { throw CraftError.invalid("Choose an unlocked pixel mask.") }
      if options.opacity==0 {return}
      let source = try input.plane(mean:input.components>1)
      let weighted = try weightedSource(source,mask:mask,selection:selection,opacity:options.opacity)
      var layer = result.layers[i]
      _ = try ClonePainter.paintTarget(mask:true,bounds:.init(x:0,y:0,width:result.width,height:result.height),
        on:&layer,clipping:.init(x:0,y:0,width:result.width,height:result.height)) { pixels,transform,_ in
        let top = try project(weighted,transform:transform,width:pixels.width,height:pixels.height)
        let original=pixels
        pixels = try pixels.combiningStoredSamples(with:top) { b,t in
          let v = unit(b.r+(transfer.blend(b.r,t.r,extended:false)-b.r)*t.a)
          return t.a==0 ? b : Pixel(v,v,v)
        }.quantizedStoredDepth(pixels.depth)
        return pixels != original
      }
      result.layers[i] = layer
    case .pixels(let id,let components):
      guard let i = result.layers.firstIndex(where:{$0.id==id}), !result.isImageLocked(id),
        result.layers[i].smartObject == nil, result.layers[i].smartFilters == nil,
        case .raster = result.layers[i].content else {
        throw CraftError.invalid("Choose an unlocked ordinary pixel layer for Apply Image.")
      }
      guard Set(components).count==components.count, components.allSatisfy({(0..<document.colorMode.componentCount).contains($0)}),
        input.components==1 || input.mode==document.colorMode else {
        throw CraftError.invalid("Composite source color modes must match. Use an individual channel for different modes.")
      }
      if options.opacity==0 {return}
      if document.hasNativeModeStorage {
        try applyNative(input,mask:mask,selection:selection,options:options,components:components,
          index:i,in:&result,transfer:transfer)
      } else {
        guard document.colorMode == .rgb else { throw CraftError.invalid("Missing native component storage.") }
        var layer = result.layers[i]
        let preserve = options.preserveTransparency || !components.isEmpty || layer.protection.locksTransparency
        let samples = input.components==1 ? try input.plane() : input.samples
        let weighted = try weightedSource(samples,mask:mask,selection:selection,opacity:options.opacity)
        let selected = Set(components.isEmpty ? [0,1,2]:components)
        _ = try ClonePainter.paintTarget(mask:false,
          bounds:.init(x:0,y:0,width:result.width,height:result.height),on:&layer,
          clipping:.init(x:0,y:0,width:result.width,height:result.height),preserveTransparency:preserve) { pixels,transform,_ in
          let top = try project(weighted,transform:transform,width:pixels.width,height:pixels.height)
          let encoding = pixels.colorEncoding, depth = pixels.depth
          // Only touched samples cross the transfer function. Outside pixels retain bits.
          let before = try pixels.mappedStoredSamples(encoding:.sRGB) { $0 }
          let edited = try before.combiningStoredSamples(with:top) { stored,t in
            var w = t.a; let ab = unit(stored.a)
            if preserve { w *= ab }
            if w<=0 { return stored }
            let b = depth == .f32 && encoding == .sRGB ? SRGBTransfer.linear(stored):stored
            let alpha = preserve ? ab : w+ab*(1-w)
            var out = b
            for c in selected {
              let original = color(b,c), source = color(t,c)
              let blended=transfer.blend(original,source,extended:depth == .f32)
              let mixed = ab==1 ? blended : ab==0 ? source:source+(blended-source)*ab
              let value = preserve || ab==1 ? original+(mixed-original)*w
                : (w*mixed+ab*(1-w)*original)/alpha
              if c==0 {out.r=value} else if c==1 {out.g=value} else {out.b=value}
            }
            out.a=alpha
            return depth == .f32 && encoding == .sRGB ? SRGBTransfer.encoded(out):out
          }
          pixels = try edited.mappedStoredSamples(encoding:encoding) { $0 }.quantizedStoredDepth(depth)
          return edited != before
        }
        result.layers[i] = layer
      }
    }
    try result.validate(); try Task.checkCancellation(); document = result
  }

  private static func plane(_ before: Surface, input: ChannelArithmeticInput, mask: Surface?,
    selection: Surface, options: ChannelArithmeticOptions,
    transfer: ChannelArithmeticTransfer) throws -> Surface {
    let source = try input.plane(mean:input.components>1)
    let weighted = try weightedSource(source,mask:mask,selection:selection,opacity:options.opacity)
    return try before.combiningStoredSamples(with:weighted) { b,t in
      if t.a<=0 {return b}
      let v=unit(b.r+(transfer.blend(b.r,t.r,extended:false)-b.r)*t.a)
      return Pixel(v,v,v)
    }.quantizedStoredDepth(before.depth)
  }

  /// Projects numeric input and weights once, then streams each retained plane.
  /// Intermediate weights stay Float32, including for integer destinations.
  static func applyingNativePlanes(_ original:NativeModeRaster,input:ChannelArithmeticInput,
    mask:Surface?,selection:Surface,options:ChannelArithmeticOptions,components:[Int],
    preserve:Bool,transform:Transform2D) throws -> NativeModeRaster {
    try options.validate(); try Task.checkCancellation()
    let transfer=ChannelArithmeticTransfer(options)
    let selected=Set(components.isEmpty ? Array(0..<original.mode.componentCount):components)
    let alpha=try original.opacityChannel().quantizedStoredDepth(.f32)
    // Match opacity * selection * mask, before the local nearest projection.
    var weights=try selection.mappedStoredSamples {p in let w=options.opacity*p.r;return Pixel(w,w,w)}
    if let mask {weights=try weights.combiningStoredSamples(with:mask) {p,m in let w=p.r*unit(m.r);return Pixel(w,w,w)}}
    weights=try project(weights,transform:transform,width:original.width,height:original.height)
      .combiningStoredSamples(with:alpha) {p,a in
        let ab=a.r,w=preserve ? p.r*ab:p.r,ao=preserve ? ab:w+ab*(1-w)
        return Pixel(w,ao,ab)
      }
    let top=try project(input.samples,transform:transform,width:original.width,height:original.height)
    var result=original
    for c in selected.sorted() {
      try Task.checkCancellation()
      let pairs=try original.channel(c).quantizedStoredDepth(.f32)
        .combiningStoredSamples(with:top) {b,t in Pixel(b.r,color(t,input.components==1 ? 0:c),0)}
      let output=try pairs.combiningStoredSamples(with:weights) {pair,k in
        let stored=pair.r,w=k.r,ao=k.g,ab=k.b
        if w<=0 {return Pixel(stored,stored,stored)}
        let base=original.mode == .cmyk ? 1-stored:stored,source=pair.g
        let blended=transfer.blend(base,source,extended:original.depth == .f32)
        let mixed=ab==1 ? blended:ab==0 ? source:source+(blended-source)*ab
        let value=preserve || ab==1 ? base+(mixed-base)*w:(w*mixed+ab*(1-w)*base)/ao
        let out=original.mode == .cmyk ? 1-value:value
        return Pixel(out,out,out)
      }.quantizedStoredDepth(original.depth)
      result=try result.replacingChannel(c,with:output)
    }
    // Retain original opacity words where no edit occurs, including signed zero.
    let opacity=try alpha.combiningStoredSamples(with:weights) {p,k in
      let value=k.r<=0 ? p.r:k.g;return Pixel(value,value,value)
    }.quantizedStoredDepth(original.depth)
    if !preserve {result=try result.replacingOpacity(with:opacity)}
    try result.validate();try Task.checkCancellation();return result
  }

  private static func applyNative(_ input: ChannelArithmeticInput, mask: Surface?, selection: Surface,
    options: ChannelArithmeticOptions, components: [Int], index: Int,
    in document: inout CraftDocument, transfer: ChannelArithmeticTransfer) throws {
    var layer=document.layers[index]
    let original=try ModeComponentEdit.raster(layer,in:document)
    let selected=Set(components.isEmpty ? Array(0..<original.mode.componentCount):components)
    let preserve=options.preserveTransparency || !components.isEmpty || layer.protection.locksTransparency
    let oldTransform=layer.coordinateTransform
    _ = try ClonePainter.paintTarget(mask:false,
      bounds:.init(x:0,y:0,width:document.width,height:document.height),on:&layer,
      clipping:.init(x:0,y:0,width:document.width,height:document.height),
      preserveTransparency:preserve) { _,_,_ in true }
    guard case .raster(let expanded)=layer.content else {throw CraftError.invalid("Missing expanded mode cache.")}
    let offset=try oldTransform.inverted()*layer.coordinateTransform
    let ox=Int(offset.tx.rounded()),oy=Int(offset.ty.rounded())
    let frame=IntRect(x:ox,y:oy,width:expanded.width,height:expanded.height)
    let baseNative:NativeModeRaster
    if ox==0 && oy==0 && expanded.width==original.width && expanded.height==original.height {baseNative=original}
    else if expanded.width*expanded.height>NativeModeRaster.maximumPixels {
      // Storage expansion is an integer reframe, not resampling. Preserve raw
      // hidden samples and visit source/support rather than the logical canvas.
      baseNative=try original.reframedExactly(bounds:frame)
    } else {baseNative=try original.transformed(by:.identity,bounds:frame,method:.nearest)}
    let transform=layer.coordinateTransform
    if baseNative.requiresPagedArchive {
      let native=try applyingNativePlanes(baseNative,input:input,mask:mask,selection:selection,
        options:options,components:components,preserve:preserve,transform:transform)
      layer.nativeMode=native;layer.content = .raster(try native.surface())
      document.layers[index]=layer;return
    }
    var native=baseNative
    // Preserve the original small-document formula and evaluation order.
    for y in 0..<native.height {try Task.checkCancellation();for x in 0..<native.width {
      let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y))
      guard (0..<document.width).contains(dx),(0..<document.height).contains(dy) else{continue}
      let at=y*native.width+x,ab=baseNative.value(component:original.mode.componentCount,index:at)
      var w=options.opacity*selection.pixel(x:dx,y:dy).r*(mask.map{unit($0.pixel(x:dx,y:dy).r)} ?? 1)
      if preserve {w *= ab};if w<=0{continue}
      let ao=preserve ? ab:w+ab*(1-w),source=input.samples.pixel(x:dx,y:dy)
      for c in selected {
        let stored=baseNative.value(component:c,index:at),base=original.mode == .cmyk ? 1-stored:stored
        let top=color(source,input.components==1 ? 0:c)
        let blended=transfer.blend(base,top,extended:original.depth == .f32)
        let mixed=ab==1 ? blended:ab==0 ? top:top+(blended-top)*ab
        let value=preserve || ab==1 ? base+(mixed-base)*w:(w*mixed+ab*(1-w)*base)/ao
        try native.set(original.mode == .cmyk ? 1-value:value,component:c,index:at)
      }
      try native.set(ao,component:original.mode.componentCount,index:at)
    }}
    layer.nativeMode=native;layer.content = .raster(try native.surface())
    document.layers[index]=layer
  }
}
