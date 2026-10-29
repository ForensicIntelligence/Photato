import Foundation

public struct TimelineWorkArea: Codable, Equatable, Sendable {
  public var startFrame: Int
  public var endFrame: Int
  public init(startFrame:Int,endFrame:Int){self.startFrame=startFrame;self.endFrame=endFrame}
  public var count:Int{endFrame-startFrame}
  public func validate(durationFrames:Int)throws {
    guard startFrame>=0,endFrame>startFrame,endFrame<=durationFrames else{throw CraftError.invalid("Work area must contain at least one frame inside the Timeline; its end is exclusive.")}
  }
  public func clamped(to duration:Int)->Self {
    let start=min(max(0,startFrame),max(0,duration-1))
    return .init(startFrame:start,endFrame:min(duration,max(start+1,endFrame)))
  }
}
public struct OnionSkinSettings:Codable,Equatable,Sendable {
  public var enabled:Bool
  public var framesBefore:Int
  public var framesAfter:Int
  public var spacing:Int
  public var minimumOpacity:Float
  public var maximumOpacity:Float
  public var blendMode:BlendMode
  public init(enabled:Bool=false,framesBefore:Int=1,framesAfter:Int=1,spacing:Int=1,
    minimumOpacity:Float=0.25,maximumOpacity:Float=0.5,blendMode:BlendMode = .multiply) {
    self.enabled=enabled;self.framesBefore=framesBefore;self.framesAfter=framesAfter;self.spacing=spacing
    self.minimumOpacity=minimumOpacity;self.maximumOpacity=maximumOpacity;self.blendMode=blendMode
  }
  public func validate()throws {
    guard (0...10).contains(framesBefore),(0...10).contains(framesAfter),(1...100).contains(spacing),
      minimumOpacity.isFinite,maximumOpacity.isFinite,(0...1).contains(minimumOpacity),
      (minimumOpacity...1).contains(maximumOpacity) else{throw CraftError.invalid("Onion skins require 0–10 frames each side, spacing1–100 and ordered opacities from0 to1.")}
  }
  public func samples(currentFrame:Int,durationFrames:Int)throws->[(frame:Int,opacity:Float)] {
    try validate();guard (0..<durationFrames).contains(currentFrame) else{throw CraftError.invalid("Invalid onion-skin playhead.")}
    guard enabled else{return []}
    var result:[(frame:Int,opacity:Float)]=[]
    for distance in stride(from:max(framesBefore,framesAfter),through:1,by:-1) {
      for (direction,count) in [(-1,framesBefore),(1,framesAfter)] where distance<=count {
        let frame=currentFrame+direction*distance*spacing
        guard (0..<durationFrames).contains(frame) else{continue}
        let fraction=count<=1 ? Float(0):Float(distance-1)/Float(count-1)
        result.append((frame,maximumOpacity+(minimumOpacity-maximumOpacity)*fraction))
      }
    }
    return result
  }
}
public enum TimelineWorkspaceCommand:Sendable {
  case trimToWorkArea
  case workArea(TimelineWorkArea?)
  case onionSkin(OnionSkinSettings?)
  public var label:String{switch self{case .trimToWorkArea:"Trim Document Duration To Work Area";case .workArea:"Set Work Area";case .onionSkin:"Onion Skin Settings"}}
  public func apply(to document:inout CraftDocument)throws {
    if case .trimToWorkArea=self {try document.trimTimelineToWorkArea();return}
    guard var timeline=document.videoTimeline else{throw CraftError.invalid("Create a video Timeline first.")}
    switch self {
    case .trimToWorkArea:break
    case .workArea(let area):try area?.validate(durationFrames:timeline.durationFrames);timeline.workArea=area
    case .onionSkin(let settings):try settings?.validate();timeline.onionSkin=settings
    }
    document.videoTimeline=timeline
  }
}
extension VideoTimeline {
  public var effectiveWorkArea:TimelineWorkArea{workArea ?? .init(startFrame:0,endFrame:durationFrames)}
  public var playbackStartFrame:Int {
    let area=effectiveWorkArea
    return (area.startFrame..<area.endFrame).contains(currentFrame) ? currentFrame:area.startFrame
  }
}
