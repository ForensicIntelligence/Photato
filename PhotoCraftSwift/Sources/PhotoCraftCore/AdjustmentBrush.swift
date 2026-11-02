import Foundation

public enum AdjustmentBrushKind: String, Codable, CaseIterable, Sendable {
  case brightnessContrast, levels, curves, exposure, vibrance, hueSaturation, colorBalance
  case blackWhite, photoFilter, channelMixer, selectiveColor, invert, posterize, threshold, gradientMap
  public var title: String {
    switch self {
    case .brightnessContrast: "Brightness/Contrast"; case .levels: "Levels"; case .curves: "Curves"
    case .exposure: "Exposure"; case .vibrance: "Vibrance"; case .hueSaturation: "Hue/Saturation"
    case .colorBalance: "Color Balance"; case .blackWhite: "Black & White"; case .photoFilter: "Photo Filter"
    case .channelMixer: "Channel Mixer"; case .selectiveColor: "Selective Color"; case .invert: "Invert"
    case .posterize: "Posterize"; case .threshold: "Threshold"; case .gradientMap: "Gradient Map"
    }
  }
  /// Native starting values; Adobe's complete preset/default catalogue is separately qualified.
  public var initial: Adjustment {
    switch self {
    case .brightnessContrast: .brightnessContrast(0.15,1)
    case .levels: .levels(.init()); case .curves: .curves(.init()); case .exposure: .classic(.exposure(.init(exposure: 1)))
    case .vibrance: .classic(.init(.vibrance)); case .hueSaturation: .hueSaturation(.init())
    case .colorBalance: .colorBalance(.init()); case .blackWhite: .classic(.init(.blackWhite))
    case .photoFilter: .classic(.init(.photoFilter)); case .channelMixer: .classic(.init(.channelMixer))
    case .selectiveColor: .classic(.init(.selectiveColor)); case .invert: .invert
    case .posterize: .tonalSteps(.init(kind:.posterize)); case .threshold: .tonalSteps(.init(kind:.threshold))
    case .gradientMap: .gradientMap(.init())
    }
  }
  public init?(adjustment: Adjustment) {
    switch adjustment {
    case .brightnessContrast:self = .brightnessContrast;case .levels:self = .levels;case .curves:self = .curves
    case .exposure:self = .exposure;case .hueSaturation:self = .hueSaturation;case .colorBalance:self = .colorBalance
    case .classic(let v):
      switch v.kind {case .exposure:self = .exposure;case .vibrance:self = .vibrance;case .blackWhite:self = .blackWhite;case .photoFilter:self = .photoFilter;case .channelMixer:self = .channelMixer;case .selectiveColor:self = .selectiveColor}
    case .invert:self = .invert;case .tonalSteps(let v):self = v.kind == .threshold ? .threshold:.posterize
    case .gradientMap:self = .gradientMap
    default:return nil
    }
  }
}

