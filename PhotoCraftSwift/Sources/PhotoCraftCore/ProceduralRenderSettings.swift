import Foundation

/// Procedural designs translated from PhotoCraft render2.rs (MIT OR Apache-2.0).
/// Native source parity does not establish Photoshop output equivalence.
public struct FlameSettings: Codable, Equatable, Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable {case oneFlameAlongPath,multipleFlamesAlongPath,multipleFlamesPathDirections,multipleFlamesVariousLength,candleLight,multipleFlamesOneDirection}
  public enum Style:String,Codable,CaseIterable,Sendable {case normal,violent,flat}
  public enum Shape:String,Codable,CaseIterable,Sendable {case parallel,toCenter,spread,oval,pointed}
  public var flameType:Mode = .oneFlameAlongPath
  public var length:Float=150, width:Float=40, angle:Float=0, interval:Float=60
  public var randomizeLength=false, adjustIntervalForLoops=true, useCustomColor=false
  public var color=Pixel(1,0.5,0.1)
  public var turbulent:Float=25,jag:Float=25,opacity:Float=75,flameLines:Float=20,flameBottomAlignment:Float=20
  public var flameStyle:Style = .normal,flameShape:Shape = .parallel
  public var randomizeShapes=false
  public var seed:UInt32=0
  public var quality:Int=2
  public init() {}
  public func validate()throws {
    try ProceduralRenderSettings.range([length,width,interval],1...1000)
    try ProceduralRenderSettings.range([angle],-180...180)
    try ProceduralRenderSettings.range([turbulent,jag,opacity,flameBottomAlignment],0...100)
    try ProceduralRenderSettings.range([flameLines],1...100)
    guard (0...4).contains(quality) else {throw CraftError.invalid("Flame quality must be0–4.")}
    try ProceduralRenderSettings.color(color)
  }
}
public struct TreeSettings: Codable,Equatable,Sendable {
  public var baseTreeType=1,lightDirection=3
  public var leavesAmount:Float=50,leavesSize:Float=100,branchesHeight:Float=100,branchesThickness:Float=100
  public var defaultLeaves=true,customBranchColor=false,flatShading=false
  public var leavesColor=Pixel(0.24,0.52,0.16),branchesColor=Pixel(0.36,0.25,0.16)
  public var seed:UInt32=0
  public var x:Float=0.5,y:Float=0.95,size:Float=0.8
  public init() {}
  public func validate()throws {
    guard (1...34).contains(baseTreeType),(1...5).contains(lightDirection) else {throw CraftError.invalid("Invalid tree type or light direction.")}
    try ProceduralRenderSettings.range([leavesAmount],0...100);try ProceduralRenderSettings.range([leavesSize],0...200)
    try ProceduralRenderSettings.range([branchesHeight],50...300);try ProceduralRenderSettings.range([branchesThickness],50...200)
    try ProceduralRenderSettings.range([x,y],0...1);try ProceduralRenderSettings.range([size],0.05...2)
    try ProceduralRenderSettings.color(leavesColor);try ProceduralRenderSettings.color(branchesColor)
  }
}
public struct PictureFrameSettings:Codable,Equatable,Sendable {
  public static let styles=["vineWithFlowers","vineWithLeaves","ivy","roses","daisies","berries","bamboo","waves","zigzag","dots","rope","scallops","doubleLine","snowflakes","stars","hearts"]
  public var frame=1,lines=1
  public var margin:Float=4,size:Float=50,arrangement:Float=50,thickness:Float=30,fade:Float=0
  public var vineColor=Pixel(0.25,0.4,0.15),flowerColor=Pixel(0.9,0.3,0.45),leafColor=Pixel(0.3,0.6,0.2)
  public var seed:UInt32=0
  public init() {}
  public func validate()throws {
    guard (1...16).contains(frame),(1...5).contains(lines) else {throw CraftError.invalid("Invalid frame design or line count.")}
    try ProceduralRenderSettings.range([margin],0...30);try ProceduralRenderSettings.range([size,arrangement,thickness],1...100)
    try ProceduralRenderSettings.range([fade],0...100)
    for c in [vineColor,flowerColor,leafColor] {try ProceduralRenderSettings.color(c)}
  }
}
public struct ProceduralRenderSettings:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {
    case flame,tree,pictureFrame
    public var title:String {switch self {case .flame:"Flame";case .tree:"Tree";case .pictureFrame:"Picture Frame"}}
  }
  public var kind:Kind
  public var flame=FlameSettings(),tree=TreeSettings(),frame=PictureFrameSettings()
  public init(_ kind:Kind) {self.kind=kind}
  public func validate()throws {try flame.validate();try tree.validate();try frame.validate()}
  static func range(_ values:[Float],_ bounds:ClosedRange<Float>)throws {guard values.allSatisfy({$0.isFinite && bounds.contains($0)}) else {throw CraftError.invalid("Procedural Render setting is outside its supported range.")}}
  static func color(_ p:Pixel)throws {try range([p.r,p.g,p.b,p.a],0...1)}
}
