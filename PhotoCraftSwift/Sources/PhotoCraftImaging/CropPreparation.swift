import Foundation
import CoreGraphics
import PhotoCraftCore

public enum CropPreparation {
  public static func prepare(_ request: CropRequest,document original: CraftDocument) throws -> CropEdit {
    try request.validate()
    let inverse=try request.transform.inverted()
    let corners=[inverse.point(0.5,0.5),inverse.point(Double(request.width)-0.5,0.5),inverse.point(0.5,Double(request.height)-0.5),inverse.point(Double(request.width)-0.5,Double(request.height)-0.5)]
    let enclosed=corners.allSatisfy{$0.x>=0 && $0.y>=0 && $0.x<Double(original.width) && $0.y<Double(original.height)}
    if request.fill == .contentAware,!enclosed,request.width>ContentAwareSynthesis.maximumPixels/request.height {
      throw CraftError.invalid("Content-aware crop fill currently supports up to4 megapixels. Crop without fill or use a smaller output.")
    }
    let soleBackground=original.layers.count==1 && original.layers[0].isBackground
    if request.fill == .contentAware,!enclosed,!soleBackground,original.layers.contains(where:{$0.isBackground}) {throw CraftError.unsupported("Convert Background to a regular layer before Content-Aware crop expansion in a layered document.")}
    var result = try CropGeometry.applying(request,to:original)
    guard request.fill != .transparent,!enclosed else { return CropEdit(source:original,result:result) }
    if request.fill == .background {return try Self.background(request,original:original,result:result)}
    let guide = try Renderer.composite(result),w = result.width,h = result.height,n = w*h
    var hole = [Bool](repeating:false,count:n);var any = false
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p = inverse.point(Double(x)+0.5,Double(y)+0.5),outside = p.x < 0 || p.y < 0 || p.x >= Double(original.width) || p.y >= Double(original.height)
      if outside && (soleBackground || original.colorMode.isRestricted || guide.pixel(x:x,y:y).a < 1) { hole[y*w+x] = true;any = true }
    } }
    guard any else { return CropEdit(source:original,result:result) }
    guard result.layers.count < LayerLimits.maximumLayers else { throw CraftError.invalid("Remove a layer before adding crop fill output.") }
    var image: [Float] = [],filled: [Float] = []
    if request.fill == .contentAware {
      guard n <= ContentAwareSynthesis.maximumPixels else { throw CraftError.invalid("Content-aware crop fill currently supports up to4 megapixels. Crop without fill or use a smaller output.") }
      image = [Float](repeating:0,count:n*4)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = (y*w+x)*4,p = result.depth == .f32 ? guide.linearPixel(x:x,y:y):guide.pixel(x:x,y:y);image[i] = p.r;image[i+1] = p.g;image[i+2] = p.b;image[i+3] = p.a } }
      var settings = ContentAwareSettings();settings.seed = request.seed
      filled = try ContentAwareSynthesis.fill(width:w,height:h,image:image,hole:hole,source:hole.map { !$0 },settings:settings,hdr:result.depth == .f32)
    }
    var patch = try Surface(width:w,height:h,depth:result.depth,colorEncoding:result.depth == .f32 ? .linearRGB:.sRGB)
    let background = result.depth == .f32 ? SRGBTransfer.linear(request.backgroundColor):request.backgroundColor
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w where hole[y*w+x] {
      let i = (y*w+x)*4,old = result.restrictedMode != nil || soleBackground ? Pixel.clear : result.depth == .f32 ? guide.linearPixel(x:x,y:y):guide.pixel(x:x,y:y)
      let fill = request.fill == .background ? background:Pixel(filled[i],filled[i+1],filled[i+2],1)
      // Store the combined edge only on newly exposed pixels. Existing layers are untouched.
      let a = old.a+fill.a*(1-old.a)
      let p = a > 1e-8 ? Pixel((old.r*old.a+fill.r*fill.a*(1-old.a))/a,(old.g*old.a+fill.g*fill.a*(1-old.a))/a,(old.b*old.a+fill.b*fill.a*(1-old.a))/a,a):Pixel.clear
      if result.depth == .f32 { patch.setLinearPixel(x:x,y:y,p) } else { patch.setPixel(x:x,y:y,p) }
    } }
    if let raster = result.restrictedMode, let id = result.activeLayerID {
      var combined = try raster.surface()
      for y in 0..<h { try Task.checkCancellation(); for x in 0..<w where hole[y*w+x] { combined.setPixel(x:x,y:y,patch.pixel(x:x,y:y)) } }
      try Command.replaceContent(id,.raster(combined)).apply(to:&result)
      return CropEdit(source:original,result:result)
    }
    // Opaque generated pixels replace only new gaps; the original layer stack stays editable.
    var layer = Layer(name:request.fill == .contentAware ? "Content-Aware Crop Fill":"Crop Background",content:.raster(patch));layer.locked = false
    result.layers.append(layer);try result.validate();return CropEdit(source:original,result:result)
  }
  /// Presentation remains bounded; working and export samples are never reduced.
  public static func preview(_ result:CraftDocument)throws->CGImage {
    let ratio=min(1,1024/Double(max(result.width,result.height)))
    let request=try RasterPreviewRequest(region:.init(x:0,y:0,width:result.width,height:result.height),width:max(1,Int(Double(result.width)*ratio)),height:max(1,Int(Double(result.height)*ratio)))
    return try ColorManagement.displayImage(request.reducing(Renderer.composite(result)),in:result)
  }
  private static func background(_ request:CropRequest,original:CraftDocument,result:CraftDocument)throws->CropEdit {
    let inverse=try request.transform.inverted(),guide=try Renderer.composite(result),w=result.width,h=result.height
    let template=try Surface(width:w,height:h,depth:result.depth,colorEncoding:result.depth == .f32 ? .linearRGB:.sRGB)
    let paged=w*h>Surface.maximumDensePixels,builder=paged ? try Surface.PagedBuilder(template:template):nil
    var patch=template,any=false
    let fill=result.depth == .f32 ? SRGBTransfer.linear(request.backgroundColor):request.backgroundColor
    for top in stride(from:0,to:h,by:64) {for left in stride(from:0,to:w,by:2048) {
      try Task.checkCancellation();let pw=min(2048,w-left),ph=min(64,h-top)
      let corners=[inverse.point(Double(left)+0.5,Double(top)+0.5),inverse.point(Double(left+pw)-0.5,Double(top)+0.5),inverse.point(Double(left)+0.5,Double(top+ph)-0.5),inverse.point(Double(left+pw)-0.5,Double(top+ph)-0.5)]
      if corners.allSatisfy({$0.x>=0 && $0.y>=0 && $0.x<Double(original.width) && $0.y<Double(original.height)}) {continue}
      var tile=try Surface(width:pw,height:ph,depth:result.depth,colorEncoding:template.colorEncoding),changed=false
      for y in 0..<ph {try Task.checkCancellation();for x in 0..<pw {
        let dx=left+x,dy=top+y,p=inverse.point(Double(dx)+0.5,Double(dy)+0.5)
        guard p.x<0 || p.y<0 || p.x>=Double(original.width) || p.y>=Double(original.height) else{continue}
        let old=result.restrictedMode != nil ? Pixel.clear:result.depth == .f32 ? guide.linearPixel(x:dx,y:dy):guide.pixel(x:dx,y:dy)
        guard result.colorMode.isRestricted || old.a<1 else{continue}
        let a=old.a+fill.a*(1-old.a),value=a>1e-8 ? Pixel((old.r*old.a+fill.r*fill.a*(1-old.a))/a,(old.g*old.a+fill.g*fill.a*(1-old.a))/a,(old.b*old.a+fill.b*fill.a*(1-old.a))/a,a):Pixel.clear
        if result.depth == .f32 {tile.setLinearPixel(x:x,y:y,value)}else{tile.setPixel(x:x,y:y,value)};changed=true
      }}
      guard changed else{continue};any=true
      if let builder{try builder.append(tile,atX:left,atY:top)}else{for y in 0..<ph{for x in 0..<pw{let p=result.depth == .f32 ? tile.linearPixel(x:x,y:y):tile.pixel(x:x,y:y);if !p.hasSameBits(as:.clear){if result.depth == .f32{patch.setLinearPixel(x:left+x,y:top+y,p)}else{patch.setPixel(x:left+x,y:top+y,p)}}}}}
    }}
    guard any else{return CropEdit(source:original,result:result)}
    if let builder{patch=try builder.finish()}
    var candidate=result
    if let raster=result.restrictedMode,let id=result.activeLayerID {
      var combined=try raster.surface();for y in 0..<h{try Task.checkCancellation();for x in 0..<w{let p=patch.pixel(x:x,y:y);if p.a>0{combined.setPixel(x:x,y:y,p)}}}
      try Command.replaceContent(id,.raster(combined)).apply(to:&candidate)
    }else{
      guard candidate.layers.count<LayerLimits.maximumLayers else{throw CraftError.invalid("Remove a layer before adding crop fill output.")}
      candidate.layers.append(Layer(name:"Crop Background",content:.raster(patch)))
    }
    try candidate.validate();return CropEdit(source:original,result:candidate)
  }

}
