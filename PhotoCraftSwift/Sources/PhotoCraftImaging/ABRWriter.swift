import Foundation
import PhotoCraftCore

extension ABRCodec {
  static func dynamicDescriptor(_ value:BrushDynamic)->PSDValue {
    let codes:[BrushControl:Int]=[.off:0,.fade:1,.penPressure:2,.penTilt:3,.stylusWheel:4,.initialDirection:5,.direction:6,.rotation:8]
    return .object(PSDDescriptor("brVr",items:[.init("bVTy",.integer(Int32(codes[value.control]!))),.init("jitter",.number(value.jitter*100)),.init("Mnm ",.number(value.minimum*100)),.init("fStp",.integer(Int32(value.fadeSteps)))]))
  }
  /// Modern ABR transport. Native-only stroke state and unsupported color capture must use the lossless native format.
  public static func write(_ presets:[BrushPreset])throws->Data {
    try BrushPresetFile(presets:presets).validate();guard !presets.isEmpty else { throw CraftError.invalid("Choose brushes to export.") }
    var samples=PSDWriter(),descriptors:[PSDValue]=[],patterns:[RasterPattern]=[]
    func str(_ value:String)->PSDValue { .text(Array(value.utf16)+[0]) }
    func addSample(_ tip:BrushBitmap)throws->String {
      try tip.validate();let id=UUID().uuidString;var body=PSDWriter();body.n(id.utf8.count,1);body.text(id);body.data.append(Data(repeating:0,count:10));body.n(0,4);body.n(0,4);body.n(tip.height,4);body.n(tip.width,4);body.n(8,2);body.n(0,1);body.data.append(tip.bytes)
      samples.section(body.data);samples.data.append(Data(repeating:0,count:(4-body.data.count%4)%4));return id
    }
    func tipDescriptor(_ brush:Brush)throws->PSDValue {
      let b=brush.settings ?? .init();var d=PSDDescriptor(b.tip==nil ? "computedBrush":"sampledBrush")
      d.items=[.init("Dmtr",.number(brush.size)),.init("Hrdn",.number(Double(brush.hardness)*100)),.init("Rndn",.number(b.roundness*100)),.init("Angl",.number(b.angle)),.init("Spcn",.number(b.spacing*100)),.init("Intr",.boolean(b.spacingEnabled)),.init("flipX",.boolean(b.flipX)),.init("flipY",.boolean(b.flipY))]
      if let tip=b.tip { d.items.append(.init("sampledData",str(try addSample(tip)))) };return .object(d)
    }
    for preset in presets {
      try Task.checkCancellation();let brush=preset.brush,b=brush.settings ?? .init()
      guard !preset.includeColor,preset.includeSize,b.symmetry.mode == .off,b.buildUpRate==20 else { throw CraftError.unsupported("ABR cannot preserve this preset's color/size-capture choice, symmetry or custom airbrush rate. Export Photato Brushes for a lossless copy.") }
      var d=PSDDescriptor("brushPreset",items:[.init("Nm  ",str(preset.name)),.init("Brsh",try tipDescriptor(brush))])
      func number(_ k:String,_ n:Double) { d.items.append(.init(k,.number(n))) }
      func flag(_ k:String,_ b:Bool) { d.items.append(.init(k,.boolean(b))) }
      func dyn(_ k:String,_ value:BrushDynamic) { d.items.append(.init(k,dynamicDescriptor(value))) }
      flag("useTipDynamics",b.shape.enabled);dyn("szVr",b.shape.size);dyn("angleDynamics",b.shape.angle);dyn("roundnessDynamics",b.shape.roundness);number("minimumDiameter",b.shape.size.minimum*100);number("minimumRoundness",b.shape.roundness.minimum*100);number("tiltScale",b.shape.tiltScale*100);flag("flipX",b.shape.flipX);flag("flipY",b.shape.flipY);flag("brushProjection",b.shape.projection)
      flag("useScatter",b.scattering.enabled);dyn("scatterDynamics",b.scattering.amount);number("Cnt ",Double(b.scattering.count));dyn("countDynamics",b.scattering.countJitter);flag("bothAxes",b.scattering.bothAxes)
      flag("useTexture",b.texture.enabled);flag("TxtC",b.texture.eachTip);number("textureScale",b.texture.scale*100);number("textureBrightness",b.texture.brightness*150);number("textureContrast",b.texture.contrast*50);number("textureDepth",b.texture.depth*100);dyn("textureDepthDynamics",b.texture.depthJitter);number("minimumDepth",b.texture.depthJitter.minimum*100);flag("InvT",b.texture.invert);flag("protectTexture",b.protectTexture)
      d.items.append(.init("textureBlendMode",.enumerated(PSDID("BlnM"),PSDID(b.texture.mode.rawValue))))
      if b.texture.enabled {
        let bitmap:BrushBitmap
        if let saved=b.texture.bitmap { bitmap=saved } else {
          var texture=b.texture;texture.scale=1;texture.brightness=0;texture.contrast=0;texture.invert=false;var bytes=Data(count:128*128)
          for y in 0..<128 { for x in 0..<128 { bytes[y*128+x]=UInt8((BrushPainter.texture(texture,Double(x)+0.5,Double(y)+0.5)*255).rounded()) } };bitmap = .init(width:128,height:128,bytes:bytes)
        }
        var surface=try Surface(width:bitmap.width,height:bitmap.height)
        for y in 0..<bitmap.height { for x in 0..<bitmap.width { let v=Float(bitmap.bytes[y*bitmap.width+x])/255;surface.setPixel(x:x,y:y,Pixel(v,v,v)) } }
        let pattern=try RasterPattern(name:preset.name+" Texture",surface:surface);patterns.append(pattern)
        d.items.append(.init("Txtr",.object(PSDDescriptor("Ptrn",items:[.init("Nm  ",str(pattern.name)),.init("Idnt",str(pattern.id))]))))
      }
      if b.dual.enabled {
        var q=Brush();q.size=b.dual.size;q.hardness=Float(b.dual.hardness);q.settings = .init();q.settings!.tip=b.dual.tip;q.settings!.roundness=b.dual.roundness;q.settings!.angle=b.dual.angle;q.settings!.spacing=b.dual.spacing
        var scatter=BrushDynamic();scatter.jitter=b.dual.scatter
        d.items.append(.init("dualBrush",.object(PSDDescriptor("dualBrush",items:[.init("useDualBrush",.boolean(true)),.init("Brsh",try tipDescriptor(q)),.init("BlnM",.enumerated(PSDID("BlnM"),PSDID(b.dual.mode.rawValue))),.init("Flip",.boolean(b.dual.flip)),.init("scatterDynamics",dynamicDescriptor(scatter)),.init("bothAxes",.boolean(b.dual.bothAxes)),.init("Cnt ",.integer(Int32(b.dual.count)))]))))
      }
      flag("useColorDynamics",b.colorDynamics.enabled);flag("colorDynamicsPerTip",b.colorDynamics.perTip);dyn("clVr",b.colorDynamics.foregroundBackground);number("H   ",b.colorDynamics.hue*100);number("Strt",b.colorDynamics.saturation*100);number("Brgh",b.colorDynamics.brightness*100);number("purity",b.colorDynamics.purity*100)
      flag("usePaintDynamics",b.transfer.enabled);dyn("opVr",b.transfer.opacity);dyn("prVr",b.transfer.flow)
      flag("useBrushPose",b.pose.enabled);number("brushPoseTiltX",b.pose.tiltX/0.9);number("brushPoseTiltY",b.pose.tiltY/0.9);number("brushPoseAngle",b.pose.rotation);number("brushPosePressure",b.pose.pressure*100);flag("overridePoseTiltX",b.pose.overrideTilt);flag("overridePoseTiltY",b.pose.overrideTilt);flag("overridePoseAngle",b.pose.overrideRotation);flag("overridePosePressure",b.pose.overridePressure)
      flag("Nose",b.noise);flag("Wtdg",b.wetEdges);flag("Rpt ",b.buildUp)
      if preset.includeToolSettings {
        let to=PSDDescriptor("paintbrushTool",items:[.init("Opct",.number(Double(brush.opacity)*100)),.init("flow",.number(b.flow*100)),.init("Md  ",.enumerated(PSDID("BlnM"),PSDID(PSDLayerStyles.blends[BlendMode.allCases.firstIndex(of:b.mode)!]))),.init("usePressureOverridesSize",.boolean(b.pressureSize)),.init("usePressureOverridesOpacity",.boolean(b.pressureOpacity)),.init("smoothing",.boolean(true)),.init("smoothingValue",.number(b.smoothing.amount*100)),.init("smoothingRadiusMode",.boolean(b.smoothing.pulledString)),.init("smoothingCatchup",.boolean(b.smoothing.catchUp)),.init("smoothingCatchupAtEnd",.boolean(b.smoothing.catchUpOnEnd)),.init("smoothingZoomCompensation",.boolean(b.smoothing.adjustForZoom))])
        d.items.append(.init("toolOptions",.object(to)))
      }
      descriptors.append(.object(d))
    }
    var out=PSDWriter();out.n(6,2);out.n(1,2)
    func section(_ key:String,_ data:Data) { out.text("8BIM");out.text(key);out.section(data);out.data.append(Data(repeating:0,count:(4-data.count%4)%4)) }
    if !samples.data.isEmpty { section("samp",samples.data) }
    if !patterns.isEmpty { section("patt",try PSDPatterns.write(patterns)) }
    section("desc",try PSDDescriptor("null",items:[.init("Brsh",.list(descriptors))]).encoded())
    guard out.data.count<=maximumBytes else { throw CraftError.invalid("ABR export exceeds64MiB.") };return out.data
  }
}
