import Foundation

/// Additional editable controls from PhotoCraft doc/effects.rs (MIT OR Apache-2.0).
/// Optional attachment preserves the old native style representation and renderer.
public struct EffectContour:Codable,Equatable,Sendable {
  public var name:String
  public var points:[[Float]]
  public init(name:String="Linear",points:[[Float]]=[]){self.name=name;self.points=points}
  public var isLinear:Bool {points.isEmpty}
  public func validate()throws {
    guard name.utf8.count<=2048,points.count<=256,points.allSatisfy({$0.count==2 && $0.allSatisfy({$0.isFinite && (0...1).contains($0)})}) else {throw CraftError.invalid("Invalid effect contour.")}
  }
  public func table()throws->[Float]? {try validate();return points.isEmpty ? nil:SourceAdjustmentTransfer.curve(points)}
}
public struct EffectGradientStop:Codable,Equatable,Sendable {
  public var location:Float
  public var color:Pixel
  public init(_ location:Float,_ color:Pixel){self.location=location;self.color=color}
}
/// Color alpha and transparency stops are retained separately. The source effect
/// renderer uses opaque stop colors and the separate transparency curve.
public struct EffectGradient:Codable,Equatable,Sendable {
  public var stops:[EffectGradientStop]
  public var opacityStops:[[Float]]
  public var placement:GradientPlacement
  public var aligned:Bool
  public var dither:Bool
  public init(stops:[EffectGradientStop]=[.init(0,.black),.init(1,.white)],opacityStops:[[Float]]=[],placement:GradientPlacement = .init(),aligned:Bool=true,dither:Bool=false){self.stops=stops;self.opacityStops=opacityStops;self.placement=placement;self.aligned=aligned;self.dither=dither}
  public func validate()throws {
    guard placement.angle.isFinite,(-360...360).contains(placement.angle),placement.scale.isFinite,(0...100).contains(placement.scale),placement.offsetX.isFinite,placement.offsetY.isFinite,abs(placement.offsetX)<=100,abs(placement.offsetY)<=100 else {throw CraftError.invalid("Invalid effect gradient geometry.")}
    func color(_ p:Pixel)->Bool {p.isFinite && [p.r,p.g,p.b,p.a].allSatisfy({(0...1).contains($0)})}
    guard stops.count<=4096,opacityStops.count<=4096,
      stops.allSatisfy({$0.location.isFinite && (0...1).contains($0.location) && color($0.color)}),
      opacityStops.allSatisfy({$0.count==2 && $0.allSatisfy({$0.isFinite && (0...1).contains($0)})}),
      zip(stops,stops.dropFirst()).allSatisfy({$0.location<=$1.location}),
      zip(opacityStops,opacityStops.dropFirst()).allSatisfy({$0[0]<=$1[0]}) else {throw CraftError.invalid("Invalid effect gradient stops.")}
  }
}
/// Bound native identity and inert original hints. Missing source artwork never
/// grants file access or silently substitutes another pattern.
public struct EffectPattern:Codable,Equatable,Sendable {
  public var patternID:String?
  public var sourceName:String?
  public var sourceID:String?
  /// Original fractional scale:1 =100%; no percent round trip on import.
  public var scale:Float
  public var angle:Float
  public var linked:Bool
  public var phase:PathPoint
  public init(patternID:String?=nil,sourceName:String?=nil,sourceID:String?=nil,scale:Float=1,angle:Float=0,linked:Bool=true,phase:PathPoint = .init(0,0)) {
    self.patternID=patternID;self.sourceName=sourceName;self.sourceID=sourceID;self.scale=scale;self.angle=angle;self.linked=linked;self.phase=phase
  }
  public func validate(in document:CraftDocument?=nil)throws {
    guard scale.isFinite,(0...100).contains(scale),angle.isFinite,(-360...360).contains(angle),phase.x.isFinite,phase.y.isFinite,abs(phase.x)<=1e9,abs(phase.y)<=1e9,
      (patternID?.utf8.count ?? 0)<=1024,(sourceName?.utf8.count ?? 0)<=4096,(sourceID?.utf8.count ?? 0)<=4096,
      patternID.map({!$0.isEmpty}) != false else {throw CraftError.invalid("Invalid effect pattern reference or placement.")}
    if let document,let id=patternID,document.pattern(id)==nil {throw CraftError.invalid("The bound effect pattern is not in the document.")}
  }
}
public struct EffectPaint:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {case color,gradient,pattern}
  public var kind:Kind
  public var gradient:EffectGradient?
  public var pattern:EffectPattern?
  public init(_ kind:Kind = .color,gradient:EffectGradient?=nil,pattern:EffectPattern?=nil){self.kind=kind;self.gradient=gradient;self.pattern=pattern}
  public func validate(in document:CraftDocument?=nil)throws {
    guard (kind == .gradient)==(gradient != nil),(kind == .pattern)==(pattern != nil) else {throw CraftError.invalid("Effect paint data does not match its kind.")}
    try gradient?.validate();try pattern?.validate(in:document)
  }
}
public struct EffectBevelContour:Codable,Equatable,Sendable {
  public var contour:EffectContour
  public var range:Float
  public var antiAlias:Bool
  public init(contour:EffectContour = .init(),range:Float=0.5,antiAlias:Bool=false){self.contour=contour;self.range=range;self.antiAlias=antiAlias}
  public func validate()throws {try contour.validate();guard range.isFinite,(0...1).contains(range) else {throw CraftError.invalid("Invalid bevel contour range.")}}
}
public struct EffectBevelTexture:Codable,Equatable,Sendable {
  public var pattern:EffectPattern
  public var depth:Float
  public var inverted:Bool
  public init(pattern:EffectPattern = .init(),depth:Float=1,inverted:Bool=false){self.pattern=pattern;self.depth=depth;self.inverted=inverted}
  public func validate(in document:CraftDocument?=nil)throws {try pattern.validate(in:document);guard depth.isFinite,(-10...10).contains(depth) else {throw CraftError.invalid("Invalid bevel texture depth.")}}
}
public struct LayerEffectAdvanced:Codable,Equatable,Sendable {
  public enum GlowTechnique:String,Codable,CaseIterable,Sendable {case softer,precise}
  public enum GlowSource:String,Codable,CaseIterable,Sendable {case center,edge}
  public enum BevelStyle:String,Codable,CaseIterable,Sendable {case outerBevel,innerBevel,emboss,pillowEmboss,strokeEmboss}
  public enum BevelTechnique:String,Codable,CaseIterable,Sendable {case smooth,chiselHard,chiselSoft}
  public var contour=EffectContour()
  public var antiAlias=false
  public var noise:Float=0
  public var knocksOut=true
  public var glowTechnique:GlowTechnique = .softer
  public var glowSource:GlowSource = .edge
  public var range:Float=1
  public var jitter:Float=0
  public var satinInverted=false
  public var bevelStyle:BevelStyle = .innerBevel
  public var bevelTechnique:BevelTechnique = .smooth
  public var directionUp=true
  public var altitude:Float=30
  public var glossContour=EffectContour()
  public var highlightBlendMode:BlendMode = .screen
  public var shadowBlendMode:BlendMode = .multiply
  public var highlightEnabled=true
  public var shadowEnabled=true
  public var bevelContour:EffectBevelContour?
  public var texture:EffectBevelTexture?
  public var paint:EffectPaint?
  public init(){}
  public var estimatedBytes:Int {512+contour.points.count*8+glossContour.points.count*8+(bevelContour?.contour.points.count ?? 0)*8+(paint?.gradient?.stops.count ?? 0)*24+(paint?.gradient?.opacityStops.count ?? 0)*8}
  public func validate(kind:LayerEffect.Kind,in document:CraftDocument?=nil)throws {
    try contour.validate();try glossContour.validate();try bevelContour?.validate();try texture?.validate(in:document);try paint?.validate(in:document)
    guard noise.isFinite,(0...1).contains(noise),range.isFinite,(0...1).contains(range),jitter.isFinite,(0...1).contains(jitter),altitude.isFinite,(0...90).contains(altitude),
      (kind == .bevelEmboss || (bevelContour==nil && texture==nil)),
      (paint==nil || [.innerGlow,.outerGlow,.stroke,.gradientOverlay,.patternOverlay].contains(kind)),
      (kind != .gradientOverlay || paint?.kind == .gradient),
      (kind != .patternOverlay || paint?.kind == .pattern) else {throw CraftError.invalid("Invalid advanced layer-effect controls.")}
  }
}
public struct GlobalLight:Codable,Equatable,Sendable {
  public var angle:Double
  public var altitude:Double
  public init(angle:Double=120,altitude:Double=30){self.angle=angle;self.altitude=altitude}
  public func validate()throws {guard angle.isFinite,(-360...360).contains(angle),altitude.isFinite,(0...90).contains(altitude) else {throw CraftError.invalid("Invalid shared light angle or altitude.")}}
}
extension LayerStyle {
  public var requiresAdvancedArchive:Bool {referenceOffset != nil || sourcePSDData != nil || effects.contains{$0.advanced != nil}}
}
extension CraftDocument {
  public var requiresAdvancedStyleArchive:Bool {
    func layer(_ l:Layer)->Bool{l.style?.requiresAdvancedArchive==true || l.videoKeyframes?.contains(where:{$0.style?.requiresAdvancedArchive==true})==true}
    if globalLight != nil || layers.contains(where:layer) || animation?.frames.contains(where:{$0.layers.contains(where:{$0.style?.requiresAdvancedArchive==true})})==true {return true}
    var retained=videoTimeline?.retainedFrameSources ?? [];if let source=animation?.retainedVideoSource{retained.append(source)}
    while let source=retained.popLast(){if source.layers.contains(where:layer){return true};retained.append(contentsOf:source.timeline.retainedFrameSources ?? [])};return false
  }
}
