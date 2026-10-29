import AppKit
import AVFoundation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor protocol TimelineAudioPlaying: AnyObject {
  var currentTime: Double { get }
  var isPlaying: Bool { get }
  func start(at seconds: Double, looping: Bool) throws
  func stop()
}
@MainActor final class NativeTimelineAudioPlayer: TimelineAudioPlaying {
  private let player: AVAudioPlayer
  init(data: Data) throws {
    player = try AVAudioPlayer(data:data, fileTypeHint:AVFileType.wav.rawValue)
    guard player.prepareToPlay() else { throw CraftError.unsupported("Audio output could not be prepared.") }
  }
  var currentTime: Double { player.currentTime }
  var isPlaying: Bool { player.isPlaying }
  func start(at seconds: Double, looping: Bool) throws {
    player.currentTime = seconds; player.numberOfLoops = looping ? -1 : 0
    guard player.play(atTime:player.deviceCurrentTime + 0.05) else { throw CraftError.unsupported("Audio output is unavailable. Mute audio to preview silently.") }
  }
  func stop() { player.stop() }
}
extension EditorStore {
  func startNativeVideoPlayback() throws {
    guard canUseTimeline, let timeline = document.videoTimeline else { throw CraftError.invalid("Create a video Timeline first.") }
    stopTimelinePlayback(render:false)
    let source = document, operation = UUID()
    timelinePlaybackSource = source; timelinePlaybackRevision = operation
    let area=timeline.effectiveWorkArea,areaStart=Double(area.startFrame)/timeline.frameRate,areaDuration=Double(area.count)/timeline.frameRate
    let audible = !TimelineAudioMixer.clips(source).isEmpty
    timelineAudioPreparing = audible
    timelineTask = Task { @MainActor [weak self] in
      guard let self, !Task.isCancelled, self.timelinePlaybackRevision == operation else { return }
      do {
        if audible {
          let worker = Task.detached(priority:.userInitiated) { try TimelineAudioMixer.render(source,startTime:areaStart,duration:areaDuration)?.wave() }
          self.timelineAudioPreparation = worker
          let data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard self.timelinePlaybackRevision == operation, self.document == source, self.canUseTimeline else {
            if self.timelinePlaybackRevision == operation { self.stopTimelinePlayback() }; return
          }
          self.timelineAudioPreparation = nil; self.timelineAudioPreparing = false
          if let data {
            let player = try self.timelineAudioFactory(data)
            try player.start(at:Double(timeline.playbackStartFrame-area.startFrame)/timeline.frameRate, looping:timeline.looping || (timeline.finiteLoopCount != nil && timeline.playbackStartFrame > area.startFrame))
            self.timelineAudioPlayer = player
          }
        }
        let start = ProcessInfo.processInfo.systemUptime
        var previousAudioTime=Double(timeline.playbackStartFrame-area.startFrame)/timeline.frameRate
        var audioElapsed=0.0
        while !Task.isCancelled {
          guard self.timelinePlaybackRevision == operation, self.document == source, self.canUseTimeline else {
            if self.timelinePlaybackRevision == operation { self.stopTimelinePlayback() }; return
          }
          let frame: Int
          if let player = self.timelineAudioPlayer {
            guard player.isPlaying else { self.stopTimelinePlayback(); return }
            let audioTime=player.currentTime
            audioElapsed += audioTime >= previousAudioTime ? audioTime-previousAudioTime:areaDuration-previousAudioTime+audioTime
            previousAudioTime=audioTime
            if let count=timeline.finiteLoopCount,audioElapsed+1e-9>=areaDuration*Double(count) {self.stopTimelinePlayback();return}
            frame = min(area.endFrame-1,max(area.startFrame,area.startFrame+Int(floor(audioTime * timeline.frameRate))))
          } else {
            let value = try timeline.playbackFrame(elapsed:ProcessInfo.processInfo.systemUptime - start)
            if value.finished { self.stopTimelinePlayback(); return }; frame = value.frame
          }
          if self.timelinePreviewVideoFrame != frame { self.timelinePreviewVideoFrame = frame; self.render(isAnimationPlayback:true) }
          await self.renderTask?.value
          try await Task.sleep(for:.milliseconds(10))
        }
      } catch {
        if self.timelinePlaybackRevision == operation {
          self.stopTimelinePlayback()
          if !(error is CancellationError) { self.error = error.localizedDescription }
        }
      }
    }
  }
}
