import Foundation

public struct CropRequest: Equatable,Sendable {
  public enum Fill: String,CaseIterable,Sendable { case transparent,background,contentAware }
  public var x: Int,y: Int,width: Int,height: Int
  public var angle: Double = 0
  public var deleteCroppedPixels = true
  public var fill = Fill.transparent
  public var backgroundColor = Pixel.white
  public var seed: UInt32 = 1
  public init(x: Int,y: Int,width: Int,height: Int) { self.x = x;self.y = y;self.width = width;self.height = height }
  public static let maximumPixels = 16_777_216
  public func validate() throws {
    guard (-1_000_000...1_000_000).contains(x),(-1_000_000...1_000_000).contains(y),(1...60000).contains(width),(1...60000).contains(height),width <= Self.maximumPixels/height,
      angle.isFinite,(-360...360).contains(angle),backgroundColor.isFinite,(0...1).contains(backgroundColor.a),(fill != .background || backgroundColor.a == 1)
    else { throw CraftError.invalid("Invalid crop dimensions, angle or fill (maximum16 megapixels).") }
  }
  /// Output pixels to original document coordinates are the inverse of this mapping.
  public var transform: Transform2D {
    let cx = Double(x)+Double(width)/2,cy = Double(y)+Double(height)/2
    return .translation(Double(width)/2,Double(height)/2) * .rotation(-angle) * .translation(-cx,-cy)
  }
}

public struct CropEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public init(source: CraftDocument,result: CraftDocument) { self.source = source;self.result = result }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    guard original == source,result.id == original.id else { throw CraftError.invalid("Crop source changed before commit.") };try Task.checkCancellation();try result.validate();return result
  }
}

