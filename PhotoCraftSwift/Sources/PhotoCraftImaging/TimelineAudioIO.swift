import AVFoundation
import AudioToolbox
import CryptoKit
import Foundation
import PhotoCraftCore

public struct TimelinePCM: Equatable, Sendable {
  public static let sampleRate = 48_000
  public static let channels = 2
  public var samples: [Float]
  public init(samples: [Float]) { self.samples = samples }
  public var frames: Int { samples.count / Self.channels }
  public var duration: Double { Double(frames) / Double(Self.sampleRate) }
  public var bytes: Int { samples.count * MemoryLayout<Float>.size }
  /// IEEE Float32 WAVE; no lossy encoder or external process is involved.
  public func wave() throws -> Data {
    guard samples.count % 2 == 0, bytes <= Int(UInt32.max) - 36,
      samples.allSatisfy(\.isFinite) else { throw CraftError.invalid("Invalid PCM output.") }
    var result = Data()
    func text(_ value: String) { result.append(contentsOf: value.utf8) }
    func word<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian; withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
    }
    text("RIFF"); word(UInt32(bytes + 36)); text("WAVEfmt "); word(UInt32(16))
    word(UInt16(3)); word(UInt16(2)); word(UInt32(Self.sampleRate)); word(UInt32(Self.sampleRate * 8))
    word(UInt16(8)); word(UInt16(32)); text("data"); word(UInt32(bytes))
    for (i,value) in samples.enumerated() { if i % 8192 == 0 { try Task.checkCancellation() }; word(value.bitPattern) }
    return result
  }
}
public enum TimelineAudioIO {
  public static let maximumDecodedBytes = 256 * 1024 * 1024
  public static let mediaTypes = ["audio/wav","audio/x-wav","audio/aiff","audio/x-aiff","audio/mpeg","audio/mp4","audio/x-m4a","audio/aac","audio/x-caf"]
  // AVFoundation selects several audio parsers by suffix. Derive it from the
  // container signature, never a caller-supplied name or path.
  static func containerExtension(_ data: Data) throws -> String {
    let h = Array(data.prefix(12))
    func text(_ start: Int, _ count: Int) -> String {
      guard h.count >= start + count else { return "" }
      return String(decoding:h[start..<start+count],as:UTF8.self)
    }
    if ["RIFF","RF64","BW64"].contains(text(0,4)), text(8,4) == "WAVE" { return "wav" }
    if text(0,4) == "FORM", ["AIFF","AIFC"].contains(text(8,4)) { return "aiff" }
    if text(0,4) == "caff" { return "caf" }
    if text(0,3) == "ID3" { return "mp3" }
    if text(4,4) == "ftyp" { return "mp4" }
    if ["moov","mdat","wide","free"].contains(text(4,4)) { return "mov" }
    if h.count >= 2, h[0] == 255, h[1] & 0xe0 == 0xe0 {
      return h[1] & 0x06 == 0 ? "aac" : "mp3"
    }
    throw CraftError.invalid("Unrecognized audio container.")
  }
  public static func read(_ url: URL, maximumBytes: Int = maximumDecodedBytes) throws -> (TimelineAudioSource, TimelinePCM) {
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    var data = Data()
    while true {
      try Task.checkCancellation()
      guard let next = try file.read(upToCount:min(1_048_576, TimelineAudioSource.maximumBytes + 1 - data.count)), !next.isEmpty else { break }
      data.append(next)
      guard data.count <= TimelineAudioSource.maximumBytes else { throw CraftError.invalid("Audio source exceeds 64 MiB.") }
    }
    return try decode(data, maximumBytes:maximumBytes)
  }
  public static func decode(_ data: Data, maximumBytes: Int = maximumDecodedBytes) throws -> (TimelineAudioSource, TimelinePCM) {
    try Task.checkCancellation()
    guard !data.isEmpty, data.count <= TimelineAudioSource.maximumBytes, maximumBytes >= 8 else { throw CraftError.invalid("Invalid audio source or decode budget.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photato-audio-" + UUID().uuidString, isDirectory:true)
    try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:false, attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:directory) }
    let url = directory.appendingPathComponent("source." + (try containerExtension(data))); try data.write(to:url, options:.atomic)
    let asset = AVURLAsset(url:url, options:[AVURLAssetPreferPreciseDurationAndTimingKey:true, AVURLAssetReferenceRestrictionsKey:UInt(0xffff)])
    let tracks = asset.tracks(withMediaType:.audio)
    guard !asset.hasProtectedContent, !tracks.isEmpty, tracks.count <= 64 else { throw CraftError.unsupported("Choose an unprotected file containing audio.") }
    let output = AVAssetReaderAudioMixOutput(audioTracks:tracks, audioSettings:[
      AVFormatIDKey:kAudioFormatLinearPCM,
      AVNumberOfChannelsKey:2, AVLinearPCMBitDepthKey:32, AVLinearPCMIsFloatKey:true,
      AVLinearPCMIsBigEndianKey:false, AVLinearPCMIsNonInterleaved:false])
    let reader = try AVAssetReader(asset:asset)
    guard reader.canAdd(output) else { throw CraftError.unsupported("Native audio decoding is unavailable for this file.") }
    reader.add(output); guard reader.startReading() else { throw reader.error ?? CraftError.invalid("Audio decode could not start.") }
    defer { reader.cancelReading() }
    var samples = [Float](); let maximumFrames = maximumBytes / 8
    var nativeRate: Double?
    while let buffer = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      guard let description = CMSampleBufferGetFormatDescription(buffer),
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
        format.pointee.mFormatID == kAudioFormatLinearPCM, format.pointee.mChannelsPerFrame == 2,
        format.pointee.mBitsPerChannel == 32, format.pointee.mBytesPerFrame == 8,
        format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
        format.pointee.mFormatFlags & (kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsNonInterleaved) == 0,
        format.pointee.mSampleRate.isFinite, (8_000...384_000).contains(format.pointee.mSampleRate),
        let block = CMSampleBufferGetDataBuffer(buffer)
      else { throw CraftError.unsupported("The audio decoder returned an unsupported PCM layout.") }
      let rate = format.pointee.mSampleRate
      guard nativeRate == nil || abs(nativeRate! - rate) < 0.01 else { throw CraftError.unsupported("Audio sample rate changed within the source.") }
      nativeRate = rate
      let time = CMSampleBufferGetPresentationTimeStamp(buffer), count = CMSampleBufferGetNumSamples(buffer)
      guard time.isNumeric, time.seconds.isFinite, abs(time.seconds) <= 86_400,
        count > 0, count <= maximumFrames, CMBlockBufferGetDataLength(block) == count * 8
      else { throw CraftError.invalid("Invalid decoded audio timing or length.") }
      let first = Int((time.seconds * rate).rounded()), skip = max(0, -first)
      if skip >= count { continue }
      let destination = max(0, first), frames = count - skip
      guard destination <= maximumFrames - frames else { throw CraftError.invalid("Audio exceeds the decoded-memory budget; no partial clip was imported.") }
      var decoded = [Float](repeating:0, count:frames * 2)
      let status = decoded.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset:skip * 8, dataLength:frames * 8, destination:$0.baseAddress!) }
      guard status == kCMBlockBufferNoErr, decoded.allSatisfy(\.isFinite) else { throw CraftError.invalid("Invalid audio sample payload.") }
      let end = (destination + frames) * 2
      if samples.count < end { samples.append(contentsOf:repeatElement(0, count:end - samples.count)) }
      samples.replaceSubrange(destination * 2..<end, with:decoded)
    }
    try Task.checkCancellation()
    guard reader.status == .completed, !samples.isEmpty else { throw reader.error ?? CraftError.invalid("No complete audio was decoded.") }
    // The AVAssetReader rate converter can drop its trailing filter samples.
    // Read the complete native-rate stream, then resample explicitly so the
    // source duration and final samples are retained.
    let rate = nativeRate!, count = samples.count / 2
    let frameCount = Int(ceil(Double(count) * Double(TimelinePCM.sampleRate) / rate - 1e-9))
    guard frameCount > 0, frameCount <= maximumFrames else { throw CraftError.invalid("Resampled audio exceeds its PCM budget.") }
    let pcm: TimelinePCM
    if rate == Double(TimelinePCM.sampleRate) { pcm = TimelinePCM(samples:samples) }
    else {
      var converted = [Float](repeating:0,count:frameCount * 2)
      for frame in 0..<frameCount {
        if frame % 4096 == 0 { try Task.checkCancellation() }
        let position = Double(frame) * rate / Double(TimelinePCM.sampleRate)
        let first = min(count - 1,Int(position)), last = min(count - 1,first + 1), fraction = Float(position - Double(first))
        for channel in 0..<2 { converted[frame * 2 + channel] = samples[first * 2 + channel] * (1 - fraction) + samples[last * 2 + channel] * fraction }
      }
      pcm = TimelinePCM(samples:converted)
    }
    let source = TimelineAudioSource(data:data, duration:pcm.duration, trackCount:tracks.count)
    try source.validate(); return (source,pcm)
  }
}
public enum TimelineAudioMixer {
  public struct Clip: Sendable {
    public let data: Data
    public let start: Double
    public let duration: Double
    public let sourceIn: Double
    public let rate: Double
    public let settings: TimelineAudioSettings
  }
  public static func clips(_ document: CraftDocument) -> [Clip] {
    var result:[Clip] = []
    for layer in document.layers {
      guard let clip = layer.video, let movie = clip.movie, movie.audioTracks > 0 else { continue }
      let settings = clip.audio ?? .init()
      if !settings.muted, settings.volume > 0 {
        result.append(.init(data:movie.data, start:clip.startTime, duration:clip.duration,
          sourceIn:clip.sourceStart / movie.originalFrameRate, rate:clip.frameRate / movie.originalFrameRate, settings:settings))
      }
    }
    for track in document.videoTimeline?.audioTracks ?? [] where !track.muted {
      for clip in track.clips where !clip.settings.muted && clip.settings.volume > 0 {
        result.append(.init(data:clip.source.data, start:clip.startTime, duration:clip.duration,
          sourceIn:clip.sourceIn, rate:clip.effectiveRate, settings:clip.settings))
      }
    }
    return result
  }
  public static func render(_ document: CraftDocument, maximumBytes: Int = TimelineAudioIO.maximumDecodedBytes,
    startTime: Double = 0, duration requestedDuration: Double? = nil) throws -> TimelinePCM? {
    try document.validate(); try Task.checkCancellation()
    guard let timeline = document.videoTimeline else { return nil }
    let clips = clips(document); guard !clips.isEmpty else { return nil }
    let duration = requestedDuration ?? Double(timeline.durationFrames) / timeline.frameRate
    guard startTime.isFinite, startTime >= 0, duration.isFinite, duration > 0, duration <= 86_400 else { throw CraftError.invalid("Invalid audio mix range.") }
    let frames = Int(ceil(duration * Double(TimelinePCM.sampleRate)))
    guard maximumBytes >= 8, frames <= maximumBytes / 8 else { throw CraftError.invalid("Timeline audio mix exceeds its PCM memory budget.") }
    var decoded:[String:TimelinePCM] = [:], sourceBytes = 0
    var output = [Float](repeating:0, count:frames * 2)
    for clip in clips {
      try Task.checkCancellation()
      let begin = max(0,Int(ceil((clip.start - startTime) * Double(TimelinePCM.sampleRate) - 1e-9)))
      let end = min(frames,Int(ceil((clip.start + clip.duration - startTime) * Double(TimelinePCM.sampleRate) - 1e-9)))
      guard begin < end else { continue }

      let key = SHA256.hash(data:clip.data).map { String(format:"%02x",$0) }.joined()
      let pcm:TimelinePCM
      if let existing = decoded[key] { pcm = existing }
      else {
        pcm = try TimelineAudioIO.decode(clip.data, maximumBytes:maximumBytes - sourceBytes).1
        sourceBytes += pcm.bytes; decoded[key] = pcm
      }
      for frame in begin..<end {
        if frame % 4096 == 0 { try Task.checkCancellation() }
        let local = startTime + Double(frame) / Double(TimelinePCM.sampleRate) - clip.start
        let position = (clip.sourceIn + local * clip.rate) * Double(TimelinePCM.sampleRate)
        guard position >= 0, position < Double(pcm.frames) else { continue }
        let first = Int(floor(position)), last = min(pcm.frames - 1,first + 1), fraction = Float(position - Double(first))
        let gain = clip.settings.gain(at:local, duration:clip.duration)
        for channel in 0..<2 {
          output[frame * 2 + channel] += (pcm.samples[first * 2 + channel] * (1 - fraction) + pcm.samples[last * 2 + channel] * fraction) * gain
        }
      }
    }
    for i in output.indices { if i % 8192 == 0 { try Task.checkCancellation() }; output[i] = min(1,max(-1,output[i])) }
    return TimelinePCM(samples:output)
  }
}
