import Foundation
import PhotoCraftCore

/// Editable original program mapping. Unsupported engines/context still reject;
/// no disabled or unknown source stage is silently dropped.
enum PcraftSmartFilters {
  static let kinds:[String:RasterFilter.Kind]=[
    "filter.blur.blur":.blur,
    "filter.blur.blurMore":.blurMore,
    "filter.blur.gaussianBlur":.gaussianBlur,
    "filter.blur.boxBlur":.boxBlur,
    "filter.blur.motionBlur":.motionBlur,
    "filter.blur.radialBlur":.radialBlur,
    "filter.blur.surfaceBlur":.surfaceBlur,
    "filter.blur.smartBlur":.smartBlur,
    "filter.blur.shapeBlur":.shapeBlur,
    "filter.blur.lensBlur":.lensBlur,
    "filter.sharpen.sharpen":.sharpen,
    "filter.sharpen.sharpenMore":.sharpenMore,
    "filter.sharpen.sharpenEdges":.sharpenEdges,
    "filter.sharpen.unsharpMask":.unsharpMask,
    "filter.sharpen.smartSharpen":.smartSharpen,
    "filter.noise.despeckle":.despeckle,
    "filter.noise.addNoise":.addNoise,
    "filter.noise.median":.median,
    "filter.noise.dustAndScratches":.dustAndScratches,
    "filter.noise.reduceNoise":.reduceNoise,
    "filter.other.highPass":.highPass,
    "filter.other.minimum":.minimum,
    "filter.other.maximum":.maximum,
    "filter.other.offset":.offset,
    "filter.other.custom":.customFilter,
    "filter.other.hsbHsl":.hsbHsl,
    "filter.pixelate.mosaic":.mosaic,
    "filter.pixelate.colorHalftone":.colorHalftone,
    "filter.pixelate.crystallize":.crystallize,
    "filter.pixelate.facet":.facet,
    "filter.pixelate.fragment":.fragment,
    "filter.pixelate.mezzotint":.mezzotint,
    "filter.pixelate.pointillize":.pointillize,
    "filter.stylize.emboss":.emboss,
    "filter.stylize.findEdges":.findEdges,
    "filter.stylize.solarize":.solarize,
    "filter.stylize.diffuse":.diffuse,
    "filter.stylize.extrude":.extrude,
    "filter.stylize.oilPaint":.oilPaint,
    "filter.stylize.tiles":.tiles,
    "filter.stylize.traceContour":.traceContour,
    "filter.stylize.wind":.wind,
    "filter.distort.displace":.displace,
    "filter.distort.twirl":.twirl,
    "filter.distort.pinch":.pinch,
    "filter.distort.spherize":.spherize,
    "filter.distort.wave":.wave,
    "filter.distort.ripple":.ripple,
    "filter.distort.polarCoordinates":.polarCoordinates,
    "filter.distort.shear":.shear,
    "filter.distort.zigZag":.zigzag,
    "filter.render.lightingEffects":.lightingEffects,
    "filter.render.relight":.relight,
    "filter.render.fibers":.fibers,
    "filter.render.lensFlare":.lensFlare,
    "filter.video.deInterlace":.deInterlace,
    "filter.video.ntscColors":.ntscColors,
    "filter.blurGallery.fieldBlur":.blurGallery,
    "filter.blurGallery.irisBlur":.blurGallery,
    "filter.blurGallery.tiltShift":.blurGallery,
    "filter.blurGallery.pathBlur":.blurGallery,
    "filter.blurGallery.spinBlur":.blurGallery
  ]
  static var commands:[String] {(Array(kinds.keys)+["filter.filterGallery"]+GalleryFilter.allCases.map{"filter.gallery."+$0.rawValue}).sorted()}
  @inline(never) static func convert(_ command:String,_ node:PcraftNode)throws->RasterFilter {
    if command=="filter.filterGallery" || command.hasPrefix("filter.gallery."){return try PcraftFilterGallery.convert(command,node)}
    guard let kind=kinds[command] else{throw node.unsupported("Smart Filter program '\(command)' needs its native editable engine/context before import.")}
    let p=try PcraftFilterParameters(node)
    let filter:RasterFilter
    if kind == .lightingEffects {filter=try PcraftLightingFilter.convert(p)}else if kind == .relight {
      var s=RelightSettings();s.angle=try p.number("angle",45,-180...180);s.elevation=try p.number("elevation",40,0...90);s.intensity=try p.number("intensity",40,0...100);s.ambient=try p.number("ambient",55,0...100);s.warmth=try p.number("warmth",0,-100...100);s.softness=try p.number("softness",25,1...100);var f=RasterFilter(.relight);f.relight=s;filter=f
    }else if kind.isClassicDetail || kind.isOtherVideo || kind == .smartSharpen || kind == .reduceNoise || kind == .lensBlur {filter=try PcraftFilterDetail.convert(kind,p)}
    else if kind.isStylize || kind.isRender || kind.isDistortion || [.colorHalftone,.crystallize,.mezzotint,.pointillize,.facet,.fragment].contains(kind){filter=try PcraftFilterEffects.convert(kind,p)}
    else if kind == .blurGallery{filter=try PcraftFilterBlurGallery.convert(command,p)}
    else {filter=try basic(kind,p)}
    try p.finish();try filter.validate();return filter
  }
  @inline(never) private static func basic(_ kind:RasterFilter.Kind,_ p:PcraftFilterParameters)throws->RasterFilter {
    var f=RasterFilter(kind)
    switch kind {
    case .gaussianBlur:f.radius=try p.number("radius",1,0.1...1000)
    case .boxBlur:f.radius=try p.number("radius",1,1...2000)
    case .motionBlur:f.angle=try p.number("angle",0);f.distance=try p.number("distance",10,1...2000)
    case .unsharpMask:f.amount=try p.number("amount",50,1...500);f.radius=try p.number("radius",1,0.1...1000);f.threshold=try p.number("threshold",0,0...255)
    case .highPass:f.radius=try p.number("radius",10,0.1...1000)
    case .mosaic:f.cellSize=try p.number("cellSize",10,2...200)
    case .addNoise:f.amount=try p.number("amount",12.5,0.1...400);f.monochromatic=try p.flag("monochromatic",false);f.distribution=try p.choice("distribution",RasterFilter.Distribution.uniform);f.seed=try p.seed()
    default:break
    }
    return f
  }
}
