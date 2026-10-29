import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canUseTimeline: Bool { canUseActions && !aiBusy && !printBusy && !showAI && !showImagePlayground && typeEditingDraft == nil && brushGesture == nil }
  func selectTimelineFrame(_ id: UUID) throws {
    guard canUseTimeline else { throw CraftError.invalid("Finish the current edit before selecting a frame.") }
    stopTimelinePlayback(render: false)
    try session.selectAnimationFrame(id); render()
  }
  func editTimeline(_ command: AnimationCommand) {
    guard canUseTimeline else { return }
    stopTimelinePlayback(render: false)
    switch command {
    case .convertFromVideo,.convertToVideo,.restoreVideoSource:performGeometry(.animation(command))
    default:perform(.animation(command))
    }
  }
  func stopTimelinePlayback(render refresh: Bool = true) {
    timelineAudioPreparation?.cancel(); timelineAudioPreparation = nil; timelineAudioPreparing = false
    timelineAudioPlayer?.stop(); timelineAudioPlayer = nil
    let hadPreview = timelinePreviewFrameID != nil || timelinePreviewVideoFrame != nil
    if timelineTask != nil || hadPreview { timelinePlaybackRevision = UUID() }
    timelineTask?.cancel(); timelineTask = nil; timelinePreviewFrameID = nil; timelinePreviewVideoFrame = nil; timelinePlaybackSource = nil
    if refresh && hadPreview { render() }
  }
  func startTimelinePlayback() throws {
    if document.videoTimeline != nil { try startVideoPlayback(); return }
    guard canUseTimeline, let animation = document.animation else { throw CraftError.invalid("Create an animation and finish the current edit before playback.") }
    stopTimelinePlayback(render: false)
    let source = document; timelinePlaybackSource = source; timelinePlaybackRevision = UUID()
    let start = ProcessInfo.processInfo.systemUptime
    timelineTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.document == source, self.canUseTimeline else { self?.stopTimelinePlayback(); return }
        do {
          let location = try animation.playbackFrame(elapsed: ProcessInfo.processInfo.systemUptime - start, startingAt: animation.selectedIndex)
          if location.finished { self.stopTimelinePlayback(); return }
          let id = animation.frames[location.index].id
          if self.timelinePreviewFrameID != id { self.timelinePreviewFrameID = id; self.render(isAnimationPlayback: true) }
          // Let the current render complete so a slow canvas cannot starve its own preview.
          await self.renderTask?.value
          try await Task.sleep(for: .milliseconds(10))
        } catch { return }
      }
    }
  }
  var animationState: [String: Any] {
    ["timelineVisible": timelineVisible, "playing": timelineTask != nil,
      "exportOperationID": animationExportID?.uuidString as Any? ?? NSNull(),
      "previewFrameID": timelinePreviewFrameID?.uuidString as Any? ?? NSNull(),
      "animation": document.animation.map { TemporalContentAPI.animation($0) } as Any? ?? NSNull()]
  }
}

