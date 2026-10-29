import Foundation

public enum ArtisticGalleryEngine {
  public static func render(_ source:Surface,settings:ArtisticGallerySettings)throws->Surface{
    try settings.validate();if settings.isIdentity{return source}
    let w=source.width,h=source.height,effects=settings.effects.filter(\.visible)
    guard w<=8_388_608/h,w*h<=67_108_864/max(1,effects.count) else{throw CraftError.unsupported("Filter Gallery exceeds its8MP layer or64M effect-pixel work limit.")}
    var colors=[GalleryMath.V]();colors.reserveCapacity(w*h)
    for y in 0..<h{try Task.checkCancellation();for x in 0..<w{let p=source.pixel(x:x,y:y);guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e6 else{throw CraftError.invalid("Invalid Filter Gallery input.")};colors.append(p.rgb)}}
    for effect in effects{try Task.checkCancellation();switch effect.filter.category{
      case "Artistic":colors=try GalleryMath.artistic(effect,colors,w,h)
      case "Sketch":colors=try GalleryMath.sketch(effect,colors,w,h)
      case "Texture":colors=try GalleryMath.textured(effect,colors,w,h)
      default:colors=try GalleryMath.brushDistort(effect,colors,w,h)
    }}
    var result=source
    for y in 0..<h{try Task.checkCancellation();for x in 0..<w{let c=colors[y*w+x];guard c.x.isFinite,c.y.isFinite,c.z.isFinite else{throw CraftError.invalid("Nonfinite gallery output.")};let p=Pixel(unit(c.x),unit(c.y),unit(c.z),source.pixel(x:x,y:y).a);result.setPixel(x:x,y:y,p)}}
    return result
  }
  static func apply(_ settings:ArtisticGallerySettings,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws{
    if settings.isIdentity{return};let edited=try render(source,settings:settings),matrix=document.layers[index].coordinateTransform,protect=document.isTransparencyLocked(layerID),linear=document.depth == .f32
    var result=source
    for y in 0..<source.height{try Task.checkCancellation();for x in 0..<source.width{let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)));if coverage<=0{continue}
      let a=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y);if protect && a.a==0{continue};let b=linear ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y),value=coverage>=1 ? b:a.mixing(b,coverage:coverage)
      if linear{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)}
    }};document.layers[index].content = .raster(result)
  }
}
