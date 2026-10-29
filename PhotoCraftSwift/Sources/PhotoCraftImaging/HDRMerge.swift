import Foundation
import ImageIO
import PhotoCraftCore

public enum HDRMerge {
  public static let maximumPixels = 16_000_000
  public static let maximumTotalPixels = 32_000_000
  public struct Result: Sendable {
    public let document: CraftDocument
    public let exposureEV: [Double]
    public let exposureSource: HDRMergeSettings.ExposureSource
    public let offsets: [[Int]]
    public let ghostBase: Int
    public let ghostFraction: Double
    public let stops: Double
    public let response: [[Double]]
  }
  public static func exposureFactor(_ document: CraftDocument) -> Double? {
    guard let data = document.sourceMetadata?[RasterMetadata.propertiesKey],data.count <= RasterMetadata.maximumBytes,
      let properties = try? PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any],
      let exif = properties[kCGImagePropertyExifDictionary as String] as? [String:Any],
      let time = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue,
      let aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue,
      let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue,
      time.isFinite,aperture.isFinite,iso.isFinite,time > 0,aperture > 0,iso > 0 else { return nil }
    let factor = time*iso/(100*aperture*aperture);return factor.isFinite && factor > 0 ? factor:nil
  }
  public static func prepare(_ sources: [CraftDocument],settings s: HDRMergeSettings,name: String = "Untitled HDR") throws -> Result {
    try s.validate(count:sources.count);try Task.checkCancellation()
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 256 else { throw CraftError.invalid("Choose an HDR name with1–256 characters.") }
    let first = sources[0],w = first.width,h = first.height
    guard w*h <= maximumPixels,w*h <= maximumTotalPixels/sources.count else { throw CraftError.unsupported("HDR merge supports16 megapixels per image and32 megapixels combined.") }
    guard sources.allSatisfy({$0.width == w && $0.height == h}) else { throw CraftError.invalid("HDR source photographs must have the same pixel dimensions.") }
    var working = try CraftDocument(width:w,height:h,depth:.f32),images = [[HDRMergeMath.Sample]]()
    working.name = name;working.resolution = first.resolution
    for source in sources {
      try Task.checkCancellation();try source.validate()
      let flat = try Renderer.composite(source),converted = try ColorManagement.converted(flat,from:source,to:working)
      var values = [HDRMergeMath.Sample]();values.reserveCapacity(w*h)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let p = converted.pixel(x:x,y:y)
        guard p.isFinite,p.a > 0.999 else { throw CraftError.unsupported("HDR merge requires opaque source photographs. Flatten transparency onto a background first.") }
        if source.depth == .f32 { let q = flat.linearPixel(x:x,y:y);guard min(q.r,q.g,q.b) >= 0,max(q.r,q.g,q.b) <= 1.00001 else { throw CraftError.unsupported("Use exposure brackets in the camera/display range. Existing extended-range HDR images should be tone mapped directly.") } }
        values.append(.init(unit(p.r),unit(p.g),unit(p.b),1))
      } };images.append(values)
    }
    var exposures: [Double]
    switch s.exposureSource {
    case .manual:exposures = s.exposureEV.map{pow(2,$0)}
    case .estimate:exposures = try HDRMergeMath.estimate(images)
    case .metadata:
      let values = sources.map(exposureFactor)
      guard values.allSatisfy({$0 != nil}) else { throw CraftError.invalid("Exposure metadata is missing. Enter each image’s EV, or choose Estimate from Images.") };exposures = values.map{$0!}
    }
    let minimum = exposures.min()!;exposures = exposures.map{$0/minimum}
    guard exposures.allSatisfy({$0.isFinite && $0 > 0 && $0 <= pow(2,40)}) else { throw CraftError.invalid("The bracket exceeds the40-stop relative exposure limit.") }
    let order = exposures.indices.sorted{exposures[$0] < exposures[$1]},mid = order[order.count/2]
    var offsets = [[Int]](repeating:[0,0],count:sources.count)
    if s.align {
      let k = max(1,(max(w,h)+1535)/1536),sw = (w+k-1)/k,sh = (h+k-1)/k
      func gray(_ input: [HDRMergeMath.Sample]) throws -> [Float] {
        var g = [Float](repeating:0,count:sw*sh),counts = g
        for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let q = input[y*w+x],j = (y/k)*sw+x/k;g[j] += (54*q.x+183*q.y+19*q.z)/256;counts[j] += 1 } }
        return g.indices.map{g[$0]/max(1,counts[$0])}
      }
      let reference = try gray(images[mid])
      for j in images.indices where j != mid {
        let shift = try HDRMergeMath.offset(width:sw,height:sh,reference:reference,image:gray(images[j]));let dx = shift.x*k,dy = shift.y*k;offsets[j] = [dx,dy]
        if dx != 0 || dy != 0 {
          let original = images[j];var shifted = [HDRMergeMath.Sample](repeating:.zero,count:w*h)
          for y in 0..<h { try Task.checkCancellation();let sy = y-dy;guard sy >= 0,sy < h else { continue }
            for x in 0..<w { let sx = x-dx;if sx >= 0,sx < w { shifted[y*w+x] = original[sy*w+sx] } }
          };images[j] = shifted
        }
      }
    }
    let merged = try HDRMergeMath.merge(width:w,height:h,images:images,exposures:exposures,removeGhosts:s.removeGhosts,ghostBase:s.ghostBase)
    let pixels = s.depth == .f32 ? merged.pixels:try HDRMergeMath.toneMap(merged.pixels,width:w,height:h,settings:s)
    working.depth = s.depth
    var surface = try Surface(width:w,height:h,depth:s.depth,colorEncoding:s.depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let q = pixels[y*w+x],p = Pixel(q.x,q.y,q.z,q.w)
      if s.depth == .f32 { surface.setLinearPixel(x:x,y:y,p) } else { surface.setPixel(x:x,y:y,p) }
    } }
    working.layers = [Layer(name:"HDR Merge",content:.raster(surface))];working.activeLayerID = working.layers[0].id
    try working.validate();return Result(document:working,exposureEV:exposures.map(log2),exposureSource:s.exposureSource,offsets:offsets,ghostBase:merged.ghostBase,ghostFraction:merged.ghostFraction,stops:merged.stops,response:merged.response)
  }
  /// Display exposure never changes the new document's32-bit samples.
  public static func preview(_ result: Result,exposure: Double) throws -> CGImage {
    guard exposure.isFinite,(-20...20).contains(exposure) else { throw CraftError.invalid("Invalid HDR preview exposure.") }
    var surface = try Renderer.composite(result.document)
    if result.document.depth == .f32 {
      let k = Float(pow(2,exposure));for y in 0..<surface.height { try Task.checkCancellation();for x in 0..<surface.width { let p = surface.linearPixel(x:x,y:y);surface.setLinearPixel(x:x,y:y,Pixel(p.r*k,p.g*k,p.b*k,p.a)) } }
    }
    return try ColorManagement.displayImage(surface,in:result.document)
  }
}
