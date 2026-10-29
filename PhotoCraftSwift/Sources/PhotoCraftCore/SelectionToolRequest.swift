import Foundation

public enum SelectionToolKind:String,Codable,CaseIterable,Sendable {
  case object,quick,brush
  public var title:String {switch self {case .object:"Object Selection";case .quick:"Quick Selection";case .brush:"Selection Brush"}}
}
public struct SelectionToolRequest:Codable,Sendable {
  public var kind:SelectionToolKind
  public var layerID:UUID?
  public var sampleAllLayers=false
  public var mode:SelectionMode = .add
  public var points:[StrokePoint]=[]
  public var brush=Brush()
  public var region:SelectionShape?
  public var enhanceEdge=false
  public var hardEdge=false
  public init(kind:SelectionToolKind){self.kind=kind}
  public func validate()throws {
    guard points.count<=4096 else{throw CraftError.invalid("Selection tools support at most4096 samples per stroke.")}
    try BrushPainter.validate(brush,points:points)
    if kind == .object {
      guard (region != nil && points.isEmpty) || (region==nil && points.count==1) else{throw CraftError.invalid("Object Selection requires one point or one region.")}
    } else {guard region==nil,!points.isEmpty else{throw CraftError.invalid("Selection painting requires stroke samples.")}}
  }
  public func paintedSelection(in document:CraftDocument)throws->SelectionMask {
    try validate();guard kind == .brush else{throw CraftError.invalid("Choose Selection Brush.")}
    guard document.width<=SelectionSegmentation.maximumPixels/max(1,document.height) else{throw CraftError.unsupported("Selection painting supports at most16MP.")}
    let old=try document.coverageSelection()
    var raster=try Surface(width:document.width,height:document.height,fill:.black)
    if mode == .add || mode == .subtract,let old {
      for y in 0..<document.height {try Task.checkCancellation();for x in 0..<document.width {let value=old.coverage(x:x,y:y);if value>0{raster.setPixel(x:x,y:y,Pixel(value,value,value))}}}
    }
    var value=brush;let gray:Float=mode == .subtract ? 0:1
    value.color=Pixel(gray,gray,gray);value.backgroundColor=value.color;value.erase=false;value.settings=value.settings ?? .init();value.settings!.colorDynamics.enabled=false;value.settings!.mode = .normal
    try Painter.stroke(surface:&raster,points:points,brush:value,grayscaleMask:true)
    var bytes=[UInt8](repeating:0,count:document.width*document.height)
    for y in 0..<document.height {try Task.checkCancellation();for x in 0..<document.width {bytes[y*document.width+x]=UInt8((min(1,max(0,raster.pixel(x:x,y:y).r))*255).rounded())}}
    let mask=try SelectionMask(width:document.width,height:document.height,bytes:bytes)
    return mode == .intersect ? try mask.combined(with:old,mode:.intersect):mask
  }
}
