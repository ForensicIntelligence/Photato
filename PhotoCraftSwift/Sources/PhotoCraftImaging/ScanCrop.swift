import Foundation
import PhotoCraftCore

/// Shared selected-layer scan extraction. Detection derives from licensed
/// PhotoCraft; Photoshop's proprietary segmentation/resampling is unqualified.
public enum ScanCrop {
  public static let maximumPixels = 8_388_608
  public static let maximumOutputPixels = 33_554_432
  public static let maximumBytes = 536_870_912
  public struct Analysis: Sendable {
    public let photos: [ScannedPhoto]
    public let layerID: UUID
    public let region: IntRect
    public let preservesNativeComponents: Bool
    fileprivate let pixels: Surface
    fileprivate let native: NativeModeRaster?
    fileprivate let nativeTransform: Transform2D
  }
  public struct Result: Sendable {
    public let documents: [CraftDocument]
    public let photos: [ScannedPhoto]
    public let layerID: UUID
    public let preservesNativeComponents: Bool
  }
  public static func analyze(_ document: CraftDocument, layerID: UUID? = nil, forceSingle: Bool = false) throws -> Analysis {
    try document.validate();try Task.checkCancellation()
    guard DocumentColorMode.componentModes.contains(document.colorMode),document.animation == nil,document.videoTimeline == nil,
      !document.hasArtboards,!document.hasFrames else {throw CraftError.unsupported("Crop and Straighten Photos requires a still RGB, Grayscale, CMYK or Lab document without artboards or frames.")}
    guard document.width <= maximumPixels/document.height,document.estimatedBytes <= maximumBytes else {throw CraftError.unsupported("Scan extraction supports up to8,388,608 source pixels and512MiB of source data.")}
    guard let id = layerID ?? document.activeLayerID,let selected = document.layers.first(where:{$0.id == id}) else {throw CraftError.invalid("Select the layer containing the scanned photos.")}
    if case .adjustment = selected.content {throw CraftError.invalid("Select an image layer instead of an adjustment layer.")}
    let region = (document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard region.width >= 8,region.height >= 8 else {throw CraftError.invalid("The selected scan area must be at least8 by8 pixels.")}
    var isolated = document
    let ids = Set(document.subtreeIDs(id));isolated.layers = document.layers.filter{ids.contains($0.id)};LayerLinks.prune(in:&isolated)
    guard let index = isolated.layers.firstIndex(where:{$0.id == id}) else {throw CraftError.invalid("The selected layer is unavailable.")}
    isolated.layers[index].parentID = nil;isolated.layers[index].visible = true;isolated.layers[index].clipped = false
    isolated.activeLayerID = id;isolated.variables = nil;isolated.selection = nil;isolated.selectionMask = nil
    let pixels = try Renderer.composite(isolated)
    var photos = try ScanCropDetector.find(width:region.width,height:region.height,forceSingle:forceSingle) {x,y in
      var p = pixels.pixel(x:x+region.x,y:y+region.y)
      p.a *= document.selectionCoverage(x:x+region.x,y:y+region.y);return p
    }
    for i in photos.indices {photos[i].centerX += Double(region.x);photos[i].centerY += Double(region.y)}
    // Retain numerical separations for ordinary pixel scans. Complex native-mode
    // layers use the existing compositor and explicit profile conversion below.
    let native: NativeModeRaster?
    if case .raster = selected.content,selected.mask == nil,selected.vectorMask == nil,selected.style == nil,
      selected.smartObject == nil,selected.smartFilters == nil,selected.warp == nil,selected.opacity == 1 {
      native = selected.nativeMode
    } else {native = nil}
    return Analysis(photos:photos,layerID:id,region:region,preservesNativeComponents:document.colorMode == .rgb || native != nil,pixels:pixels,native:native,nativeTransform:selected.coordinateTransform)
  }
  public static func prepare(_ document: CraftDocument, layerID: UUID? = nil, forceSingle: Bool = false) throws -> Result {
    try extract(analyze(document,layerID:layerID,forceSingle:forceSingle),from:document)
  }
  public static func extract(_ analysis: Analysis,from document: CraftDocument) throws -> Result {
    guard !analysis.photos.isEmpty else {throw CraftError.invalid("No photos were detected. Leave space between the photos and use a uniform scan background.")}
    var outputs: [CraftDocument] = [],totalPixels = 0,totalBytes = 0
    let linear = document.depth == .f32
    let samples = try linear ? analysis.pixels.interpretingSamples(as:.sRGB):analysis.pixels
    for (index,photo) in analysis.photos.enumerated() {
      try Task.checkCancellation()
      let width = max(1,Int(photo.width.rounded())),height = max(1,Int(photo.height.rounded()))
      guard width <= maximumPixels/height else {throw CraftError.unsupported("A detected photo exceeds8,388,608 pixels.")}
      totalPixels += width*height;guard totalPixels <= maximumOutputPixels else {throw CraftError.unsupported("Extracted photos exceed the32-megapixel combined output budget.")}
      let toSource = Transform2D.translation(photo.centerX,photo.centerY) * .rotation(photo.angle) * .scale(photo.width/Double(width),photo.height/Double(height)) * .translation(-Double(width)/2,-Double(height)/2)
      var layer: Layer
      if let native = analysis.native {
        let transform = try toSource.inverted() * analysis.nativeTransform
        var extracted = try native.transformed(by:transform,bounds:IntRect(x:0,y:0,width:width,height:height),method:.bicubic)
        let white = try NativeModeRaster.converting(Surface(width:1,height:1,depth:document.depth,fill:.white),to:native.mode,profile:native.profile,intent:native.intent).components(index:0)
        for i in 0..<width*height {
          if i%1024 == 0 {try Task.checkCancellation()}
          let alpha = extracted.value(component:native.mode.componentCount,index:i)
          if alpha < 1 {for c in 0..<native.mode.componentCount {try extracted.set(extracted.value(component:c,index:i)*alpha+white[c]*(1-alpha),component:c,index:i)}}
          try extracted.set(1,component:native.mode.componentCount,index:i)
        }
        layer = Layer(name:"Background",content:.raster(try extracted.surface()));layer.nativeMode = extracted
      } else {
        var sampled = try Surface(width:width,height:height,depth:document.depth,colorEncoding:linear ? .linearRGB:.sRGB)
        for y in 0..<height {try Task.checkCancellation();for x in 0..<width {
          let point = toSource.point(Double(x)+0.5,Double(y)+0.5)
          let p = RasterGeometry.sample(samples,x:point.x,y:point.y,method:.bicubic)
          let value = Pixel(p.r*p.a+1-p.a,p.g*p.a+1-p.a,p.b*p.a+1-p.a)
          if linear {sampled.setLinearPixel(x:x,y:y,value)} else {sampled.setPixel(x:x,y:y,value)}
        }}
        layer = Layer(name:"Background",content:.raster(sampled))
        if let mode = document.modeDescriptor {
          let native = try NativeModeRaster.converting(sampled,to:mode.mode,profile:mode.profile,intent:mode.intent,sourceProfile:document.workingICC)
          layer.nativeMode = native;layer.content = .raster(try native.surface())
        }
      }
      layer.protection = [.transparency,.position]
      var output = try CraftDocument(width:width,height:height,depth:document.depth,name:"\(document.name) copy \(index+1)")
      output.layers = [layer];output.activeLayerID = layer.id;output.resolution = document.resolution
      output.workingICC = document.workingICC;output.sourceICC = document.sourceICC;output.colorSpace = document.colorSpace
      output.profileIsUntagged = document.profileIsUntagged;output.modeDescriptor = document.modeDescriptor
      try output.validate();totalBytes += output.estimatedBytes
      guard totalBytes <= maximumBytes else {throw CraftError.unsupported("Extracted documents exceed512MiB.")}
      outputs.append(output)
    }
    return Result(documents:outputs,photos:analysis.photos,layerID:analysis.layerID,preservesNativeComponents:analysis.preservesNativeComponents)
  }
}
