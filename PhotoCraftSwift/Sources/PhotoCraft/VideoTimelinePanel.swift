import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func selectVideoFrame(_ frame: Int) throws {
    guard canUseTimeline else { throw CraftError.invalid("Finish the current edit before moving the playhead.") }
    stopTimelinePlayback(render:false); try session.selectVideoFrame(frame); render()
  }
  func editVideo(_ command: VideoCommand) { guard canUseTimeline else { return }; stopTimelinePlayback(render:false); perform(.video(command)) }
  func startVideoPlayback() throws { try startNativeVideoPlayback() }
  var videoState: [String:Any] {
    ["canCreateBlankLayer":canCreateBlankVideoLayer,"pixelsPerSecond":videoTimelinePixelsPerSecond,"selectedTransitionID":videoSelectedTransitionID?.uuidString as Any? ?? NSNull(),"transitionEditorVisible":videoTransitionEditorVisible,"arrangement":VideoArrangementAPI.state(document),"placementOperationID":moviePlacementID?.uuidString as Any? ?? NSNull(),"timeline":document.videoTimeline.map { TemporalContentAPI.timeline($0) } as Any? ?? NSNull(),
     "previewFrame":timelinePreviewVideoFrame as Any? ?? NSNull(),
     "keyframes":document.layers.filter{$0.videoKeyframes != nil}.map{["layerID":$0.id.uuidString,"keys":$0.videoKeyframes!.map{TemporalContentAPI.key($0)}] as [String:Any]},
     "clips":document.layers.compactMap { layer -> [String:Any]? in
       guard let clip = layer.video else { return nil }
       return ["layerID":layer.id.uuidString,"sourceFrames":clip.frames.count,"sparseFrames":clip.frames.isSparse,"storedFrames":clip.frames.storedFrameCount,"sourceFrameRate":clip.frameRate,"sourceIn":clip.sourceStart,"sourceOut":clip.sourceEnd,"startTime":clip.startTime,"inFrame":clip.inFrame,"outFrame":clip.outFrame,"duration":clip.duration,"movie":MovieAPI.state(clip.movie)]
     }]
  }
}
struct VideoTimelinePanel: View {
  @Bindable var store: EditorStore
  @State private var showProperties=false
  var body: some View {
    if let timeline = store.document.videoTimeline {
      VStack(alignment:.leading,spacing:8) {
        HStack {
          Text("Timeline").fontWeight(.semibold);VideoTransitionControls(store:store);TimelineAudioControls(store:store);Spacer()
          Button("Export Image Sequence…") { store.presentImageSequenceExport() }
          Menu {
            Button("Convert to Frame Animation…") {store.presentVideoFrameConversion()}
            if timeline.retainedFrameSources?.isEmpty == false {Button("Restore Original Video Timeline…") {store.presentVideoSourceRecovery()}}
            Divider()
            TimelineWorkspaceMenu(store:store)
            Button("New Blank Video Layer"){store.createBlankVideoLayer()}.disabled(!store.canCreateBlankVideoLayer)
            Button("Render Video…"){store.presentRenderVideo()}
            Divider()
            Button("New Video Group") {store.editVideo(.arrange(.group("Video Group",[])))}
            Button("New Video Group from Selected Clips") {store.editVideo(.arrange(.group("Video Group",Array(store.layoutSelection))))}
            Button("Split At Playhead") {store.editVideo(.arrange(.split(store.layoutSelection)))}
            Divider()
            Button("Remove Timeline"){store.editVideo(.remove)}.disabled(store.document.layers.contains{$0.video != nil}) } label:{Image(systemName:"line.3.horizontal")}
          Button("Add Movie…") { store.presentMovieLayerImport() }
          Button("Import Image Sequence…") { store.presentVideoSequenceImport() }
          Button { store.stopTimelinePlayback();store.timelineVisible = false } label:{Image(systemName:"xmark")}
        }
        HStack {
          Button { if store.timelineTask != nil { store.stopTimelinePlayback() } else { do { try store.startVideoPlayback() } catch { store.error=error.localizedDescription } } } label:{Image(systemName:store.timelineTask == nil ? "play.fill":"stop.fill")}
          Text("Frame \((store.timelinePreviewVideoFrame ?? timeline.currentFrame)+1) / \(timeline.durationFrames)").monospacedDigit().frame(width:145,alignment:.leading)
          Slider(value:Binding(get:{Double(timeline.currentFrame)},set:{ value in do { try store.selectVideoFrame(Int(value)) } catch { store.error=error.localizedDescription } }),in:0...Double(max(1,timeline.durationFrames-1)),step:1).disabled(timeline.durationFrames == 1)
          Text("fps")
          TextField("Frame rate",value:Binding(get:{timeline.frameRate},set:{store.editVideo(.frameRate($0))}),format:.number).frame(width:55)
          Text("Frames")
          TextField("Duration",value:Binding(get:{timeline.durationFrames},set:{store.editVideo(.duration($0))}),format:.number).frame(width:60)
          Toggle(timeline.finiteLoopCount.map{"Loop (\($0) passes)"} ?? "Loop",isOn:Binding(get:{timeline.looping},set:{store.editVideo(.loop($0))}))
          Button {store.toggleOnionSkins()} label:{Image(systemName:"square.3.layers.3d").foregroundStyle(timeline.onionSkin?.enabled == true ? Color.accentColor:Color.primary)}.help("Toggle Onion Skins")
          Image(systemName:"magnifyingglass")
          Slider(value:$store.videoTimelinePixelsPerSecond,in:5...400).frame(width:80).help("Timeline zoom")
        }
        VideoArrangementControls(store:store)
        VideoTrackCanvas(store:store).frame(minHeight:100)
        DisclosureGroup("Clip and keyframe properties",isExpanded:$showProperties) {
        ScrollView(.vertical) {
          VStack(alignment:.leading,spacing:5) {
            ForEach(store.document.layers) { layer in
              VideoLayerKeyframeControls(store:store,layer:layer)
              if let clip = layer.video {
                HStack(spacing:8) {
                  Image(systemName:"film");Text(layer.name).lineLimit(1).frame(width:130,alignment:.leading)
                  Text("Start (sec.)")
                  TextField("Start",value:Binding(get:{clip.startTime},set:{ timing(layer,clip,start:$0) }),format:.number).frame(width:55).disabled(store.document.layers.first{$0.id==layer.parentID}?.group?.videoStartTime != nil)
                  Text("In")
                  TextField("First source frame",value:Binding(get:{clip.inFrame},set:{ timing(layer,clip,first:$0) }),format:.number).frame(width:50)
                  Text("Out")
                  TextField("Exclusive source end",value:Binding(get:{clip.outFrame},set:{ timing(layer,clip,end:$0) }),format:.number).frame(width:50)
                  Text("Source fps")
                  TextField("Source frame rate",value:Binding(get:{clip.frameRate},set:{ timing(layer,clip,rate:$0) }),format:.number).frame(width:55)
                  if let movie=clip.movie,movie.audioTracks>0 {Image(systemName:clip.audio?.muted == true ? "speaker.slash":"speaker.wave.2").help("Select this movie clip and open Audio settings for volume, mute and fades.")}
                  Spacer(minLength:0)
                }.padding(5).background(StudioTheme.field)
              }
            }
          }
        }
        }
      }.padding(8).frame(height:320).clipped().background(StudioTheme.panel).disabled(!store.canUseTimeline).onDisappear{store.stopTimelinePlayback()}
    }
  }
  func timing(_ layer:Layer,_ clip:VideoClip,start:Double?=nil,first:Int?=nil,end:Int?=nil,rate:Double?=nil) {
    store.editVideo(.timing(layer.id,startTime:start ?? clip.startTime,inFrame:first ?? clip.inFrame,outFrame:end ?? clip.outFrame,frameRate:rate ?? clip.frameRate))
  }
}
