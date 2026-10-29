import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

@MainActor final class VideoRenderAccessory: NSObject {
  let codec=NSPopUpButton(frame:.zero,pullsDown:false)
  let width=NSTextField(),height=NSTextField(),rate=NSTextField(),first=NSTextField(),last=NSTextField(),bitRate=NSTextField()
  let workArea=NSButton(checkboxWithTitle:"Use work area",target:nil,action:nil)
  let hasTimeline:Bool
  let audio=NSButton(checkboxWithTitle:"Include audio",target:nil,action:nil)
  let alpha=NSButton(checkboxWithTitle:"Preserve transparency",target:nil,action:nil)
  let view:NSGridView
  init(document:CraftDocument) {
    hasTimeline=document.videoTimeline != nil
    width.stringValue=String(document.width);height.stringValue=String(document.height)
    rate.stringValue=String(document.videoTimeline?.frameRate ?? 30)
    first.stringValue="1";last.stringValue=String(document.animation?.frames.count ?? document.videoTimeline?.durationFrames ?? 0)
    bitRate.placeholderString="Automatic";audio.state = .on
    codec.addItems(withTitles:VideoRenderCodec.allCases.map(\.name))
    let labels=["Format:","Width (pixels):","Height (pixels):","Frames per second:","First frame:","Last frame:","Bit rate (Mbps):","","",""]
    let controls:[NSView]=[codec,width,height,rate,first,last,bitRate,workArea,audio,alpha]
    view=NSGridView(views:zip(labels,controls).map{[NSTextField(labelWithString:$0),$1]})
    super.init();view.rowSpacing=8;view.columnSpacing=12
    for control in controls{control.widthAnchor.constraint(equalToConstant:270).isActive=true}
    workArea.target=self;workArea.action = #selector(changed);codec.target=self;codec.action = #selector(changed);changed();view.setFrameSize(view.fittingSize)
  }
  @objc func changed() {
    workArea.isEnabled=hasTimeline;first.isEnabled=workArea.state != .on;last.isEnabled=workArea.state != .on
    let value=VideoRenderCodec.allCases[codec.indexOfSelectedItem]
    bitRate.isEnabled=value.usesBitRate;alpha.isEnabled=value.supportsAlpha
    if !value.usesBitRate{bitRate.stringValue=""};if !value.supportsAlpha{alpha.state = .off}
  }
  func options() throws -> VideoRenderOptions {
    guard let w=Int(width.stringValue),let h=Int(height.stringValue),let fps=Double(rate.stringValue),
      let a=Int(workArea.state == .on ? "1":first.stringValue),let b=Int(workArea.state == .on ? "1":last.stringValue),a>0,b>0 else{throw CraftError.invalid("Enter valid dimensions, frame rate and frame numbers.")}
    let bits:Int?
    if bitRate.stringValue.trimmingCharacters(in:.whitespaces).isEmpty{bits=nil}
    else{guard let mbps=Double(bitRate.stringValue),mbps.isFinite,(0.1...200).contains(mbps) else{throw CraftError.invalid("Bit rate must be 0.1–200 Mbps, or blank for automatic.")};bits=Int((mbps*1_000_000).rounded())}
    return .init(codec:VideoRenderCodec.allCases[codec.indexOfSelectedItem],width:w,height:h,frameRate:fps,
      firstFrame:workArea.state == .on ? 0:a-1,lastFrame:workArea.state == .on ? nil:b-1,bitRate:bits,includeAudio:audio.state == .on,preserveAlpha:alpha.state == .on,useWorkArea:workArea.state == .on)
  }
}
extension EditorStore {
  var canRenderVideo:Bool {canUseTimeline && timelineTask == nil && (document.animation != nil || document.videoTimeline != nil)}
  func encodedVideo(_ options:VideoRenderOptions,maximumBytes:Int=VideoRender.maximumBytes)async throws->RenderedVideo {
    guard canRenderVideo,videoRenderID == nil else{throw CraftError.invalid("Stop playback and finish the current edit before rendering video.")}
    _=try options.plan(for:document)
    let snapshot=document,generation=layerPanelGeneration,operation=UUID()
    videoRenderID=operation;geometryBusy=true;status="Rendering video…"
    let worker=Task.detached(priority:.userInitiated){try VideoRender.render(snapshot,options:options,maximumBytes:maximumBytes,
      maximumAudioBytes:min(TimelineAudioIO.maximumDecodedBytes,maximumBytes))};videoRenderWorker=worker
    let observer=Task{await withTaskCancellationHandler{_=try? await worker.value}onCancel:{worker.cancel()}};geometryTask=observer
    var completed=false
    defer{if videoRenderID==operation{videoRenderID=nil;videoRenderWorker=nil;if layerPanelGeneration==generation{geometryBusy=false;geometryTask=nil};status=completed ? "Video rendered":"Video rendering stopped"}}
    let output=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    do {
      try Task.checkCancellation()
      guard !worker.isCancelled,!observer.isCancelled,document==snapshot,layerPanelGeneration==generation else{throw CancellationError()}
      completed=true;return output
    } catch{output.discard();throw error}
  }
  func presentRenderVideo() {
    guard canRenderVideo else{return}
    let snapshot=document,generation=layerPanelGeneration,accessory=VideoRenderAccessory(document:document)
    let settings=NSAlert();settings.messageText="Render Video"
    settings.informativeText="Export a movie from the Timeline. Frame numbers start at 1. Output is SDR Rec. 709 with square pixels. Transparency is composited on black unless preserved. Uncompressed movies use QuickTime row metadata that some readers do not support."
    settings.accessoryView=accessory.view;settings.addButton(withTitle:"Continue…");settings.addButton(withTitle:"Cancel")
    let window=NSApp.keyWindow
    let configure:(NSApplication.ModalResponse)->Void = { [weak self] response in
      guard response == .alertFirstButtonReturn,let self else{return}
      do {
        let options=try accessory.options();_=try options.plan(for:snapshot)
        let panel=NSSavePanel();panel.title="Render Video";panel.prompt="Render"
        panel.allowedContentTypes=[options.codec.fileExtension == "mp4" ? .mpeg4Movie:.quickTimeMovie]
        panel.nameFieldStringValue=(snapshot.name as NSString).deletingPathExtension+"."+options.codec.fileExtension
        let save:(NSApplication.ModalResponse)->Void = { [weak self] response in
          guard response == .OK,let self,let destination=panel.url else{return}
          guard self.canRenderVideo,self.document==snapshot,self.layerPanelGeneration==generation else{self.error="The document changed. Open Render Video again.";return}
          let progress=NSAlert();progress.messageText="Rendering Video";progress.informativeText="Compositing frames and encoding the movie…";progress.addButton(withTitle:"Cancel")
          let task=Task{ @MainActor in
            let scoped=destination.startAccessingSecurityScopedResource()
            defer{if scoped{destination.stopAccessingSecurityScopedResource()};if let parent=progress.window.sheetParent{parent.endSheet(progress.window,returnCode:.OK)}}
            do {
              let output=try await self.encodedVideo(options);defer{output.discard()}
              let worker=Task.detached(priority:.userInitiated){try PreparedVideoPublication(output:output,destination:destination)}
              let publication=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
              defer{publication.discard()}
              try Task.checkCancellation()
              guard self.document==snapshot,self.layerPanelGeneration==generation else{throw CancellationError()}
              try publication.commit();self.status="Rendered \(output.plan.frameCount) video frames"
            }catch is CancellationError{self.status="Video rendering cancelled"}catch{self.error=error.localizedDescription}
          }
          if let window{progress.beginSheetModal(for:window){response in if response != .OK{task.cancel();self.videoRenderWorker?.cancel()}}}
        }
        if let window{panel.beginSheetModal(for:window,completionHandler:save)}else{panel.begin(completionHandler:save)}
      }catch{self.error=error.localizedDescription}
    }
    if let window{settings.beginSheetModal(for:window,completionHandler:configure)}else{configure(settings.runModal())}
  }
}
// A detached worker transfers exclusive ownership to MainActor before publication.
final class PreparedVideoPublication:@unchecked Sendable {
  private let writer:AtomicFileWriter
  init(output:RenderedVideo,destination:URL)throws {
    writer=try AtomicFileWriter(to:destination,maximumBytes:output.bytes)
    let file=try FileHandle(forReadingFrom:output.url);defer{try? file.close()}
    while let bytes=try file.read(upToCount:AtomicFileWriter.chunkBytes),!bytes.isEmpty{try Task.checkCancellation();try writer.append(bytes)}
    guard writer.count==output.bytes else{throw CraftError.invalid("Video output changed before publication.")}
  }
  func discard(){writer.discard()}
  func commit()throws{try writer.commit()}
}
extension AppDelegate {
  @objc func renderVideo(){store?.presentRenderVideo()}
}
