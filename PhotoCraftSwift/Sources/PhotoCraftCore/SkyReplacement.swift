import Foundation

public enum SkyOutput:String,Codable,CaseIterable,Sendable {case layers,duplicate}
public enum SkyLightingMode:String,Codable,CaseIterable,Sendable {case multiply,screen}
public struct SkyReplacementSettings:Codable,Equatable,Sendable {
  public var selection=SkySelectionSettings()
  public var shiftEdge=0.0,fadeEdge=50.0,brightness=0.0,temperature=0.0,scale=100.0
  public var offsetX=0.0,offsetY=0.0
  public var flip=false
  public var lightingMode=SkyLightingMode.multiply
  public var foregroundLighting=50.0,edgeLighting=0.0,colorAdjustment=35.0
  public var output=SkyOutput.layers
  public init() {}
  public func validate()throws {
    try selection.validate()
    guard [shiftEdge,brightness,temperature].allSatisfy({$0.isFinite && (-100...100).contains($0)}),
      [fadeEdge,foregroundLighting,edgeLighting,colorAdjustment].allSatisfy({$0.isFinite && (0...100).contains($0)}),
      scale.isFinite,(10...500).contains(scale),[offsetX,offsetY].allSatisfy({$0.isFinite && abs($0)<=1_000_000})
    else{throw CraftError.invalid("Invalid Sky Replacement settings.")}
  }
  public func transform(sky:Surface,width:Int,height:Int)->Transform2D {
    let factor=max(Double(width)/Double(sky.width),Double(height)/Double(sky.height))*scale/100
    let left=(Double(width)-Double(sky.width)*factor)/2+offsetX,top=(Double(height)-Double(sky.height)*factor)/2+offsetY
    return .init(a:flip ? -factor:factor,b:0,c:0,d:factor,tx:left+(flip ? Double(sky.width)*factor:0),ty:top)
  }
}
public struct SkyMaskStroke:Codable,Equatable,Sendable {
  public var points:[StrokePoint],size:Double,hardness:Float,opacity:Float,add:Bool
  public init(points:[StrokePoint],size:Double=40,hardness:Float=0.5,opacity:Float=1,add:Bool=true){self.points=points;self.size=size;self.hardness=hardness;self.opacity=opacity;self.add=add}
  public func validate()throws {var brush=Brush();brush.size=size;brush.hardness=hardness;brush.opacity=opacity;var request=SelectionToolRequest(kind:.brush);request.brush=brush;request.points=points;try request.validate()}
}
public enum SkyReplacement {
  public static let maximumPixels=8_388_608
  public static func refined(_ mask:SelectionMask,settings:SkyReplacementSettings,strokes:[SkyMaskStroke])throws->SelectionMask {
    try settings.validate();guard mask.width<=maximumPixels/mask.height,strokes.count<=128,mask.width*mask.height<=134_217_728/max(1,strokes.count) else{throw CraftError.unsupported("Sky Replacement supports8,388,608 canvas pixels and128 refinement strokes.")}
    let w=mask.width,h=mask.height;var values=(try mask.bytes).map{Float($0)/255}
    let shift=Int((settings.shiftEdge/100*20).rounded())
    if shift != 0{values=try MattingFilters.morph(values,w,h,abs(shift),grow:shift>0)}
    if settings.fadeEdge>0{values=try MattingFilters.gaussian(values,w,h,Float(settings.fadeEdge/100*5))}
    var result=try SelectionMask(width:w,height:h,bytes:values.map{UInt8(min(255,max(0,($0*255).rounded())))})
    for stroke in strokes {
      try Task.checkCancellation();try stroke.validate();var document=try CraftDocument(width:w,height:h);document.setCoverageSelection(result)
      var request=SelectionToolRequest(kind:.brush);request.points=stroke.points;request.brush.size=stroke.size;request.brush.hardness=stroke.hardness;request.brush.opacity=stroke.opacity;request.mode=stroke.add ? .add:.subtract
      result=try request.paintedSelection(in:document)
    }
    return result
  }
  public static func edgeMask(_ mask:SelectionMask)throws->SelectionMask {
    let v=(try mask.bytes).map{Float($0)/255},w=mask.width,h=mask.height
    let hi=try MattingFilters.extreme(v,w,h,5,maximum:true),lo=try MattingFilters.extreme(v,w,h,5,maximum:false)
    return try .init(width:w,height:h,bytes:v.indices.map{UInt8(min(255,max(0,((hi[$0]-lo[$0])*(1-v[$0])*255).rounded())))})
  }
}
public struct SkyReplacementEdit:Sendable {
  public let source:CraftDocument,result:CraftDocument
  public init(source:CraftDocument,result:CraftDocument){self.source=source;self.result=result}
  public func applied(to document:CraftDocument)throws->CraftDocument {guard document==source else{throw CraftError.invalid("Sky Replacement source changed; preview again.")};try result.validate();return result}
}
