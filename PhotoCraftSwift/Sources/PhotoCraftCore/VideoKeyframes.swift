import Foundation

public enum VideoProperty:String,Codable,CaseIterable,Sendable {
  case position,opacity,transform,style,visibility,content
  public var title:String {rawValue.prefix(1).uppercased()+rawValue.dropFirst()}
  public var isGeometry:Bool {self == .position || self == .transform}
}
public enum KeyframeInterpolation:String,Codable,CaseIterable,Sendable {case linear,hold}
public struct VideoGeometryValue:Codable,Equatable,Sendable {
  public var x:Int
  public var y:Int
  public var affine:Transform2D
  public init(_ layer:Layer){x=layer.x;y=layer.y;affine=layer.affine ?? .identity}
  public var matrix:Transform2D {.translation(Double(x),Double(y))*affine}
  public func validate()throws {guard (-1_000_000...1_000_000).contains(x),(-1_000_000...1_000_000).contains(y) else{throw CraftError.invalid("Invalid keyframe position.")};try affine.validated()}
}
public struct VideoKeyframe:Codable,Equatable,Identifiable,Sendable {
  public var id=UUID()
  public var property:VideoProperty
  public var time:Double
  public var interpolation:KeyframeInterpolation
  public var geometry:VideoGeometryValue?
  public var opacity:Float?
  public var style:LayerStyle?
  public var content:AnimationLayerPayload?
  public var visibility:Bool?
  /// Converted frame composition changes placement without baking shared content.
  public var frameComposition:Bool?
  public init(property:VideoProperty,time:Double,layer:Layer,interpolation:KeyframeInterpolation = .linear){
    self.property=property;self.time=time;self.interpolation=(property == .visibility || property == .content) ? .hold:interpolation
    switch property {case .content:content=AnimationLayerPayload(layer);case .position,.transform:geometry=VideoGeometryValue(layer);case .opacity:opacity=layer.opacity;case .style:style=layer.style;case .visibility:visibility=layer.visible}
  }
  public var metadataBytes:Int {256+(style?.estimatedBytes ?? 0)+(content?.metadataBytes ?? 0)}
  public var estimatedBytes:Int {metadataBytes+(content?.rasterBytes ?? 0)}
  public func validate(in document:CraftDocument)throws {
    guard time.isFinite,(document.videoTimeline?.trimmedToWorkArea == true ? -86_400...86_400 : 0...86_400).contains(time) else{throw CraftError.invalid("Keyframe time must be within one day.")}
    guard property == .visibility || visibility == nil else{throw CraftError.invalid("Unexpected visibility key value.")}
    guard property == .content || content==nil else{throw CraftError.invalid("Unexpected sampled layer content.")}
    switch property {
    case .content:guard content != nil,geometry==nil,opacity==nil,style==nil,visibility==nil,interpolation == .hold else{throw CraftError.invalid("Content keys require a payload and Hold interpolation.")}
    case .visibility:guard visibility != nil,geometry==nil,opacity==nil,style==nil,interpolation == .hold else{throw CraftError.invalid("Visibility keys require a Boolean and Hold interpolation.")}
    case .position,.transform:guard let geometry,opacity==nil,style==nil else{throw CraftError.invalid("Invalid geometry keyframe.")};try geometry.validate()
    case .opacity:guard geometry==nil,style==nil,let opacity,opacity.isFinite,(0...1).contains(opacity) else{throw CraftError.invalid("Invalid opacity keyframe.")}
    case .style:guard geometry==nil,opacity==nil else{throw CraftError.invalid("Invalid style keyframe.")};try style?.validate(in:document)
    }
  }
  public func matches(_ layer:Layer)->Bool {
    switch property {case .content:return content==AnimationLayerPayload(layer);case .position,.transform:return geometry==VideoGeometryValue(layer);case .opacity:return opacity==layer.opacity;case .style:return style==layer.style;case .visibility:return visibility==layer.visible}
  }
  public static func evaluate(_ keys:[Self],property:VideoProperty,time:Double)throws->Self? {
    let track=keys.filter{$0.property==property}.sorted{$0.time<$1.time}
    guard var first=track.first else{return nil}
    if time<=first.time{return first}
    guard let next=track.firstIndex(where:{$0.time>time}) else{return track.last}
    first=track[next-1];let last=track[next]
    guard first.interpolation == .linear,time-first.time>1e-9 else{return first}
    let t=(time-first.time)/(last.time-first.time)
    switch property {
    case .visibility,.content:break
    case .opacity:first.opacity=first.opacity!+(last.opacity!-first.opacity!)*Float(t)
    case .position:
      var value=first.geometry!,end=last.geometry!
      let x=Double(value.x)+value.affine.tx,y=Double(value.y)+value.affine.ty
      let tx=x+(Double(end.x)+end.affine.tx-x)*t,ty=y+(Double(end.y)+end.affine.ty-y)*t
      value.x=Int(floor(tx));value.y=Int(floor(ty));value.affine.tx=tx-Double(value.x);value.affine.ty=ty-Double(value.y)
      // Position does not rotate/scale; use Transform for those components.
      first.geometry=value
    case .transform:
      let matrix=try interpolateTransform(first.geometry!.matrix,last.geometry!.matrix,t)
      var value=first.geometry!;value.x=Int(floor(matrix.tx));value.y=Int(floor(matrix.ty));value.affine = .translation(-Double(value.x),-Double(value.y))*matrix;first.geometry=value
    case .style:first.style=interpolateStyle(first.style,last.style,t)
    }
    return first
  }
  private static func interpolateTransform(_ a:Transform2D,_ b:Transform2D,_ t:Double)throws->Transform2D {
    func parts(_ m:Transform2D)->(Double,Double,Double,Double){let sx=hypot(m.a,m.b),sy=(m.a*m.d-m.b*m.c)/sx;return (atan2(m.b,m.a),sx,sy,(m.a*m.c+m.b*m.d)/(sx*sy))}
    let p=parts(a),q=parts(b)
    // Reflection changes have no nonsingular continuous affine path.
    guard p.2*q.2>0 else{return a}
    func mix(_ x:Double,_ y:Double)->Double{x+(y-x)*t}
    var angle=q.0-p.0;while angle > .pi{angle-=2 * .pi};while angle < -.pi{angle+=2 * .pi}
    let rotation=p.0+angle*t,sx=mix(p.1,q.1),sy=mix(p.2,q.2),shear=mix(p.3,q.3),c=cos(rotation),s=sin(rotation)
    let result=Transform2D(a:c*sx,b:s*sx,c:(c*shear-s)*sy,d:(s*shear+c)*sy,tx:mix(a.tx,b.tx),ty:mix(a.ty,b.ty));try result.validated();return result
  }
  private static func interpolateStyle(_ start:LayerStyle?,_ end:LayerStyle?,_ t:Double)->LayerStyle? {
    guard start != nil || end != nil else{return nil}
    guard start?.restrictedChannels == end?.restrictedChannels else{return start}
    func faded(_ style:LayerStyle)->LayerStyle{var s=style;for i in s.effects.indices{s.effects[i].opacity=0};s.fillOpacity=1;return s}
    var a=start ?? faded(end!),b=end ?? faded(start!)
    if !a.enabled{a=faded(a);a.enabled=true};if !b.enabled{b=faded(b);b.enabled=true}
    // Different effect topology and categorical/gradient/pattern choices hold
    // until the next key. Numeric controls/colors of matching effects interpolate.
    guard a.effects.map(\.kind)==b.effects.map(\.kind),a.effects.map(\.advanced)==b.effects.map(\.advanced),a.referenceOffset==b.referenceOffset,a.sourcePSDData==b.sourcePSDData,a.restrictedChannels==b.restrictedChannels else{return start}
    func mix(_ x:Double,_ y:Double)->Double{x+(y-x)*t}
    func f(_ x:Float,_ y:Float)->Float{x+(y-x)*Float(t)}
    func color(_ x:Pixel,_ y:Pixel)->Pixel{Pixel(f(x.r,y.r),f(x.g,y.g),f(x.b,y.b),f(x.a,y.a))}
    a.fillOpacity=f(a.fillOpacity,b.fillOpacity);a.scale=mix(a.scale,b.scale);a.lightAngle=mix(a.lightAngle,b.lightAngle);a.lightAltitude=mix(a.lightAltitude,b.lightAltitude)
    for i in a.effects.indices {
      var x=a.effects[i];let y=b.effects[i]
      x.opacity=f(x.enabled ? x.opacity:0,y.enabled ? y.opacity:0);x.enabled=true;x.color=color(x.color,y.color)
      x.size=mix(x.size,y.size);x.distance=mix(x.distance,y.distance);x.angle=mix(x.angle,y.angle);x.spread=mix(x.spread,y.spread);x.depth=mix(x.depth,y.depth);x.soften=mix(x.soften,y.soften)
      x.highlightColor=color(x.highlightColor,y.highlightColor);x.shadowColor=color(x.shadowColor,y.shadowColor);x.highlightOpacity=f(x.highlightOpacity,y.highlightOpacity);x.shadowOpacity=f(x.shadowOpacity,y.shadowOpacity);a.effects[i]=x
    }
    return a
  }
}
public enum VideoKeyframeCommand:Sendable {
  case enable(UUID,VideoProperty),disable(UUID,VideoProperty),set(UUID,VideoProperty,Double)
  case delete(UUID,UUID),move(UUID,UUID,Double),interpolation(UUID,UUID,KeyframeInterpolation)
  public var layerID:UUID {switch self{case .enable(let id,_),.disable(let id,_),.set(let id,_,_),.delete(let id,_),.move(let id,_,_),.interpolation(let id,_,_):id}}
  public func apply(to document:inout CraftDocument)throws {
    guard var timeline=document.videoTimeline,let i=document.layers.firstIndex(where:{$0.id==layerID}),!document.isLocked(layerID) else{throw CraftError.invalid("Choose an unlocked layer in a video Timeline.")}
    var layer=document.layers[i],keys=layer.videoKeyframes ?? []
    func check(_ property:VideoProperty)throws {
      if property == .content,layer.video != nil {throw CraftError.unsupported("Content keys require an ordinary layer; movie clips retain their own source frames.")}
      let converted=keys.contains{$0.property==property && $0.frameComposition == true}
      if case .adjustment = layer.content,property != .opacity,property != .visibility,!converted {throw CraftError.unsupported("Adjustment layers currently support opacity keyframes.")}
      if property.isGeometry {
        guard !document.isPositionLocked(layerID),(converted || (!layer.isGroup && layer.smartFilters==nil && layer.warp==nil)) else{throw CraftError.unsupported("Geometry keyframes require an unlocked individual layer without Smart Filters or Warp.")}
      }
    }
    switch self {
    case .enable(_,let property):
      try check(property);guard !keys.contains(where:{$0.property==property}) else{return}
      if property.isGeometry {keys.removeAll{$0.property.isGeometry}}
      keys.append(VideoKeyframe(property:property,time:timeline.seconds,layer:layer))
    case .disable(_,let property):try check(property);keys.removeAll{$0.property==property}
    case .set(_,let property,let time):
      try check(property);guard !property.isGeometry || !keys.contains(where:{$0.property.isGeometry && $0.property != property}) else{throw CraftError.invalid("Choose either Position or Transform animation for this layer.")}
      var key=VideoKeyframe(property:property,time:time,layer:layer)
      if let evaluated=try VideoKeyframe.evaluate(keys,property:property,time:time),evaluated.frameComposition == true {key.frameComposition=true;key.interpolation=evaluated.interpolation}
      try key.validate(in:document)
      if let j=keys.firstIndex(where:{$0.property==property && abs($0.time-time)<1e-9}){key.id=keys[j].id;key.interpolation=keys[j].interpolation;keys[j]=key}else{keys.append(key)}
    case .delete(_,let id):guard let j=keys.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("Keyframe no longer exists.")};try check(keys[j].property);keys.remove(at:j)
    case .move(_,let id,let time):
      guard let j=keys.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("Keyframe no longer exists.")};try check(keys[j].property)
      guard !keys.contains(where:{$0.id != id && $0.property==keys[j].property && abs($0.time-time)<1e-9}) else{throw CraftError.invalid("A keyframe already exists at that time.")};keys[j].time=time;try keys[j].validate(in:document)
    case .interpolation(_,let id,let value):guard let j=keys.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("Keyframe no longer exists.")};try check(keys[j].property);guard (keys[j].property != .visibility && keys[j].property != .content) || value == .hold else{throw CraftError.invalid("Visibility and Content use Hold interpolation.")};keys[j].interpolation=value
    }
    keys.sort{$0.time == $1.time ? $0.property.rawValue<$1.property.rawValue:$0.time<$1.time}
    layer.videoKeyframes=keys.isEmpty ? nil:keys;document.layers[i]=layer
    if let last=keys.map(\.time).max(){timeline.durationFrames=max(timeline.durationFrames,Int(ceil(last*timeline.frameRate-1e-9))+1)}
    document.videoTimeline=timeline;try document.selectVideoFrame(timeline.currentFrame)
  }
}
extension Layer {
  public var hasGeometryKeyframes:Bool {videoKeyframes?.contains{$0.property.isGeometry} == true}
  public var keyframeBytes:Int {videoKeyframes?.reduce(0){$0+$1.estimatedBytes} ?? 0}
}
extension CraftDocument {
  func validateVideoKeyframes()throws {
    let all=layers.flatMap{$0.videoKeyframes ?? []}
    guard all.count<=65_536,all.reduce(0,{$0+$1.metadataBytes})<=64*1024*1024 else{throw CraftError.invalid("Timeline keyframes exceed their metadata budget.")}
    guard videoTimeline != nil || all.isEmpty else{throw CraftError.invalid("Keyframes require a video Timeline.")}
    if let timeline=videoTimeline,timeline.trimmedToWorkArea != true {guard all.allSatisfy({$0.time<Double(timeline.durationFrames)/timeline.frameRate}) else{throw CraftError.invalid("Keyframes must be inside the video Timeline.")}}
    for layer in layers {
      guard let keys=layer.videoKeyframes else{continue}
      guard !keys.isEmpty,keys.count<=4096,Set(keys.map(\.id)).count==keys.count else{throw CraftError.invalid("Invalid layer keyframes.")}
      for key in keys{try key.validate(in:self);try key.content?.validate(layer:layer,in:self)}
      let geometry=Set(keys.filter{$0.property.isGeometry}.map(\.property));guard geometry.count<=1 else{throw CraftError.invalid("Position and Transform tracks cannot both be enabled.")}
      if case .adjustment = layer.content,keys.contains(where:{$0.property != .opacity && $0.property != .visibility && $0.frameComposition != true}) {throw CraftError.unsupported("Adjustment layers currently support opacity keyframes.")}
      if keys.contains(where:{$0.property.isGeometry && $0.frameComposition != true}) {guard !layer.isGroup,layer.smartFilters==nil,layer.warp==nil else{throw CraftError.unsupported("Geometry animation for groups, Smart Filters and Warp remains unsupported.")}}
      for property in VideoProperty.allCases {
        let track=keys.filter{$0.property==property}.sorted{$0.time<$1.time}
        guard zip(track,track.dropFirst()).allSatisfy({$1.time-$0.time>=1e-9}) else{throw CraftError.invalid("Duplicate keyframe time.")}
        if let expected=try VideoKeyframe.evaluate(keys,property:property,time:videoTimeline!.seconds),!expected.matches(layer){throw CraftError.invalid("Layer does not match its evaluated video keyframes.")}
      }
    }
  }
  mutating func evaluateVideoKeyframes(at time:Double)throws {
    for i in layers.indices {
      let keys=layers[i].videoKeyframes ?? []
      for property in VideoProperty.allCases {
        guard let value=try VideoKeyframe.evaluate(keys,property:property,time:time) else{continue}
        switch property {
        case .position,.transform:
          let target=value.geometry!
          if value.frameComposition == true {
            layers[i].x=target.x;layers[i].y=target.y;layers[i].affine=target.affine == .identity ? nil:target.affine
          }else if !value.matches(layers[i]) {
            let delta=target.matrix * (try layers[i].coordinateTransform.inverted())
            var layer=try DocumentGeometry.transformLayer(layers[i],by:delta,in:self)
            layer.x=target.x;layer.y=target.y;layer.affine=target.affine == .identity ? nil:target.affine;layers[i]=layer
          }
        case .content:value.content!.apply(to:&layers[i])
        case .visibility:layers[i].visible=value.visibility!
        case .opacity:layers[i].opacity=value.opacity!
        case .style:layers[i].style=value.style
        }
      }
    }
  }
  mutating func captureVideoKeyframeChanges()throws {
    guard let timeline=videoTimeline else{return}
    for i in layers.indices {
      guard var keys=layers[i].videoKeyframes else{continue}
      for property in VideoProperty.allCases {
        guard let expected=try VideoKeyframe.evaluate(keys,property:property,time:timeline.seconds),!expected.matches(layers[i]) else{continue}
        var key=VideoKeyframe(property:property,time:timeline.seconds,layer:layers[i]);key.frameComposition=expected.frameComposition;if expected.frameComposition == true {key.interpolation=expected.interpolation}
        if let j=keys.firstIndex(where:{$0.property==property && abs($0.time-timeline.seconds)<1e-9}){key.id=keys[j].id;key.interpolation=keys[j].interpolation;keys[j]=key}else{keys.append(key)}
      }
      keys.sort{$0.time == $1.time ? $0.property.rawValue<$1.property.rawValue:$0.time<$1.time};layers[i].videoKeyframes=keys
    }
  }
}
