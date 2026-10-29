import Foundation

/// Shared target preparation for the workspace and on-device face detection API.
public struct LiquifyInput: Sendable {
  public let pixels: Surface
  public let coverage: Surface?
  public let width: Int
  public let height: Int
  public static func prepare(document: CraftDocument, layerID: UUID, filterID: UUID? = nil,
    maximumSide: Int = 1024) throws -> Self {
    guard let original = document.layers.first(where: { $0.id == layerID }),
      case .raster = original.content, !document.isImageLocked(layerID), maximumSide > 0 else {
      throw CraftError.invalid("Liquify requires an unlocked raster layer or Smart Object.")
    }
    var layer = original
    if layer.smartObject != nil {
      var stack = layer.smartFilters ?? SmartFilterStack()
      if let filterID {
        guard let i = stack.filters.firstIndex(where: { $0.id == filterID }) else { throw CraftError.invalid("Missing Smart Filter.") }
        stack.filters = Array(stack.filters.prefix(i))
      }
      stack.mask = nil; stack.enabled = true; layer.smartFilters = stack
      layer = try SmartFilterEngine.renderedLayer(layer, in: document)
    } else if filterID != nil { throw CraftError.invalid("Filter IDs require a Smart Object.") }
    guard case .raster(let full) = layer.content, full.width <= RasterFilterEngine.maximumPixels / full.height else {
      throw CraftError.invalid("Liquify supports up to8,388,608 target pixels.")
    }
    let scale = min(1,Double(maximumSide)/Double(max(full.width,full.height)))
    let w = max(1,Int(Double(full.width)*scale)), h = max(1,Int(Double(full.height)*scale))
    var pixels = try Surface(width:w,height:h,depth:full.depth)
    var coverage: Surface? = document.selection != nil && original.smartObject == nil ? try Surface(width:w,height:h) : nil
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let sx = min(full.width-1,Int((Double(x)+0.5)*Double(full.width)/Double(w)))
        let sy = min(full.height-1,Int((Double(y)+0.5)*Double(full.height)/Double(h)))
        if full.depth == .f32 { pixels.setLinearPixel(x:x,y:y,full.linearPixel(x:sx,y:sy)) }
        else { pixels.setPixel(x:x,y:y,full.pixel(x:sx,y:sy)) }
        if coverage != nil {
          let p = layer.coordinateTransform.point(Double(sx)+0.5,Double(sy)+0.5)
          let a = document.selectionCoverage(x:Int(floor(p.x)),y:Int(floor(p.y)))
          coverage?.setPixel(x:x,y:y,Pixel(a,a,a))
        }
      }
    }
    return Self(pixels:pixels,coverage:coverage,width:full.width,height:full.height)
  }
  public func preview(_ field: LiquifyField) throws -> Surface {
    var result = try field.render(pixels,preview:true)
    guard let coverage else { return result }
    for y in 0..<pixels.height {
      try Task.checkCancellation()
      for x in 0..<pixels.width {
        let k = coverage.pixel(x:x,y:y).r
        if k >= 1 { continue }
        let a = pixels.depth == .f32 ? pixels.linearPixel(x:x,y:y) : pixels.pixel(x:x,y:y)
        let b = pixels.depth == .f32 ? result.linearPixel(x:x,y:y) : result.pixel(x:x,y:y)
        let alpha = a.a*(1-k)+b.a*k
        let rgb = alpha > 0 ? (a.rgb*a.a*(1-k)+b.rgb*b.a*k)/alpha : .zero
        let p = Pixel(rgb.x,rgb.y,rgb.z,alpha)
        if pixels.depth == .f32 { result.setLinearPixel(x:x,y:y,p) } else { result.setPixel(x:x,y:y,p) }
      }
    }
    return result
  }
}
