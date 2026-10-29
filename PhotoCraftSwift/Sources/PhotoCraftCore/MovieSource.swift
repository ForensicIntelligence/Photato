import Foundation

/// Exact media presentation time, independent of AVFoundation in the document engine.
public struct MovieTime: Codable, Equatable, Sendable {
  public var value: Int64
  public var timescale: Int32
  public init(value: Int64, timescale: Int32) { self.value=value;self.timescale=timescale }
  public var seconds: Double { Double(value)/Double(timescale) }
}
/// Retains the complete original container, including audio. Edited frame tiles
/// remain separate. Native archives/history store the original bytes once by hash.
public struct MovieSource: Codable, Equatable, Sendable {
  public static let maximumBytes = 64*1024*1024
  public var data: Data
  public var presentationTimes: [MovieTime]
  public var endTime: MovieTime
  public var originalFrameRate: Double
  public var audioTracks: Int
  public init(data:Data,presentationTimes:[MovieTime],endTime:MovieTime,originalFrameRate:Double,audioTracks:Int) {
    self.data=data;self.presentationTimes=presentationTimes;self.endTime=endTime;self.originalFrameRate=originalFrameRate;self.audioTracks=audioTracks
  }
  public func time(_ frame:Int) -> Double { frame == presentationTimes.count ? endTime.seconds : presentationTimes[frame].seconds }
  public func validate(frameCount:Int) throws {
    guard !data.isEmpty,data.count<=Self.maximumBytes,presentationTimes.count==frameCount,(1...VideoClip.maximumFrames).contains(frameCount),originalFrameRate.isFinite,(1...240).contains(originalFrameRate),(0...64).contains(audioTracks) else {throw CraftError.invalid("Invalid retained movie source.")}
    let times=presentationTimes+[endTime]
    guard times.allSatisfy({$0.timescale>0 && $0.seconds.isFinite && (0...86_400).contains($0.seconds)}),zip(times,times.dropFirst()).allSatisfy({$0.seconds<$1.seconds}) else {throw CraftError.invalid("Movie presentation times must increase within one day.")}
  }
  private enum CodingKeys:CodingKey {case data,sourceBlob,presentationTimes,endTime,originalFrameRate,audioTracks}
  public init(from decoder:Decoder) throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    presentationTimes=try c.decode([MovieTime].self,forKey:.presentationTimes);endTime=try c.decode(MovieTime.self,forKey:.endTime)
    originalFrameRate=try c.decode(Double.self,forKey:.originalFrameRate);audioTracks=try c.decode(Int.self,forKey:.audioTracks)
    if c.contains(.sourceBlob) {
      guard !c.contains(.data),let context=decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding else {throw CraftError.invalid("Movie source blob has no archive context.")}
      data=try context.bytes(c.decode(String.self,forKey:.sourceBlob),maximumBytes:Self.maximumBytes)
    } else {data=try c.decode(Data.self,forKey:.data)}
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?.reserve(tiles:(data.count+TileArchive.byteCount-1)/TileArchive.byteCount)
    try validate(frameCount:presentationTimes.count)
  }
  public func encode(to encoder:Encoder) throws {
    var c=encoder.container(keyedBy:CodingKeys.self)
    try c.encode(presentationTimes,forKey:.presentationTimes);try c.encode(endTime,forKey:.endTime);try c.encode(originalFrameRate,forKey:.originalFrameRate);try c.encode(audioTracks,forKey:.audioTracks)
    if let context=encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {try c.encode(context.storeBytes(data),forKey:.sourceBlob)} else {try c.encode(data,forKey:.data)}
  }
}