public struct AdjustmentBrushRequest: Codable, Equatable, Sendable {
  public var layerID: UUID?
  public var newLayerID: UUID
  public var adjustment: Adjustment
  public var points: [StrokePoint]
  public var brush: Brush
  public var subtract: Bool
  public var objectMask: SelectionMask?
  public init(layerID:UUID? = nil,newLayerID:UUID = UUID(),adjustment:Adjustment,points:[StrokePoint],brush:Brush,subtract:Bool = false) {
    self.layerID=layerID;self.newLayerID=newLayerID;self.adjustment=adjustment;self.points=points;self.brush=brush;self.subtract=subtract
  }
  public func validate() throws {
    try adjustment.validate();try BrushPainter.validate(brush,points:points)
    guard AdjustmentBrushKind(adjustment:adjustment) != nil else {throw CraftError.unsupported("Choose an available Adjustment Brush type.")}
    guard objectMask == nil || points.isEmpty else {throw CraftError.invalid("Choose brush samples or an object mask, not both.")}
  }
  public func apply(to document:inout CraftDocument) throws {
    try validate();try Task.checkCancellation()
    guard !points.isEmpty || objectMask != nil else {return}
    var d=document
    if let objectMask {guard objectMask.width==d.width,objectMask.height==d.height else {throw CraftError.invalid("Object mask size does not match the document.")}}
    let id:UUID
    if let layerID {id=layerID} else {
      guard !subtract else {throw CraftError.invalid("Paint an adjustment before subtracting from it.")}
      var layer=Layer(name:AdjustmentBrushKind(adjustment:adjustment)!.title,content:.adjustment(adjustment));layer.id=newLayerID
      layer.mask=try Surface(width:d.width,height:d.height,depth:d.depth,fill:.black)
      try d.insertNewLayer(layer);id=newLayerID
    }
    guard let i=d.layers.firstIndex(where:{$0.id==id}),case .adjustment=d.layers[i].content,d.layers[i].smartObject==nil,d.layers[i].mask != nil else {throw CraftError.invalid("Choose an adjustment layer with a pixel mask.")}
    guard !d.isLocked(id) else {throw CraftError.invalid("Unlock the adjustment layer and its groups.")}
    var layer=d.layers[i],brush=brush
    guard layer.effectiveMaskProperties.enabled else {throw CraftError.invalid("Enable the adjustment mask before painting.")}
    let before=layer.mask
    let value:Float = subtract != layer.effectiveMaskProperties.inverted ? 0:1
    brush.color=Pixel(value,value,value);brush.backgroundColor=brush.color;brush.erase=false
    // Mask tools paint coverage, independent of foreground color and RGB color dynamics.
    brush.settings=brush.settings ?? .init();brush.settings!.mode = .normal;brush.settings!.colorDynamics.enabled=false
    if let region=objectMask {
      try layer.expandMask(toDocumentBounds:.init(x:0,y:0,width:d.width,height:d.height))
      var mask=layer.mask!;guard mask.width<=16_777_216/max(1,mask.height) else {throw CraftError.unsupported("Adjustment object masks support at most16MP stored samples.")}
      let transform=layer.maskCoordinateTransform
      for y in 0..<mask.height {
        try Task.checkCancellation()
        for x in 0..<mask.width {
          let p=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(p.x)),dy=Int(floor(p.y))
          let amount=region.coverage(x:dx,y:dy)*d.selectionCoverage(x:dx,y:dy)
          guard amount>0 else {continue};let old=mask.pixel(x:x,y:y),v=old.r+(value-old.r)*amount
          let pixel=Pixel(v,v,v).quantized(mask.depth)
          if !pixel.hasSameBits(as:old) {mask.setPixel(x:x,y:y,pixel)}
        }
      }
      layer.mask=mask
    } else {
      try layer.expandMask(for:points,brush:brush,clipping:d.selection)
      var mask=layer.mask!
      try Painter.stroke(surface:&mask,points:points,brush:brush,selection:d.selection,selectionMask:d.selectionMask,transform:layer.maskCoordinateTransform,grayscaleMask:true)
      layer.mask=mask
    }
    if layerID==nil && layer.mask==before {return}
    layer.content = .adjustment(adjustment);d.layers[i]=layer;d.activeLayerID=id
    try d.validate();try Task.checkCancellation();document=d
  }
}

/// Recorded object coverage is explicit data; playback never silently invokes a new model.
public struct RecordedAdjustmentBrush:Codable,Sendable {
  public var target:ActionLayerTarget?
  public var request:AdjustmentBrushRequest
  public init(_ request:AdjustmentBrushRequest,in document:CraftDocument) {
    target=request.layerID.map{ActionLayerTarget($0,in:document)};self.request=request
    self.request.layerID=nil
  }
  public func command(in document:CraftDocument)throws->Command {
    var value=request;value.layerID=try target?.resolve(in:document);value.newLayerID=UUID()
    return .adjustmentBrush(value)
  }
}