private actor TimelineThumbnailRenderer {
  static let shared = TimelineThumbnailRenderer()
  func image(_ document: CraftDocument, frame: UUID) throws -> CGImage {
    try Task.checkCancellation()
    let frameDocument = try document.animationDocument(at: frame)
    let surface = try Renderer.composite(frameDocument)
    let scale = min(1, 80.0 / Double(max(surface.width, surface.height)))
    let small = try Renderer.resize(surface, width: max(1, Int(Double(surface.width) * scale)), height: max(1, Int(Double(surface.height) * scale)))
    return try ColorManagement.image(small, in: frameDocument)
  }
}
private struct TimelineThumbnail: View {
  let document: CraftDocument
  let frame: UUID
  let generation: Int
  @State private var image: CGImage?
  @State private var failure: String?
  var body: some View {
    ZStack {
      Color(white: 0.18)
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else if failure != nil { Image(systemName: "exclamationmark.triangle").help(failure!) }
      else { ProgressView().controlSize(.small) }
    }.frame(width: 76, height: 56)
      .task(id: generation) {
        do { let result = try await TimelineThumbnailRenderer.shared.image(document, frame: frame); try Task.checkCancellation(); image = result; failure = nil }
        catch { if !Task.isCancelled { failure = error.localizedDescription } }
      }
  }
}
struct TimelinePanel: View {
  @Bindable var store: EditorStore
  @State private var tweenCount = 5
  @State private var tweenPosition = true
  @State private var tweenOpacity = true
  @State private var showTween = false
  var animation: FrameAnimation? { store.document.animation }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Timeline").fontWeight(.semibold)
        Spacer()
        Menu {
          Button("Import Image Sequence…") { store.presentVideoSequenceImport() }
          Button("Convert to Video Timeline…") { store.presentFrameTimelineConversion() }.disabled(animation == nil)
          if animation?.retainedVideoSource != nil {Button("Restore Original Video Timeline…") {store.presentVideoSourceRecovery()}}
          Button("Make Frames From Layers") { store.editTimeline(.fromLayers) }.disabled(animation != nil)
          Button("Export Image Sequence…") { store.presentImageSequenceExport() }.disabled(animation == nil)
          Button("Export Animated GIF…") { store.presentAnimationExport() }.disabled(animation == nil)
          Button("Reverse Frames") { store.editTimeline(.reverse) }.disabled(animation == nil)
          Button("Delete Animation", role: .destructive) { store.editTimeline(.remove) }.disabled(animation == nil)
        } label: { Image(systemName: "line.3.horizontal") }.menuStyle(.borderlessButton).frame(width: 24)
        Button { store.stopTimelinePlayback(); store.timelineVisible = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close Timeline")
      }
      if let animation {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
              ForEach(Array(animation.frames.enumerated()), id: \.element.id) { index, frame in
                Button {
                  do { try store.selectTimelineFrame(frame.id) } catch { store.error = error.localizedDescription }
                } label: {
                  VStack(spacing: 3) {
                    TimelineThumbnail(document: store.document, frame: frame.id, generation: store.timelineContentGeneration)
                    HStack { Text("\(index + 1)"); Spacer(); Text(frame.delay, format: .number.precision(.fractionLength(0...2))) + Text(" sec.") }
                  }.padding(4).background((store.timelinePreviewFrameID ?? animation.selectedFrameID) == frame.id ? StudioTheme.selected : StudioTheme.field)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke((store.timelinePreviewFrameID ?? animation.selectedFrameID) == frame.id ? StudioTheme.accent : .clear, lineWidth: 2))
                }.buttonStyle(.plain).id(frame.id).accessibilityLabel("Frame \(index + 1), \(frame.delay) seconds")
              }
            }.padding(3)
          }.frame(height: 92)
            .onChange(of: animation.selectedFrameID) { _, id in proxy.scrollTo(id) }
        }
        HStack(spacing: 12) {
          Picker("Loop", selection: Binding(get: { animation.loopCount }, set: { store.editTimeline(.loop($0)) })) {
            Text("Forever").tag(0); Text("Once").tag(1); Text("3 times").tag(3)
            if ![0,1,3].contains(animation.loopCount) { Text("\(animation.loopCount) times").tag(animation.loopCount) }
          }.labelsHidden().frame(width: 100)
          Button { selectOffset(-animation.selectedIndex) } label: { Image(systemName: "backward.end.fill") }.help("Select first frame")
          Button { selectOffset(-1) } label: { Image(systemName: "backward.fill") }.help("Select previous frame")
          Button {
            if store.timelineTask != nil { store.stopTimelinePlayback() }
            else { do { try store.startTimelinePlayback() } catch { store.error = error.localizedDescription } }
          } label: { Image(systemName: store.timelineTask == nil ? "play.fill" : "stop.fill") }.help("Play or stop animation")
          Button { selectOffset(1) } label: { Image(systemName: "forward.fill") }.help("Select next frame")
          Divider().frame(height: 15)
          Button { showTween = true } label: { Image(systemName: "circle.lefthalf.filled") }.help("Tween animation frames").disabled(animation.frames.count < 2)
          Button { store.editTimeline(.duplicate) } label: { Image(systemName: "plus.square") }.help("Duplicate selected frame")
          Button { store.editTimeline(.delete) } label: { Image(systemName: "trash") }.help("Delete selected frame").disabled(animation.frames.count < 2)
          Button("←") { store.editTimeline(.reorder(animation.selectedIndex - 1)) }.disabled(animation.selectedIndex == 0).help("Move frame left")
          Button("→") { store.editTimeline(.reorder(animation.selectedIndex + 1)) }.disabled(animation.selectedIndex == animation.frames.count - 1).help("Move frame right")
          Text("Delay:")
          TextField("Seconds", value: Binding(get: { animation.frames[animation.selectedIndex].delay }, set: { store.editTimeline(.delay($0)) }), format: .number).frame(width: 55)
          Text("sec.")
          Spacer(minLength: 0)
        }.buttonStyle(.borderless)
      } else {
        HStack { Spacer(); Button("Create Video Timeline") { store.editVideo(.create(frameRate:30,durationFrames:150)) }; Button("Create Frame Animation") { store.editTimeline(.create) }; Spacer() }.frame(height: 100)
      }
    }.padding(8).background(StudioTheme.panel).frame(height: animation == nil ? 150 : 166)
      .disabled(!store.canUseTimeline)
      .onDisappear { store.stopTimelinePlayback() }
      .popover(isPresented: $showTween) {
        VStack(alignment: .leading) {
          Text("Tween with Next Frame").font(.headline)
          Stepper("Frames to add: \(tweenCount)", value: $tweenCount, in: 1...100)
          Toggle("Position", isOn: $tweenPosition); Toggle("Opacity", isOn: $tweenOpacity)
          HStack { Button("Cancel") { showTween = false }; Button("OK") { store.editTimeline(.tween(count:tweenCount,position:tweenPosition,opacity:tweenOpacity)); showTween = false }.disabled(!tweenPosition && !tweenOpacity) }
        }.padding().frame(width: 260)
      }
  }
  func selectOffset(_ delta: Int) {
    guard let animation, animation.frames.indices.contains(animation.selectedIndex + delta) else { return }
    do { try store.selectTimelineFrame(animation.frames[animation.selectedIndex + delta].id) } catch { store.error = error.localizedDescription }
  }
}
extension AppDelegate {
  @objc func showTimeline() { store?.timelineVisible.toggle() }
}
