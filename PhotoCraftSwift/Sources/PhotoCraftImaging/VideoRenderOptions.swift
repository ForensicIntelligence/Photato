import AVFoundation
import Foundation
import PhotoCraftCore

public enum VideoRenderCodec: String, CaseIterable, Codable, Sendable {
  case h264, hevc, proRes422, proRes4444, uncompressed
  public var name: String {
    switch self {
    case .h264: "H.264 — MP4"
    case .hevc: "HEVC — MP4"
    case .proRes422: "Apple ProRes 422 — QuickTime"
    case .proRes4444: "Apple ProRes 4444 — QuickTime"
    case .uncompressed: "Uncompressed BGRA — QuickTime"
    }
  }
  public var supportsAlpha: Bool { self == .proRes4444 || self == .uncompressed }
  public var usesBitRate: Bool { self == .h264 || self == .hevc }
  public var fileExtension: String { usesBitRate ? "mp4" : "mov" }
  public var contentType: String { usesBitRate ? "video/mp4" : "video/quicktime" }
  var fileType: AVFileType { usesBitRate ? .mp4 : .mov }
  var avCodec: AVVideoCodecType? {
    switch self {
    case .h264: .h264
    case .hevc: .hevc
    case .proRes422: .proRes422
    case .proRes4444: .proRes4444
    case .uncompressed: nil
    }
  }
}
public struct VideoRenderOptions: Equatable, Sendable {
  public var codec: VideoRenderCodec
  public var width: Int?
  public var height: Int?
  public var frameRate: Double?
  public var firstFrame: Int
  public var lastFrame: Int?
  public var bitRate: Int?
  public var includeAudio: Bool
  public var useWorkArea: Bool
  public var preserveAlpha: Bool
  public init(codec: VideoRenderCodec = .h264, width: Int? = nil, height: Int? = nil,
    frameRate: Double? = nil, firstFrame: Int = 0, lastFrame: Int? = nil,
    bitRate: Int? = nil, includeAudio: Bool = true, preserveAlpha: Bool = false, useWorkArea: Bool = false) {
    self.codec=codec;self.width=width;self.height=height;self.frameRate=frameRate
    self.firstFrame=firstFrame;self.lastFrame=lastFrame;self.bitRate=bitRate
    self.useWorkArea=useWorkArea;self.includeAudio=includeAudio;self.preserveAlpha=preserveAlpha
  }
  public func plan(for document: CraftDocument) throws -> VideoRenderPlan {
    let count = document.animation?.frames.count ?? document.videoTimeline?.durationFrames ?? 0
    let first:Int,last:Int
    if useWorkArea {
      guard let timeline=document.videoTimeline,firstFrame==0,lastFrame==nil else{throw CraftError.invalid("Work-area export requires a video Timeline and no explicit frame range.")}
      first=timeline.effectiveWorkArea.startFrame;last=timeline.effectiveWorkArea.endFrame-1
    }else{first=firstFrame;last=lastFrame ?? count-1}
    let w = width ?? document.width, h = height ?? document.height
    let rate = frameRate ?? document.videoTimeline?.frameRate ?? 30
    guard count > 0, first >= 0, last >= first, last < count,
      (1...8192).contains(w), (1...8192).contains(h), w*h <= 33_554_432,
      rate.isFinite, (1...240).contains(rate), !preserveAlpha || codec.supportsAlpha,
      !codec.usesBitRate || (w % 2 == 0 && h % 2 == 0),
      bitRate == nil || (codec.usesBitRate && (100_000...200_000_000).contains(bitRate!))
    else { throw CraftError.invalid("Choose a valid Timeline range, dimensions, rate and codec options. H.264/HEVC require even dimensions; alpha requires ProRes 4444 or uncompressed QuickTime.") }
    let start: Double, duration: Double
    if let animation = document.animation {
      start = (0..<first).reduce(0) { $0 + animation.playbackDelay(at:$1) }
      duration = (first...last).reduce(0) { $0 + animation.playbackDelay(at:$1) }
    } else {
      start = Double(first)/document.videoTimeline!.frameRate
      duration = Double(last-first+1)/document.videoTimeline!.frameRate
    }
    let numerator: Int32, denominator: Int64
    if let standard = [24_000,30_000,48_000,60_000,120_000,240_000].first(where:{abs(rate-Double($0)/1001)<0.000_001}) {
      numerator=Int32(standard);denominator=1001
    } else {
      var a=Int64((rate*1_000_000).rounded()), b:Int64=1_000_000
      let raw=a;while b != 0 { let r=a%b;a=b;b=r }
      numerator=Int32(raw/a);denominator=1_000_000/a
    }
    let effectiveRate=Double(numerator)/Double(denominator)
    guard start.isFinite, start >= 0, duration.isFinite, duration > 0, duration <= 86_400 else {
      throw CraftError.invalid("Invalid source Timeline interval.")
    }
    let frames=Int(ceil(duration*effectiveRate-1e-9))
    guard (1...100_000).contains(frames) else {
      throw CraftError.invalid("Video output is limited to 100,000 frames and 24 hours.")
    }
    return VideoRenderPlan(width:w,height:h,sourceStart:start,sourceDuration:duration,
      frameCount:frames,rateNumerator:numerator,rateDenominator:denominator)
  }
}
public struct VideoRenderPlan: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let sourceStart: Double
  public let sourceDuration: Double
  public let frameCount: Int
  public let rateNumerator: Int32
  public let rateDenominator: Int64
  public var frameRate: Double { Double(rateNumerator)/Double(rateDenominator) }
  public var duration: Double { Double(frameCount)/frameRate }
  public func timestamp(_ frame: Int) -> CMTime { CMTime(value:Int64(frame)*rateDenominator,timescale:rateNumerator) }
}
