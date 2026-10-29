import Foundation
import PhotoCraftCore

public enum CropPreparation {
  public static func prepare(_ request: CropRequest,document original: CraftDocument) throws -> CropEdit {
    var result = try CropGeometry.applying(request,to:original)
    guard request.fill != .transparent else { return CropEdit(source:original,result:result) }
    let guide = try Renderer.composite(result),inverse = try request.transform.inverted(),w = result.width,h = result.height,n = w*h
    var hole = [Bool](repeating:false,count:n);var any = false
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p = inverse.point(Double(x)+0.5,Double(y)+0.5),outside = p.x < 0 || p.y < 0 || p.x >= Double(original.width) || p.y >= Double(original.height)
      if outside && (original.colorMode.isRestricted || guide.pixel(x:x,y:y).a < 1) { hole[y*w+x] = true;any = true }
    } }
    guard any else { return CropEdit(source:original,result:result) }
    guard result.layers.count < 512 else { throw CraftError.invalid("Remove a layer before adding crop fill output.") }
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
      let i = (y*w+x)*4,old = result.restrictedMode != nil ? Pixel.clear : result.depth == .f32 ? guide.linearPixel(x:x,y:y):guide.pixel(x:x,y:y)
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
}
