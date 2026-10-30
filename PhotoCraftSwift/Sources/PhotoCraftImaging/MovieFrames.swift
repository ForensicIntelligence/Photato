import AVFoundation
import Foundation
import PhotoCraftCore

public struct MovieFrameImportOptions: Codable,Equatable,Sendable {
  public var selectedRange = false
  public var start = 0.0
  public var end = 1.0
  public var every = 1
  public var makeAnimation = true
  public init() {}
  public func validate() throws {
    guard start.isFinite,end.isFinite,start >= 0,end > start,end <= 86_400,(1...10_000).contains(every) else {
      throw CraftError.invalid("Choose an increasing movie range within one day and a frame interval from1 to10,000.")
    }
  }
}
public struct MovieFrameInfo: Sendable {
  public let width: Int,height: Int
  public let duration: Double,frameRate: Double
}
public enum MovieFrames {
  public static func info(_ url: URL) throws -> MovieFrameInfo {
    let asset = AVURLAsset(url:url,options:[AVURLAssetPreferPreciseDurationAndTimingKey:true,AVURLAssetReferenceRestrictionsKey:UInt(0xffff)])
    guard !asset.hasProtectedContent,asset.tracks(withMediaType:.video).count == 1,let track = asset.tracks(withMediaType:.video).first else {throw CraftError.unsupported("Choose an unprotected movie with one video track.")}
    let size = CGRect(origin:.zero,size:track.naturalSize).applying(track.preferredTransform).standardized.size
    let duration = CMTimeRangeGetEnd(track.timeRange).seconds
    guard size.width.isFinite,size.height.isFinite,size.width >= 1,size.height >= 1,size.width <= Double(Surface.maxDimension),size.height <= Double(Surface.maxDimension),duration.isFinite,duration > 0,duration <= 86_400 else {throw CraftError.invalid("Invalid movie dimensions or duration.")}
    return MovieFrameInfo(width:Int(size.width.rounded()),height:Int(size.height.rounded()),duration:duration,frameRate:Double(track.nominalFrameRate))
  }
  public static func decode(_ data: Data,name: String,options: MovieFrameImportOptions,maximumBytes: Int = 1_073_741_824,maximumPixels: Int = Surface.maximumDensePixels,maximumLayers: Int = 512) throws -> CraftDocument {
    try MovieIO.decode(data,name:name,maximumBytes:maximumBytes,maximumPixels:maximumPixels,frameOptions:options,maximumLayers:maximumLayers)
  }
  static func document(frames: [Surface],times: [MovieTime],end: MovieTime,indices: [Int],name: String,options: MovieFrameImportOptions,maximumBytes: Int) throws -> CraftDocument {
    guard let first = frames.first,frames.count == times.count,frames.count == indices.count else {throw CraftError.invalid("The selected range contains no frames.")}
    var result = try CraftDocument(width:first.width,height:first.height,depth:first.depth,name:name)
    result.layers = frames.enumerated().map {index,pixels in
      var layer = Layer(name:"Layer \(index+1)",content:.raster(pixels));layer.visible = !options.makeAnimation || index == 0;return layer
    }
    result.activeLayerID = options.makeAnimation ? result.layers.first?.id:result.layers.last?.id
    if options.makeAnimation {
      var animation = FrameAnimation(layers:result.layers)
      animation.frames = try frames.indices.map {index in
        try Task.checkCancellation()
        var frame = AnimationFrame(layers:result.layers,delay:(index+1<times.count ? times[index+1].seconds:end.seconds)-times[index].seconds)
        guard frame.delay > 0,frame.delay <= 3600 else {throw CraftError.invalid("Imported frame delays must be greater than zero and at most one hour.")}
        frame.sourceVideoFrame = indices[index]
        for i in frame.layers.indices {frame.layers[i].visible = i == index}
        return frame
      }
      animation.selectedFrameID = animation.frames[0].id;result.animation = animation
    }
    guard result.estimatedBytes <= maximumBytes else {throw CraftError.invalid("Imported layers exceed the decoded-memory budget.")}
    try result.validate();return result
  }
}
