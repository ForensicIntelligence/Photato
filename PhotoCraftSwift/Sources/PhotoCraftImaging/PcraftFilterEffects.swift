import Foundation
import PhotoCraftCore

enum PcraftFilterEffects {
  @inline(never) static func convert(_ kind:RasterFilter.Kind,_ p:PcraftFilterParameters)throws->RasterFilter {
    var f=RasterFilter(kind)
    if kind.isStylize {
      var s=StylizeSettings(kind:kind)
      switch kind {
      case .diffuse:s.mode=try p.choice("mode",StylizeSettings.DiffuseMode.normal);s.seed=try p.seed()
      case .emboss:s.angle=try p.number("angle",135);s.height=try p.number("height",3,1...100);s.amount=try p.number("amount",100,1...500)
      case .extrude:s.type=try p.choice("type",StylizeSettings.ExtrudeType.blocks);s.size=try p.number("size",30,2...255);s.depth=try p.number("depth",30,1...255);s.depthMode=try p.choice("depthMode",StylizeSettings.DepthMode.random);s.solidFrontFaces=try p.flag("solidFrontFaces",false);s.maskIncompleteBlocks=try p.flag("maskIncompleteBlocks",false);s.seed=try p.seed()
      case .oilPaint:s.stylization=try p.number("stylization",4,0.1...10);s.cleanliness=try p.number("cleanliness",5,0...10);s.scale=try p.number("scale",1,0.1...10);s.bristleDetail=try p.number("bristleDetail",5,0...10);s.lighting=try p.flag("lighting",true);s.angle=try p.number("angle",-60);s.shine=try p.number("shine",1,0...10)
      case .tiles:s.count=Double(try p.integer("count",10,1...99));s.maxOffset=try p.number("maxOffset",10,1...99);s.fill=try p.choice("fill",StylizeSettings.TileFill.background);s.foreground=try p.color("foreground",.black);s.background=try p.color("background",.white);s.seed=try p.seed()
      case .traceContour:s.level=try p.number("level",128,0...255);s.edge=try p.choice("edge",StylizeSettings.ContourEdge.lower)
      case .wind:s.method=try p.choice("method",StylizeSettings.WindMethod.wind);s.direction=try p.string("direction","fromRight")=="fromLeft" ? .fromLeft:.fromRight;s.seed=try p.seed()
      default:break
      };f.stylize=s
    }else if kind.isRender {
      var s=RenderSettings(kind:kind)
      if kind == .fibers{s.variance=try p.number("variance",16,1...64);s.strength=try p.number("strength",4,1...64);s.foreground=try p.color("foreground",.black);s.background=try p.color("background",.white);s.seed=try p.seed()}
      if kind == .lensFlare{s.brightness=try p.number("brightness",100,10...300);s.centerX=try p.number("centerX",0.5,-0.5...1.5);s.centerY=try p.number("centerY",0.5,-0.5...1.5);s.lens=try p.choice("lens",RenderSettings.Lens.zoom)}
      f.renderSettings=s
    }else if kind.isDistortion {
      var s=DistortionSettings(kind:kind)
      switch kind {
      case .twirl:s.angle=try p.number("angle",50,-999...999)
      case .displace:
        s.horizontalScale=try p.number("horizontal",10,-999...999);s.verticalScale=try p.number("vertical",10,-999...999);s.fit=try p.string("fit","stretch")=="tile" ? .tile:.stretchToFit;s.edge=try edge(p,fallback:"repeat")
        var source=SourceDisplacement()
        if let path=p.field("mapPath"){source.reference.path=try path.string()}
        if let document=p.field("mapDocument"){if let name=document.value.string{source.reference.documentName=name}else{source.reference.documentIndex=try document.unsigned()}}
        if let layer=p.field("mapLayer"){source.reference.layerID=try layer.unsigned()}
        try source.validate();s.source=source
      case .pinch:s.amount=try p.number("amount",50,-100...100)
      case .spherize:s.amount=try p.number("amount",100,-100...100);s.sphereMode=try p.choice("mode",DistortionSettings.Sphere.normal)
      case .ripple:s.amount=try p.number("amount",100,-999...999);s.rippleSize=try p.choice("size",DistortionSettings.Ripple.medium)
      case .polarCoordinates:s.polarMode=try p.string("mode","rectangularToPolar")=="polarToRectangular" ? .polarToRectangular:.rectangularToPolar
      case .zigzag:s.amount=try p.number("amount",10,-100...100);s.ridges=try p.number("ridges",5,0...20);s.zigzagStyle=try p.choice("style",DistortionSettings.ZigZag.pondRipples)
      case .wave:
        s.generators=Int(try p.integer("generators",5,1...999));s.wavelengthMin=try p.number("wavelengthMin",10,1...998);s.wavelengthMax=try p.number("wavelengthMax",120,2...999);s.amplitudeMin=try p.number("amplitudeMin",5,1...998);s.amplitudeMax=try p.number("amplitudeMax",35,1...999);s.waveType=try p.choice("type",DistortionSettings.Wave.sine);s.seed=try p.seed();s.edge=try edge(p)
      case .shear:
        if let field=p.field("points"),!(try field.array()).isEmpty {s.points=try field.array().map{point in let a=try point.array();guard a.count==2 else{throw point.invalid};return try .init(Double(a[0].float()),Double(a[1].float()))}}
        else{let amount=Float(try p.number("amount",0,-100...100))/100;s.points=[.init(0,0),.init(0.5,Double(amount)),.init(1,0)]}
        s.edge=try edge(p)
      default:break
      };f.distortion=s
    }else {
      var s=PixelateSettings(kind:kind)
      switch kind {
      case .colorHalftone:s.maxRadius=try p.number("maxRadius",8,4...127);s.angles=try [p.number("channel1",108),p.number("channel2",162),p.number("channel3",90),p.number("channel4",45)]
      case .crystallize:s.cellSize=try p.number("cellSize",10,3...300);s.seed=try p.seed()
      case .pointillize:s.cellSize=try p.number("cellSize",5,3...300);s.seed=try p.seed();s.background=try p.color("background",.white)
      case .mezzotint:s.pattern=try p.choice("type",PixelateSettings.Pattern.fineDots);s.seed=try p.seed()
      default:break
      };f.pixelate=s
    }
    return f
  }
  private static func edge(_ p:PcraftFilterParameters,fallback:String="wrap")throws->DistortionSettings.Edge {
    let edge=try p.string("undefinedAreas",fallback)
    return edge=="transparent" ? .transparent:edge=="repeat" ? .repeatEdge:.wrapAround
  }
}