public enum CropGeometry {
  public static func applying(_ request: CropRequest,to original: CraftDocument) throws -> CraftDocument {
    try request.validate();try original.validate();try Task.checkCancellation()
    guard original.width <= CropRequest.maximumPixels/original.height else { throw CraftError.invalid("Crop source canvas exceeds16 megapixels.") }
    if original.inkMode != nil {
      guard request.deleteCroppedPixels, request.fill != .contentAware else {
        throw CraftError.unsupported("Ink-mode crop currently requires Delete Cropped Pixels and paper/background fill.")
      }
      return try InkModeGeometry.document(original, by: request.transform, width: request.width, height: request.height,
        method: request.angle == 0 ? .nearest : .bilinear, fill: request.fill == .background ? request.backgroundColor : nil, clearSelection: true)
    }
    if original.restrictedMode != nil {
      guard request.deleteCroppedPixels else { throw CraftError.unsupported("Indexed Color and Bitmap cannot retain off-canvas layers. Enable Delete Cropped Pixels, or convert to RGB first.") }
      return try RestrictedModeGeometry.document(original, by: request.transform, width: request.width, height: request.height, clearSelection: true)
    }
    let delta = request.transform;var document = original;document.width = request.width;document.height = request.height
    var pixelsUsed = 0
    for i in document.layers.indices {
      try Task.checkCancellation();let old = original.layers[i];var layer = old
      DocumentGeometry.freezeTextLayout(&layer,document:original)
      let matrix = delta * old.coordinateTransform
      layer.x = Int(floor(matrix.tx));layer.y = Int(floor(matrix.ty));let local = Transform2D.translation(-Double(layer.x),-Double(layer.y))*matrix;layer.affine = local == .identity ? nil:local
      if case .gradientFill(var fill) = old.content { try fill.transform(by:delta);layer.content = .gradientFill(fill) }
      if case .patternFill(var fill) = old.content { try fill.transform(by:delta);layer.content = .patternFill(fill) }
      if var filters = old.smartFilters,filters.mask != nil { filters.maskProperties.transform = delta*filters.maskProperties.transform;layer.smartFilters = filters }
      if var mask = old.vectorMask { mask.path = mask.path.transformed(delta);layer.vectorMask = mask }
      // Canvas changes move linked and unlinked masks together with the document.
      // Retained storage keeps the original local mask transform exactly.
      // The new layer mapping already carries the whole-canvas delta.
      if request.deleteCroppedPixels,old.smartObject == nil,case .raster(let source) = old.content {
        let clipped = try trimmed(source,transform:matrix,width:document.width,height:document.height,pixelsUsed:&pixelsUsed)
        layer.content = .raster(clipped.surface);layer.x = clipped.bounds.x;layer.y = clipped.bounds.y;layer.affine = nil
        if let native = old.nativeMode {
          let integer = matrix.a == 1 && matrix.d == 1 && matrix.b == 0 && matrix.c == 0 && matrix.tx.rounded() == matrix.tx && matrix.ty.rounded() == matrix.ty
          let retained = try native.transformed(by:matrix,bounds:clipped.bounds,method:integer ? .nearest:.bilinear)
          layer.nativeMode=retained;layer.content = .raster(try retained.surface())
        }
        if old.mask != nil { var properties = old.effectiveMaskProperties;properties.transform = try layer.coordinateTransform.inverted()*delta*old.maskCoordinateTransform;layer.maskProperties = properties }
      }
      document.layers[i] = layer
    }
    document.transformSavedPaths(by:delta);try document.transformChannels(from:original,by:delta,method:.bilinear)
    document.setCoverageSelection(nil);try document.validate();return document
  }
  /// Materialize only retained raster pixels. Integer translation uses exact stored-sample copies.
  private static func trimmed(_ source: Surface,transform: Transform2D,width: Int,height: Int,pixelsUsed: inout Int) throws -> (surface:Surface,bounds:IntRect) {
    let full = try transform.bounds(width:source.width,height:source.height),box = full.clipped(toWidth:width,height:height)
    guard box.width > 0,box.height > 0 else { return (try Surface(width:1,height:1,depth:source.depth,colorEncoding:source.colorEncoding),.init(x:0,y:0,width:1,height:1)) }
    guard box.width <= 67_108_864/box.height,pixelsUsed <= 67_108_864-box.width*box.height else { throw CraftError.invalid("Crop exceeds the64 megapixel total raster processing budget.") };pixelsUsed += box.width*box.height
    if transform.a == 1,transform.d == 1,transform.b == 0,transform.c == 0,transform.tx.rounded() == transform.tx,transform.ty.rounded() == transform.ty {
      return (try source.cropped(to:.init(x:box.x-Int(transform.tx),y:box.y-Int(transform.ty),width:box.width,height:box.height)),box)
    }
    let inverse = try transform.inverted();var output = try Surface(width:box.width,height:box.height,depth:source.depth,colorEncoding:source.depth == .f32 ? .linearRGB:source.colorEncoding)
    for y in 0..<box.height { try Task.checkCancellation();for x in 0..<box.width {
      let p = inverse.point(Double(box.x+x)+0.5,Double(box.y+y)+0.5),pixel = sample(source,x:p.x,y:p.y)
      if source.depth == .f32 { output.setLinearPixel(x:x,y:y,pixel) } else { output.setPixel(x:x,y:y,pixel) }
    } };return (output,box)
  }
  public static func sample(_ source: Surface,x: Double,y: Double) -> Pixel {
    let ix = Int(floor(x-0.5)),iy = Int(floor(y-0.5)),fx = Float(x-0.5-Double(ix)),fy = Float(y-0.5-Double(iy));var v = SIMD4<Float>.zero
    for j in 0...1 { for i in 0...1 { let p = source.depth == .f32 ? source.linearPixel(x:ix+i,y:iy+j):source.pixel(x:ix+i,y:iy+j),w = (i == 0 ? 1-fx:fx)*(j == 0 ? 1-fy:fy);v += SIMD4(p.r*p.a,p.g*p.a,p.b*p.a,p.a)*w } }
    return v.w > 1e-8 ? Pixel(v.x/v.w,v.y/v.w,v.z/v.w,unit(v.w)):.clear
  }
}
