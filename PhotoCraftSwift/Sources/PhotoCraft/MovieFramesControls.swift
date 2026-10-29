import AppKit
import AVKit
import SwiftUI

@MainActor private struct MovieFramesPlayer: NSViewRepresentable {
  let player: AVPlayer
  func makeNSView(context: Context) -> AVPlayerView {let view = AVPlayerView();view.controlsStyle = .inline;view.player = player;return view}
  func updateNSView(_ view: AVPlayerView,context: Context) {view.player = player}
}
struct MovieFramesView: View {
  @Bindable var model: MovieFramesWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      HStack {
        Text(model.source?.name ?? "Choose a video to import").font(.headline).lineLimit(1)
        Spacer();Button("Choose Movie…") {model.choose()}.disabled(model.loading || model.busy)
      }
      HStack(alignment:.top,spacing:20) {
        VStack(alignment:.leading,spacing:14) {
          GroupBox("Range To Import") {
            VStack(alignment:.leading,spacing:12) {
              Picker("Range",selection:$model.options.selectedRange) {
                Text("From Beginning To End").tag(false)
                Text("Selected Range Only").tag(true)
              }.pickerStyle(.radioGroup).labelsHidden()
              Group {if let info = model.source?.info {
                HStack {Text("Start");TextField("Start",value:$model.options.start,format:.number.precision(.fractionLength(3)));Text("s")}
                Slider(value:$model.options.start,in:0...info.duration).accessibilityLabel("Range start")
                HStack {Text("End");TextField("End",value:$model.options.end,format:.number.precision(.fractionLength(3)));Text("s")}
                Slider(value:$model.options.end,in:0...info.duration).accessibilityLabel("Range end")
              }}.disabled(!model.options.selectedRange)
            }.padding(8)
          }
          HStack {Text("Limit To Every");TextField("Interval",value:$model.options.every,format:.number).frame(width:60);Text("Frames")}
          Toggle("Make Frame Animation",isOn:$model.options.makeAnimation)
          if let info = model.source?.info {Text("\(info.width) × \(info.height) px · \(info.duration,format:.number.precision(.fractionLength(3))) s").font(.caption).foregroundStyle(.secondary)}
        }.frame(width:270).disabled(model.loading || model.busy || model.source == nil)
        Group {
          if let player = model.player {MovieFramesPlayer(player:player)} else {ZStack {Color.black;Text("Movie preview").foregroundStyle(.white.opacity(0.6))}}
        }.frame(maxWidth:.infinity,minHeight:320,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:6))
      }
      if let error = model.error {Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack {
        if model.loading || model.busy {ProgressView().controlSize(.small);Text(model.loading ? "Loading movie…":"Importing frames…").foregroundStyle(.secondary)}
        Spacer()
        Button(model.busy ? "Cancel Import":"Cancel") {if model.busy {model.cancelImport()} else {model.controller?.cancelMovieFrames()}}.keyboardShortcut(.cancelAction)
        Button("OK") {model.run()}.keyboardShortcut(.defaultAction).disabled(model.source == nil || model.loading || model.busy)
      }
    }.padding(20).frame(minWidth:780,minHeight:470)
      .onChange(of:model.options.start) {model.seekStart()}
  }
}
@MainActor final class MovieFramesWindow: NSWindowController,NSWindowDelegate {
  let model: MovieFramesWorkspace
  init(model: MovieFramesWorkspace) {
    self.model = model
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:540),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title = "Import Video To Layers";window.isReleasedWhenClosed = false;window.contentView = NSHostingView(rootView:MovieFramesView(model:model));window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) {nil}
  func windowWillClose(_ notification: Notification) {model.close();model.controller?.movieFramesWorkspace = nil;model.controller?.movieFramesWindow = nil}
}
extension CraftDocumentController {
  var canFinishMovieFrames: Bool {canPublishScanCrop && scanCropOperationID == nil}
  func beginMovieFrames(display: Bool = true) {
    if let movieFramesWindow {if display {movieFramesWindow.showWindow(nil)};return}
    guard movieFramesWorkspace == nil,canFinishMovieFrames else{return}
    let model = MovieFramesWorkspace(controller:self);movieFramesWorkspace = model
    model.didImport = { [weak self] in self?.cancelMovieFrames() }
    if display {let window = MovieFramesWindow(model:model);movieFramesWindow = window;window.showWindow(nil);model.choose()}
  }
  func cancelMovieFrames() {movieFramesWorkspace?.close();movieFramesWindow?.close();movieFramesWorkspace = nil;movieFramesWindow = nil}
}
extension AppDelegate {@objc func videoFramesToLayers() {controller.beginMovieFrames()}}
