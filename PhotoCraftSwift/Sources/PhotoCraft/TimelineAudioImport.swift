import AppKit
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canImportTimelineAudio: Bool { canUseTimeline && timelineTask == nil && document.videoTimeline != nil && isCompositeColorTarget }
  func importTimelineAudio(_ url: URL, trackID: UUID? = nil) async throws {
    guard canImportTimelineAudio else { throw CraftError.invalid("Create a video Timeline and finish the current edit before adding audio.") }
    let source = document, generation = layerPanelGeneration, operation = UUID()
    let clipID = UUID(), start = source.videoTimeline!.seconds
    geometryBusy = true; timelineAudioImportID = operation; renderTask?.cancel()
    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    defer { if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil; timelineAudioImportID = nil; render() } }
    let worker = Task.detached(priority:.userInitiated) {
      let audio = try TimelineAudioIO.read(url).0
      let clip = TimelineAudioClip(id:clipID,name:url.deletingPathExtension().lastPathComponent,source:audio,startTime:start)
      return try PreparedEdit(command:.video(.audio(.importClip(trackID,clip))),document:source)
    }
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }; geometryTask = observer
    let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !observer.isCancelled, layerPanelGeneration == generation, document == source else { throw CancellationError() }
    try executeCompositePreparedEdit(prepared)
    selectedAudioClipID = clipID
    selectedAudioTrackID = document.videoTimeline?.audioTracks?.first(where: { $0.clips.contains(where: { $0.id == clipID }) })?.id
    onChange?(.changeDone); status = "Added audio"; timelineVisible = true
  }
  func presentTimelineAudioImport() {
    guard canImportTimelineAudio else { return }
    let panel = NSOpenPanel(); panel.title = "Add Audio"; panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = false
    panel.message = "Add audio at the playhead. The original source is retained with editable volume, mute and fades."
    let window = NSApp.keyWindow, track = selectedAudioTrackID
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let self, let url = panel.url else { return }
      let progress = NSAlert(); progress.messageText = "Adding Audio"; progress.informativeText = "Decoding audio…"; progress.addButton(withTitle:"Cancel")
      let task = Task { @MainActor in
        defer { if let parent = progress.window.sheetParent { parent.endSheet(progress.window,returnCode:.OK) } }
        do { try await self.importTimelineAudio(url,trackID:track) }
        catch is CancellationError { self.status = "Audio import cancelled" }
        catch { self.error = error.localizedDescription }
      }
      if let window { progress.beginSheetModal(for:window) { if $0 != .OK { task.cancel() } } }
    }
    if let window { panel.beginSheetModal(for:window,completionHandler:finish) } else { panel.begin(completionHandler:finish) }
  }
  func newAudioTrack() {
    let id = UUID(); editVideo(.audio(.addTrack(id,"Audio Track \((document.videoTimeline?.audioTracks?.count ?? 0) + 1)")))
    if document.videoTimeline?.audioTracks?.contains(where: { $0.id == id }) == true { selectedAudioTrackID = id; selectedAudioClipID = nil }
  }
  var selectedAudioClip: TimelineAudioClip? { document.videoTimeline?.audioTracks?.flatMap(\.clips).first { $0.id == selectedAudioClipID } }
  func audioTrimCommand(_ id: UUID, leading: Bool, delta: Double) throws -> TimelineAudioCommand {
    guard let clip = document.videoTimeline?.audioTracks?.flatMap(\.clips).first(where: { $0.id == id }), let timeline = document.videoTimeline else { throw CraftError.invalid("Audio clip no longer exists.") }
    let end=Double(timeline.durationFrames)/timeline.frameRate
    let delta=delta+(leading ? max(0,clip.startTime)-clip.startTime : min(end,clip.startTime+clip.duration)-(clip.startTime+clip.duration))
    let minimum = min(clip.duration,1 / timeline.frameRate)
    if leading {
      let change = min(clip.duration - minimum,max(max(-clip.sourceIn/clip.effectiveRate,-clip.startTime),delta))
      return .trim(id,startTime:clip.startTime + change,sourceIn:clip.sourceIn + change*clip.effectiveRate,sourceOut:clip.sourceOut)
    }
    let change = max(minimum - clip.duration,min((clip.source.duration - clip.sourceOut)/clip.effectiveRate,delta))
    return .trim(id,startTime:clip.startTime,sourceIn:clip.sourceIn,sourceOut:clip.sourceOut + change*clip.effectiveRate)
  }
}
