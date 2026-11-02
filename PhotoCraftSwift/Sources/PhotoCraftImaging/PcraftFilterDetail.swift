import Foundation
import PhotoCraftCore

enum PcraftFilterDetail {
  @inline(never) static func convert(_ kind:RasterFilter.Kind,_ p:PcraftFilterParameters)throws->RasterFilter {
    var f=RasterFilter(kind)
    if kind.isClassicDetail {
      var s=ClassicDetailSettings(kind:kind)
      switch kind {
      case .radialBlur:s.amount=try p.number("amount",10,1...100);s.method=try p.choice("method",ClassicDetailSettings.Method.spin);s.centerX=try p.number("centerX",0.5);s.centerY=try p.number("centerY",0.5)
      case .surfaceBlur:s.radius=try p.number("radius",5,1...100);s.threshold=try p.number("threshold",15,2...255)
      case .median:s.radius=try p.number("radius",1,1...500)
      case .dustAndScratches:s.radius=try p.number("radius",1,1...500);s.threshold=try p.number("threshold",0,0...255)
      case .smartBlur:s.radius=try p.number("radius",3,0.1...100);s.threshold=try p.number("threshold",25,0.1...100);s.quality=try p.choice("quality",ClassicDetailSettings.Quality.high);s.mode=try p.choice("mode",ClassicDetailSettings.Mode.normal)
      case .shapeBlur:s.radius=try p.number("radius",10,5...1000);s.shape=try p.choice("shape",ClassicDetailSettings.Shape.circle)
      default:break
      };f.classicDetail=s
    }else if kind.isOtherVideo {
      var s=OtherVideoSettings()
      switch kind {
      case .minimum,.maximum:s.radius=try p.number("radius",1,0.2...500);s.preserve=try p.choice("preserve",OtherVideoSettings.Preserve.squareness)
      case .offset:s.horizontal=Int(try p.integer("horizontal",0));s.vertical=Int(try p.integer("vertical",0));let edge=try p.string("undefinedAreas","wrap");s.undefinedAreas=edge=="repeat" ? .repeatEdge:edge=="transparent" ? .transparent:.wrap
      case .customFilter:
        if let array=p.field("kernel"){let values=try array.array();guard values.count==25 else{throw array.invalid};s.kernel=try values.map{v in let x=try v.float();let clamped=min(999,max(-999,x));guard clamped.rounded()==clamped else{throw v.unsupported("Fractional Custom coefficients require a native model extension.")};return Int(clamped)}}
        s.scale=try p.number("scale",1,1...9999);s.offset=try p.number("offset",0,-9999...9999)
      case .hsbHsl:s.inputMode=try p.choice("inputMode",OtherVideoSettings.ColorModel.rgb);s.outputMode=try p.choice("rowOrder",OtherVideoSettings.ColorModel.hsb)
      case .deInterlace:s.eliminate=try p.string("eliminate","oddFields")=="evenFields" ? .even:.odd;s.createBy=try p.string("createBy","interpolation")=="duplication" ? .duplication:.interpolation
      default:break
      };f.otherVideo=s
    }else if kind == .smartSharpen {
      var s=SmartSharpenSettings();s.amount=try p.number("amount",100,1...500);s.radius=try p.number("radius",1,0.1...64);s.reduceNoise=try p.number("reduceNoise",10,0...100);f.sharpen=s
    }else if kind == .reduceNoise {
      var s=ReduceNoiseSettings();s.strength=try p.number("strength",6,0...10);s.preserveDetails=try p.number("preserveDetails",60,0...100);s.reduceColorNoise=try p.number("reduceColorNoise",45,0...100);s.sharpenDetails=try p.number("sharpenDetails",25,0...100);s.removeJpegArtifact=try p.flag("removeJpegArtifact",false);f.denoise=s
    }else if kind == .lensBlur {
      var s=LensBlurSettings();s.radius=try p.number("radius",15,0...100);let shape=try p.string("shape","hexagon");s.blades=["triangle":3,"square":4,"pentagon":5,"heptagon":7,"octagon":8][shape] ?? 6
      s.bladeCurvature=try p.number("bladeCurvature",0,0...100);s.rotation=try p.number("rotation",0);let depth=try p.string("depthMap","none")
      guard depth != "layerMask" else{throw p.node.unsupported("Original Smart Filter layer-mask depth needs retained source context before migration.")};s.depthSource=depth=="transparency" ? .transparency:.none
      s.focalDistance=try p.number("focalDistance",0,0...255);s.invert=try p.flag("invert",false);s.brightness=try p.number("brightness",0,0...100);s.threshold=try p.number("threshold",255,0...255);s.noiseAmount=try p.number("noise",0,0...100);s.distribution=try p.choice("distribution",RasterFilter.Distribution.uniform);s.monochromatic=try p.flag("monochromatic",false);s.seed=try p.seed();f.lensBlur=s
    }
    return f
  }
}
