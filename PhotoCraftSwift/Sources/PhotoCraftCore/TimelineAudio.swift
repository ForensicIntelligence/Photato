import Foundation

/// Retained original audio container. PCM decoding belongs to the native media adapter.
public struct TimelineAudioSource: Codable, Equatable, Sendable {
  public static let maximumBytes = 64 * 1024 * 1024
  public var data: Data
  public var duration: Double
  public var trackCount: Int
  public init(data: Data, duration: Double, trackCount: Int = 1) {
    self.data = data; self.duration = duration; self.trackCount = trackCount
  }
  public func validate() throws {
    guard !data.isEmpty, data.count <= Self.maximumBytes, duration.isFinite,
      duration > 0, duration <= 86_400, (1...64).contains(trackCount)
    else { throw CraftError.invalid("Invalid retained audio source.") }
  }
  private enum CodingKeys: CodingKey { case data, sourceBlob, duration, trackCount }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    duration = try c.decode(Double.self, forKey: .duration)
    trackCount = try c.decode(Int.self, forKey: .trackCount)
    if c.contains(.sourceBlob) {
      guard !c.contains(.data), let context = decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding
      else { throw CraftError.invalid("Audio source blob has no archive context.") }
      data = try context.bytes(c.decode(String.self, forKey: .sourceBlob), maximumBytes: Self.maximumBytes)
    } else { data = try c.decode(Data.self, forKey: .data) }
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?.reserve(tiles: (data.count + TileArchive.byteCount - 1) / TileArchive.byteCount)
    try validate()
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(duration, forKey: .duration); try c.encode(trackCount, forKey: .trackCount)
    if let context = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {
      try c.encode(context.storeBytes(data), forKey: .sourceBlob)
    } else { try c.encode(data, forKey: .data) }
  }
}
public struct TimelineAudioSettings: Codable, Equatable, Sendable {
  public var volume: Double
  public var muted: Bool
  public var fadeIn: Double
  public var fadeOut: Double
  public init(volume: Double = 1, muted: Bool = false, fadeIn: Double = 0, fadeOut: Double = 0) {
    self.volume = volume; self.muted = muted; self.fadeIn = fadeIn; self.fadeOut = fadeOut
  }
  public func validate() throws {
    guard volume.isFinite, (0...1).contains(volume), fadeIn.isFinite, fadeOut.isFinite,
      (0...86_400).contains(fadeIn), (0...86_400).contains(fadeOut)
    else { throw CraftError.invalid("Audio volume must be 0–100 percent and fades must be nonnegative seconds.") }
  }
  public func gain(at time: Double, duration: Double) -> Float {
    guard !muted, time >= 0, time < duration else { return 0 }
    let start = fadeIn > 0 ? min(1, time / fadeIn) : 1
    let end = fadeOut > 0 ? min(1, (duration - time) / fadeOut) : 1
    return Float(volume * min(start, end))
  }
}
public struct TimelineAudioClip: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var source: TimelineAudioSource
  public var startTime: Double
  public var sourceIn: Double
  public var sourceOut: Double
  public var settings: TimelineAudioSettings
  public var playbackRate:Double?
  public var effectiveRate:Double {playbackRate ?? 1}
  public var duration: Double { (sourceOut - sourceIn)/effectiveRate }
  public init(id: UUID = UUID(), name: String, source: TimelineAudioSource, startTime: Double = 0,
              sourceIn: Double = 0, sourceOut: Double? = nil, settings: TimelineAudioSettings = .init()) {
    self.id = id; self.name = name; self.source = source; self.startTime = startTime
    self.sourceIn = sourceIn; self.sourceOut = sourceOut ?? source.duration; self.settings = settings
  }
  public func validate() throws {
    try source.validate(); try settings.validate()
    guard effectiveRate.isFinite,(1.0/240...240).contains(effectiveRate) else{throw CraftError.invalid("Invalid retained audio playback rate.")}
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 256,
      startTime.isFinite, sourceIn.isFinite, sourceOut.isFinite, startTime >= -86_400,
      sourceIn >= 0, sourceOut <= source.duration + 1e-9, duration > 1e-9, startTime + duration <= 86_400
    else { throw CraftError.invalid("Invalid audio clip name or timing.") }
  }
}
public struct TimelineAudioTrack: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var muted: Bool
  public var clips: [TimelineAudioClip]
  public init(id: UUID = UUID(), name: String, muted: Bool = false, clips: [TimelineAudioClip] = []) {
    self.id = id; self.name = name; self.muted = muted; self.clips = clips
  }
}
public enum TimelineAudioCommand: Sendable {
  case addTrack(UUID, String), renameTrack(UUID, String), removeTrack(UUID), muteTrack(UUID, Bool)
  case insert(UUID, TimelineAudioClip), importClip(UUID?, TimelineAudioClip), removeClip(UUID)
  case move(UUID, track: UUID, startTime: Double)
  case trim(UUID, startTime: Double, sourceIn: Double, sourceOut: Double)
  case settings(UUID, TimelineAudioSettings), movieSettings(UUID, TimelineAudioSettings)
  case split(UUID, Double)
  public var label: String {
    switch self {
    case .addTrack: "New Audio Track"; case .renameTrack: "Rename Audio Track"
    case .removeTrack: "Delete Audio Track"; case .muteTrack: "Mute Audio Track"
    case .insert, .importClip: "Add Audio"; case .removeClip: "Delete Audio Clip"
    case .move: "Move Audio Clip"; case .trim: "Trim Audio Clip"
    case .settings, .movieSettings: "Audio Settings"; case .split: "Split Audio At Playhead"
    }
  }
  public func apply(to document: inout CraftDocument) throws {
    guard var timeline = document.videoTimeline else { throw CraftError.invalid("Create a video Timeline before adding audio.") }
    var tracks = timeline.audioTracks ?? []
    func track(_ id: UUID) throws -> Int {
      guard let i = tracks.firstIndex(where: { $0.id == id }) else { throw CraftError.invalid("Audio track no longer exists.") }; return i
    }
    func clip(_ id: UUID) throws -> (Int, Int) {
      for t in tracks.indices { if let c = tracks[t].clips.firstIndex(where: { $0.id == id }) { return (t,c) } }
      throw CraftError.invalid("Audio clip no longer exists.")
    }
    switch self {
    case .addTrack(let id, let name): tracks.append(.init(id: id, name: name))
    case .renameTrack(let id, let name): tracks[try track(id)].name = name
    case .removeTrack(let id): tracks.remove(at: try track(id))
    case .muteTrack(let id, let muted): tracks[try track(id)].muted = muted
    case .importClip(let id, let value):
      if let id { tracks[try track(id)].clips.append(value) }
      else { tracks.append(.init(name:"Audio Track \(tracks.count + 1)",clips:[value])) }
    case .insert(let id, let value): tracks[try track(id)].clips.append(value)
    case .removeClip(let id): let (t,c) = try clip(id); tracks[t].clips.remove(at:c)
    case .move(let id, let target, let time):
      let (t,c) = try clip(id), destination = try track(target)
      var value = tracks[t].clips.remove(at:c); value.startTime = time; tracks[destination].clips.append(value)
    case .trim(let id, let time, let first, let last):
      let (t,c) = try clip(id); tracks[t].clips[c].startTime = time
      tracks[t].clips[c].sourceIn = first; tracks[t].clips[c].sourceOut = last
    case .settings(let id, let settings): let (t,c) = try clip(id); tracks[t].clips[c].settings = settings
    case .movieSettings(let id, let settings):
      try settings.validate()
      guard let i = document.layers.firstIndex(where: { $0.id == id }),
        (document.layers[i].video?.movie?.audioTracks ?? 0) > 0, !document.isPositionLocked(id)
      else { throw CraftError.invalid("Select an unlocked movie clip containing audio.") }
      document.layers[i].video?.audio = settings
    case .split(let id, let time):
      let (t,c) = try clip(id), old = tracks[t].clips[c]
      guard time.isFinite, time > old.startTime + 1e-9, time < old.startTime + old.duration - 1e-9
      else { throw CraftError.invalid("Place the playhead inside the audio clip.") }
      var right = old; right.id = UUID(); right.startTime = time
      right.sourceIn += (time - old.startTime)*old.effectiveRate; right.settings.fadeIn = 0
      tracks[t].clips[c].sourceOut = right.sourceIn; tracks[t].clips[c].settings.fadeOut = 0
      tracks[t].clips.insert(right, at:c+1)
    }
    for t in tracks.indices {
      tracks[t].clips.sort { $0.startTime == $1.startTime ? $0.id.uuidString < $1.id.uuidString : $0.startTime < $1.startTime }
    }
    // New media may extend a trimmed output without reintroducing old handles.
    let inserted:TimelineAudioClip?
    switch self {case .insert(_,let clip),.importClip(_,let clip):inserted=clip;default:inserted=nil}
    if let inserted {
      try inserted.validate()
      timeline.durationFrames=max(timeline.durationFrames,Int(ceil((inserted.startTime+inserted.duration)*timeline.frameRate-1e-9)))
    }
    timeline.audioTracks = tracks.isEmpty ? nil : tracks
    document.videoTimeline = timeline
    try document.validateTimelineAudio()
  }
}
extension CraftDocument {
  public var timelineAudioBytes: Int { videoTimeline?.audioTracks?.reduce(0) { $0 + $1.clips.reduce(256) { $0 + $1.source.data.count + 256 } } ?? 0 }
  public var timelineAudioEnd: Double { videoTimeline?.audioTracks?.flatMap(\.clips).map { $0.startTime + $0.duration }.max() ?? 0 }
  public var hasTimelineAudio: Bool {
    !(videoTimeline?.audioTracks?.flatMap(\.clips).isEmpty ?? true) || layers.contains { ($0.video?.movie?.audioTracks ?? 0) > 0 }
  }
  func validateTimelineAudio() throws {
    let tracks = videoTimeline?.audioTracks ?? []
    let clips = tracks.flatMap(\.clips)
    guard tracks.count <= 32, clips.count <= 512, Set(tracks.map(\.id)).count == tracks.count,
      Set(clips.map(\.id)).count == clips.count,
      tracks.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 256 })
    else { throw CraftError.invalid("Use at most 32 named audio tracks and 512 uniquely identified clips.") }
    for clip in clips { try clip.validate() }
    for layer in layers {
      if let settings = layer.video?.audio {
        try settings.validate()
        guard (layer.video?.movie?.audioTracks ?? 0) > 0 else { throw CraftError.invalid("Audio settings require retained movie audio.") }
      }
    }
  }
}
