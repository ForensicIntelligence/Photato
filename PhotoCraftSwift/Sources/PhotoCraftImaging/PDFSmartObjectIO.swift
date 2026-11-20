import CoreGraphics
import Foundation
import PhotoCraftCore

/// Retains the original PDF and re-renders its selected page after enlargement.
/// Temporary render surfaces never replace the archived source or source pixels.
public enum PDFSmartObjectIO {
  public static func embedded(_ data: Data, fileName: String, in parent: CraftDocument,
    settings: PDFImportSettings, matching: SmartObject? = nil) throws -> (SmartObject, Surface) {
    try settings.validate()
    guard settings.pages.count == 1, settings.width == nil, settings.height == nil else {
      throw CraftError.invalid("Place one PDF page; use the layer transform to resize it.")
    }
    let pdf = try PDFImport.open(data,password:nil)
    guard !pdf.isEncrypted else { throw CraftError.unsupported("Encrypted PDF placement needs a durable unlocked source; open an unencrypted copy.") }
    let plan = try PDFImport.plan(pdf,number:settings.pages[0],settings:settings,
      maximumPixels:SmartObjectIO.maximumCanvasPixels,maximumBytes:PDFImport.maximumDecodedBytes)
    let selection = try PDFSmartObjectSource(page:plan.number,
      crop:PDFSmartObjectSource.Crop(rawValue:settings.crop.rawValue)!,
      x:plan.region.minX,y:plan.region.minY,width:plan.region.width,height:plan.region.height,
      antialias:settings.antialias)
    let (w,h) = try PDFImport.dimensions(CGSize(width:plan.region.width*settings.resolution/72,
      height:plan.region.height*settings.resolution/72),maximumPixels:SmartObjectIO.maximumCanvasPixels)
    try matching?.validate()
    let object = try SmartObject(fileName:fileName,mediaType:"application/pdf",data:data,
      width:matching?.width ?? w,height:matching?.height ?? h,resolution:matching?.resolution ?? settings.resolution,pdfSource:selection)
    return (object,try surface(object,width:object.width,height:object.height,in:parent))
  }
  public static func placed(_ data: Data, fileName: String, in parent: CraftDocument,
    settings: PDFImportSettings, image: Int? = nil, fit: Bool = true,
    sizing: SmartObjectPlacementSizing = .pixels) throws -> Layer {
    let (object,pixels) = try image.map {try embeddedImage(data,fileName:fileName,in:parent,image:$0,resolution:settings.resolution,antialias:settings.antialias)}
      ?? embedded(data,fileName:fileName,in:parent,settings:settings)
    var layer = Layer(name:(fileName as NSString).deletingPathExtension,content:.raster(pixels))
    layer.smartObject = object
    try sizing.center(&layer, source: object, in: parent, fit: fit)
    return layer
  }
  public static func replacement(_ data: Data, fileName: String, in parent: CraftDocument,
    layerID: UUID, settings: PDFImportSettings, image: Int? = nil, preserveSize: Bool = true,
    allInstances: Bool = true) throws -> Command {
    let (object,pixels) = try image.map {try embeddedImage(data,fileName:fileName,in:parent,image:$0,resolution:settings.resolution,antialias:settings.antialias)}
      ?? embedded(data,fileName:fileName,in:parent,settings:settings)
    return .replaceSmartObject(layerID,object,pixels,preserveSize:preserveSize,allInstances:allInstances)
  }
  /// A saved source edit keeps the selected page/image and existing instance transforms.
  public static func sourceUpdate(_ data: Data, in parent: CraftDocument,
    layerID: UUID, expectedRevision: String) throws -> Command {
    guard let source = parent.layers.first(where: {$0.id == layerID})?.smartObject,
      let selection = source.pdfSource else {throw CraftError.invalid("Select a retained PDF Smart Object.")}
    guard source.revision == expectedRevision else {throw CraftError.invalid("The PDF source changed. Reopen its contents or explicitly apply the saved PDF.")}
    guard !data.isEmpty,data.count <= SmartObject.maximumSourceBytes,PDFImport.recognizes(data) else {
      throw CraftError.invalid("Choose a PDF source between1 byte and64MiB.")
    }
    var settings = PDFImportSettings();settings.pages = [selection.page]
    settings.crop = PDFImportSettings.Crop(rawValue:selection.crop.rawValue)!
    settings.resolution = source.resolution;settings.antialias = selection.antialias
    return try replacement(data,fileName:source.fileName,in:parent,layerID:layerID,
      settings:settings,image:selection.image,preserveSize:false,allInstances:true)
  }
  public static func surface(_ object: SmartObject, width: Int, height: Int,
    in parent: CraftDocument) throws -> Surface {
    try object.validate();try Task.checkCancellation()
    guard let selection = object.pdfSource else { throw CraftError.invalid("Select a PDF Smart Object.") }
    _ = try PDFImport.dimensions(CGSize(width:width,height:height),maximumPixels:SmartObjectIO.maximumCanvasPixels)
    var source = object.data,pageNumber = selection.page
    if let image = selection.image {
      let (info,archive) = try PDFImages.selectedPage(source,image:image)
      guard info.page == selection.page,Double(info.width) == selection.width,Double(info.height) == selection.height else {
        throw CraftError.invalid("The retained PDF image disagrees with its source.")
      }
      source = archive;pageNumber = 1
    }
    let pdf = try PDFImport.open(source,password:nil)
    guard !pdf.isEncrypted, let page = pdf.page(at:pageNumber),
      let crop = PDFImportSettings.Crop(rawValue:selection.crop.rawValue) else {
      throw CraftError.invalid("The retained PDF page is unavailable.")
    }
    let full = try PDFImport.orientedBox(page,crop.box)
    let region = CGRect(x:selection.x,y:selection.y,width:selection.width,height:selection.height)
    guard full.contains(region), crop == .bounding || region == full else {
      throw CraftError.invalid("The retained PDF crop disagrees with its page box.")
    }
    let plan = PDFImport.Plan(page:page,full:full,region:region,number:selection.page)
    let pixels = try PDFImport.surface(plan,box:crop.box,width:width,height:height,depth:parent.depth,
      antialias:selection.antialias,maximumBytes:PDFImport.maximumDecodedBytes)
    let sourceDocument = try CraftDocument(width:width,height:height,depth:parent.depth)
    return try ColorManagement.converted(pixels,from:sourceDocument,to:parent)
  }
  public static func embeddedImage(_ data: Data,fileName: String,in parent: CraftDocument,
    image: Int,resolution: Double = 72,antialias: Bool = true) throws -> (SmartObject,Surface) {
    let pdf = try PDFImport.open(data,password:nil)
    guard !pdf.isEncrypted else {throw CraftError.unsupported("Place an unencrypted PDF source.")}
    let (info,archive) = try PDFImages.selectedPage(data,image:image)
    var settings = PDFImportSettings();settings.crop = .media;settings.resolution = 72;settings.antialias = antialias
    var (object,pixels) = try embedded(archive,fileName:fileName,in:parent,settings:settings)
    object.data = data;object.resolution = resolution
    object.pdfSource?.page = info.page;object.pdfSource?.image = image
    try object.validate()
    return (object,pixels)
  }
  /// Only a render projection. Archived geometry, source identity, masks and
  /// undo history retain their original coordinates and original PDF bytes.
  public static func renderedLayer(_ layer: Layer, in parent: CraftDocument) throws -> Layer {
    guard let object = layer.smartObject, object.pdfSource != nil else { return layer }
    if object.linkedSource != nil,object.data.isEmpty {return layer}
    if let projection = layer.sourceProjection, layer.warp?.isIdentity != false {
      if layer.pristineSmartAppearance?.pixels != nil { return layer }
      let samples = try projectedSamples(layer, projection: projection, object: object, in: parent)
      var result = try WarpRaster.baked(layer, in: parent, samples: samples)
      if result.smartFilters == nil { result.smartObject = nil }
      return result
    }
    if let warp = layer.warp {
      if layer.pristineSmartAppearance?.pixels != nil { return layer }
      let mapping = try warpMapping(layer, warp: warp, object: object)
      let samples = try magnifiedSamples(object, scale: mapping.maximumMagnification(), in: parent)
      var result = try WarpRaster.baked(layer, in: parent, using: mapping, method: warp.interpolation, samples: samples)
      if result.smartFilters == nil { result.smartObject = nil }
      return result
    }
    let t = layer.coordinateTransform
    let aa = t.a*t.a+t.b*t.b, bb = t.c*t.c+t.d*t.d, ab = t.a*t.c+t.b*t.d
    let maximumScale = sqrt(max(0,(aa+bb+sqrt((aa-bb)*(aa-bb)+4*ab*ab))/2))
    guard maximumScale.isFinite else { throw CraftError.invalid("The PDF transform has no finite render scale.") }
    // The cached initial render is already at adequate resolution for shrinkage.
    guard maximumScale > 1.00000001 else { return layer }
    let density = ceil(maximumScale-0.00000001)
    let (w,h) = try PDFImport.dimensions(CGSize(width:Double(object.width)*density,
      height:Double(object.height)*density),maximumPixels:SmartObjectIO.maximumCanvasPixels)
    var result = layer
    result.content = .raster(try surface(object,width:w,height:h,in:parent))
    let sx = Double(w)/Double(object.width), sy = Double(h)/Double(object.height)
    result.affine = (layer.affine ?? .identity) * .scale(1/sx,1/sy)
    if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = .scale(sx,sy) * properties.transform
      result.maskProperties = properties
    }
    if layer.smartFilters == nil { result.smartObject = nil }
    return result
  }

  static func rasterizationSamples(_ layer: Layer, in parent: CraftDocument) throws -> Surface? {
    guard let object = layer.smartObject, object.pdfSource != nil,
          !object.data.isEmpty, layer.pristineSmartAppearance?.pixels == nil else { return nil }
    if let projection = layer.sourceProjection, layer.warp?.isIdentity != false {
      return try projectedSamples(layer, projection: projection, object: object, in: parent)
    }
    guard let warp = layer.warp else { return nil }
    let mapping = try warpMapping(layer, warp: warp, object: object)
    return try magnifiedSamples(object, scale: mapping.maximumMagnification(), in: parent)
  }

  private static func projectedSamples(_ layer: Layer, projection: ProjectiveTransform, object: SmartObject,
                                       in parent: CraftDocument) throws -> Surface? {
    let full = try projection.followed(by: layer.coordinateTransform)
    return try magnifiedSamples(object, scale: full.maximumMagnification(width: object.width, height: object.height), in: parent)
  }

  private static func warpMapping(_ layer: Layer, warp: WarpDefinition, object: SmartObject) throws -> PagedWarpRaster.Mapping {
    try PagedWarpRaster.mapping(warp, width: object.width, height: object.height,
                                transform: layer.coordinateTransform, projection: layer.sourceProjection)
  }

  private static func magnifiedSamples(_ object: SmartObject, scale required: Double,
                                       in parent: CraftDocument) throws -> Surface? {
    let width = Double(object.width), height = Double(object.height)
    let budget = floor(min(Double(Surface.maxDimension) / max(width, height),
                           sqrt(Double(SmartObjectIO.maximumCanvasPixels) / (width * height))))
    // Keep the same integer rendering density as ordinary PDF placement. An
    // extreme local stretch can reach the existing full-source raster budget.
    let density = min(budget, ceil(required - 1e-8))
    guard density > 1 else { return nil }
    return try surface(object, width: object.width * Int(density), height: object.height * Int(density), in: parent)
  }
}
