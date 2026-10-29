import SwiftUI
import PhotoCraftCore

struct TimelineAudioControls: View {
  @Bindable var store: EditorStore
  @State private var settings = TimelineAudioSettings()
  var clip: TimelineAudioClip? { store.selectedAudioClip }
  var movie: Layer? { (store.activeLayer?.video?.movie?.audioTracks ?? 0) > 0 ? store.activeLayer : nil }
  var track: TimelineAudioTrack? { store.document.videoTimeline?.audioTracks?.first { $0.id == store.selectedAudioTrackID } }
  var body: some View {
    HStack(spacing:4) {
      Menu {
        Button("Add Audio…") { store.presentTimelineAudioImport() }.disabled(!store.canImportTimelineAudio)
        Button("New Audio Track") { store.newAudioTrack() }
        if let track {
          Button(track.muted ? "Unmute Audio Track" : "Mute Audio Track") { store.editVideo(.audio(.muteTrack(track.id,!track.muted))) }
          Button("Delete Audio Track") { store.editVideo(.audio(.removeTrack(track.id))) }
        }
        if let clip {
          Divider()
          Button("Split At Playhead") { store.editVideo(.audio(.split(clip.id,store.document.videoTimeline?.seconds ?? 0))) }
          Button("Delete Audio Clip") { store.editVideo(.audio(.removeClip(clip.id))) }
        }
      } label: { Image(systemName:"music.note") }.help("Audio tracks")
      Button { store.showAudioControls.toggle() } label: { Image(systemName:"speaker.wave.2") }
        .help("Audio settings").disabled(clip == nil && movie == nil)
        .popover(isPresented:$store.showAudioControls) {
          VStack(alignment:.leading,spacing:12) {
            Text("Audio").font(.headline)
            Text(clip?.name ?? movie?.name ?? "Select an audio clip").foregroundStyle(.secondary)
            Toggle("Mute Audio",isOn:$settings.muted)
            HStack { Text("Volume"); Slider(value:$settings.volume,in:0...1); Text("\(Int(settings.volume * 100))%").frame(width:40) }
            HStack {
              Text("Fade In"); TextField("Seconds",value:$settings.fadeIn,format:.number).frame(width:70)
              Text("Fade Out"); TextField("Seconds",value:$settings.fadeOut,format:.number).frame(width:70)
            }
            Text("Fade durations are in seconds.").font(.caption).foregroundStyle(.secondary)
            HStack {
              Button("Cancel") { store.showAudioControls = false }; Spacer()
              Button("Apply") {
                if let clip { store.editVideo(.audio(.settings(clip.id,settings))) }
                else if let movie { store.editVideo(.audio(.movieSettings(movie.id,settings))) }
                let actual = clip?.settings ?? movie?.video?.audio
                if actual == settings { store.showAudioControls = false }
              }.disabled((clip == nil && movie == nil) || (try? settings.validate()) == nil)
            }
          }.padding(16).frame(width:350).onAppear { load() }.onChange(of:store.selectedAudioClipID) { _,_ in load() }.onChange(of:store.document.activeLayerID) { _,_ in load() }
        }
      if store.timelineAudioPreparing { ProgressView().controlSize(.mini).help("Preparing synchronized audio") }
    }
  }
  func load() { settings = clip?.settings ?? movie?.video?.audio ?? .init() }
}
