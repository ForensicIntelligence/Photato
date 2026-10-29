import Foundation

/// Editable layout instructions. Paths and dimensions use the type layer's logical pixels.
public struct TypeWarp:Codable,Equatable,Sendable {
  public var style:WarpStyle = .none
  public var bend:Double=0,horizontalDistortion:Double=0,verticalDistortion:Double=0
  public var vertical=false
  public init(){}
  private var engine:WarpDefinition {var value=WarpDefinition();value.style=style;value.bend=bend;value.horizontalDistortion=horizontalDistortion;value.verticalDistortion=verticalDistortion;value.vertical=vertical;return value}
  public var isIdentity:Bool{engine.isIdentity}
  public func validate()throws{try engine.validate()}
  public func point(_ x:Double,_ y:Double,width:Double,height:Double)->PathPoint{engine.point(x,y,width:width,height:height)}
}
public struct TextGeometry:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable {case warp,path,inside,block,circle,arch,bow}
  public var mode:Mode = .warp
  public var width:Double=400,height:Double=200
  public var path:VectorPath?
  public var warp=TypeWarp()
  public var fit=false,reverse=false
  public var start:Double=0,end:Double=1,offset:Double=0
  public var wordSpacing:Double=0,lineSpacing:Double=0
  public init(){}
  public var isActive:Bool{mode != .warp || !warp.isIdentity}
  public func validate()throws {
    guard [width,height].allSatisfy({$0.isFinite && (1...16384).contains($0)}),width*height<=16_777_216,
      start.isFinite,end.isFinite,(0...1).contains(start),(0...1).contains(end),end-start>=0.0001,
      [offset,wordSpacing,lineSpacing].allSatisfy({$0.isFinite && abs($0)<=4096})
    else{throw CraftError.invalid("Invalid shaped-text frame, path interval or spacing.")}
    if mode != .warp,!warp.isIdentity{throw CraftError.invalid("Warp settings belong to Warp text layout.")}
    try warp.validate();guard warp.style != .custom else{throw CraftError.unsupported("Type Warp uses the fifteen preset styles.")}
    if mode == .path || mode == .inside {
      guard let path,!path.isEmpty,!path.inverted else{throw CraftError.invalid("Shaped text requires a nonempty path.")};try path.validate()
      if mode == .path {guard path.components.count==1,path.components[0].knots.count>=2 else{throw CraftError.invalid("Text on a path requires one connected contour.")}}
      else{guard path.components.allSatisfy({$0.closed && $0.knots.count>=3}) else{throw CraftError.invalid("Text inside a path requires closed contours.")}}
    }else if path != nil{throw CraftError.invalid("Only path layouts store a custom path.")}
  }
  public func baselinePath()throws->PathComponent {
    try validate()
    if mode == .path{return path!.components[0]}
    guard [.circle,.arch,.bow].contains(mode) else{throw CraftError.invalid("This layout has no baseline path.")}
    let a=mode == .circle ? -Double.pi/2:Double.pi,b=mode == .circle ? 3*Double.pi/2:mode == .arch ? 2*Double.pi:0
    let points=(0...128).map{i->PathPoint in let t=a+(b-a)*Double(i)/128;return .init(width/2+width/2*cos(t),height/2+height/2*sin(t))}
    // Cubic handles along each sampled chord keep evaluation deterministic and bounded.
    return PathComponent(knots:points.map{.init($0)},closed:false)
  }
}
extension TextTypography {public var requiresShapedText:Bool{geometry != nil}}
extension CraftDocument {public var hasShapedText:Bool{layers.contains{if case .text(let t)=$0.content{return t.typography?.geometry != nil};return false}}}
