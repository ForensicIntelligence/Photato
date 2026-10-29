import AppKit
import PhotoCraftCore

extension EditorStore {
  func presentFrameTimelineConversion() {
    guard canUseTimeline, document.animation != nil else { return }
    stopTimelinePlayback(render: false)
    let source = document
    let field = NSTextField(string: document.animation?.retainedVideoSource.map { String($0.timeline.frameRate) } ?? "30")
    let grid = NSGridView(views: [[NSTextField(labelWithString: "Frame Rate:"), field]])
    field.widthAnchor.constraint(equalToConstant: 100).isActive = true
    grid.setFrameSize(grid.fittingSize)
    let alert = NSAlert()
    alert.messageText = "Convert to Video Timeline"
    alert.informativeText = "Keep editable layers and convert frame compositions to Hold keyframes. The chosen rate samples the existing sequence; the duration rounds up to a complete video frame."
    if document.animation?.retainedVideoSource != nil {
      alert.informativeText += " Original audio resumes when frame order and delays are unchanged. If you changed timing, audio stays in the recoverable original Timeline."
    }
    alert.accessoryView = grid
    alert.addButton(withTitle: "Convert"); alert.addButton(withTitle: "Cancel")
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .alertFirstButtonReturn, let self else { return }
      guard self.canUseTimeline, self.document == source else {
        self.error = "The animation changed. Reopen conversion settings."; return
      }
      guard let rate = Double(field.stringValue), rate.isFinite, (1...240).contains(rate) else {
        self.error = "Enter a frame rate from 1 to 240 fps."; return
      }
      self.editTimeline(.convertToVideo(rate))
    }
    if let window = NSApp.keyWindow { alert.beginSheetModal(for: window, completionHandler: finish) }
    else { finish(alert.runModal()) }
  }

  func presentVideoFrameConversion() {
    guard canUseTimeline, let timeline=document.videoTimeline else{return}
    presentTemporalConversion(.convertFromVideo,title:"Convert to Frame Animation",
      message:"Create \(timeline.durationFrames) editable frames at \(timeline.frameRate) fps. Continuous motion becomes sampled frames. Frame playback is silent; the original Timeline and audio remain available through Restore Original Video Timeline.")
  }
  func presentVideoSourceRecovery() {
    guard canUseTimeline,document.animation?.retainedVideoSource != nil || document.videoTimeline?.retainedFrameSources?.isEmpty == false else{return}
    presentTemporalConversion(.restoreVideoSource,title:"Restore Original Video Timeline",
      message:"Restore the original layers, source media and audio from before conversion. This replaces subsequent layer and animation edits. You can Undo the restoration.")
  }
  private func presentTemporalConversion(_ command:AnimationCommand,title:String,message:String) {
    stopTimelinePlayback(render:false)
    let source=document,alert=NSAlert()
    alert.messageText=title;alert.informativeText=message
    alert.addButton(withTitle:title.hasPrefix("Restore") ? "Restore":"Convert");alert.addButton(withTitle:"Cancel")
    let finish:(NSApplication.ModalResponse)->Void = { [weak self] response in
      guard response == .alertFirstButtonReturn,let self else{return}
      guard self.canUseTimeline,self.document==source else{self.error="The document changed. Reopen conversion settings.";return}
      self.editTimeline(command)
    }
    if let window=NSApp.keyWindow {alert.beginSheetModal(for:window,completionHandler:finish)}else{finish(alert.runModal())}
  }
}
