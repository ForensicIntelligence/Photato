import AppKit
import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct ImageSequenceOptions: Sendable {
  var prefix = "frame"
  var firstFrame = 0
  var lastFrame: Int?
  var startNumber = 0
  var digits = 4
  var useWorkArea = false
  func range(in document: CraftDocument) throws -> ClosedRange<Int> {
    let count = document.animation?.frames.count ?? document.videoTimeline?.durationFrames ?? 0
    let start:Int,end:Int
    if useWorkArea {
      guard let timeline=document.videoTimeline,firstFrame==0,lastFrame==nil else{throw CraftError.invalid("Work-area export requires a video Timeline without an explicit range.")}
      start=timeline.effectiveWorkArea.startFrame;end=timeline.effectiveWorkArea.endFrame-1
    }else{start=firstFrame;end=lastFrame ?? count-1}
    guard !prefix.isEmpty, prefix.utf8.count <= 64, prefix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_- ".unicodeScalars.contains($0) }),
      count > 0, start >= 0, end >= start, end < count, end-start < 4096,
      (0...999_999_999).contains(startNumber), (1...9).contains(digits), startNumber <= 999_999_999-(end-start) else { throw CraftError.invalid("Choose a safe filename prefix, valid frame range (at most 4096 frames), numbering and 1–9 digits.") }
    return start...end
  }
}
struct ImageSequenceOutput: Sendable {
  let files: [StoredZIP.File]
  var archive: Data?
  func zip() throws -> Data { try StoredZIP.encode(files,maximumBytes:ImageSequenceExport.maximumBytes) }
}
enum ImageSequenceExport {
  static let maximumBytes = 128*1024*1024
  static func render(_ document: CraftDocument, options: ImageSequenceOptions, maximumBytes: Int = maximumBytes) throws -> ImageSequenceOutput {
    try Task.checkCancellation();try document.validate();let range = try options.range(in:document)
    guard maximumBytes > 0, maximumBytes <= Self.maximumBytes else { throw CraftError.invalid("Invalid sequence output budget.") }
    var files: [StoredZIP.File] = [], frames: [[String:Any]] = [], total = 0
    var time = document.animation.map { $0.frames.prefix(range.lowerBound).reduce(0) { $0+$1.delay } } ?? Double(range.lowerBound)/(document.videoTimeline?.frameRate ?? 1)
    for (offset,index) in range.enumerated() {
      try Task.checkCancellation()
      let frame: CraftDocument, duration: Double
      if let animation = document.animation { frame = try document.animationDocument(at:animation.frames[index].id);duration = animation.frames[index].delay }
      else { frame = try document.videoDocument(at:index);duration = 1/document.videoTimeline!.frameRate }
      let number = String(options.startNumber+offset), name = options.prefix + String(repeating:"0",count:max(0,options.digits-number.count)) + number + ".png"
      let bytes = try DocumentIO.encode(frame,format:.png)
      guard bytes.count <= maximumBytes-total else { throw CraftError.invalid("Image sequence exceeds 128 MiB.") }
      total += bytes.count;files.append(.init(name:name,data:bytes))
      frames.append(["file":name,"sourceFrame":index,"time":time,"duration":duration]);time += duration
    }
    let metadata: [String:Any] = ["format":"photato-image-sequence","version":1,"sourceName":document.name,"kind":document.animation == nil ? "video":"frameAnimation","width":document.width,"height":document.height,"sourceDepth":document.depth.rawValue,"pngBitsPerChannel":document.depth == .u8 ? 8:16,"colorPolicy":document.depth == .f32 ? "HDR converted to SDR sRGB16 by the native PNG encoder":"Working ICC profile retained","frameRate":document.videoTimeline?.frameRate as Any? ?? NSNull(),"loopCount":(document.animation?.loopCount ?? document.videoTimeline?.finiteLoopCount) as Any? ?? NSNull(),"videoLooping":document.videoTimeline?.looping as Any? ?? NSNull(),"firstFrame":range.lowerBound,"lastFrame":range.upperBound,"frames":frames]
    let manifest = try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys,.prettyPrinted])
    guard manifest.count <= maximumBytes-total else { throw CraftError.invalid("Sequence manifest exceeds the output budget.") }
    files.append(.init(name:"sequence.json",data:manifest));try Task.checkCancellation();return ImageSequenceOutput(files:files)
  }
}
struct PreparedSequenceFolder: Sendable {
  let staging: URL
  let destination: URL
  static func prepare(_ output: ImageSequenceOutput, destination: URL) throws -> Self {
    guard destination.isFileURL else { throw CraftError.invalid("Choose a local export folder.") }
    try Task.checkCancellation()
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".photato-sequence-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false)
    do {
      for file in output.files {
        try Task.checkCancellation()
        let writer = try AtomicFileWriter(to:staging.appendingPathComponent(file.name),maximumBytes:ImageSequenceExport.maximumBytes)
        try writer.append(file.data);try writer.commit()
      }
      try Task.checkCancellation();return Self(staging:staging,destination:destination)
    } catch { try? FileManager.default.removeItem(at:staging);throw error }
  }
  func commit() throws {
    try Task.checkCancellation()
    let result = staging.withUnsafeFileSystemRepresentation { from in destination.withUnsafeFileSystemRepresentation { to in Darwin.renamex_np(from,to,UInt32(RENAME_EXCL)) } }
    guard result == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"Could not publish the sequence folder. Choose a new folder name; existing destinations are never replaced."]) }
  }
  func discard() { try? FileManager.default.removeItem(at:staging) }
}
extension EditorStore {
  func encodedImageSequence(_ options: ImageSequenceOptions, archive: Bool = false) async throws -> ImageSequenceOutput {
    guard canUseTimeline, timelineTask == nil, sequenceExportID == nil else { throw CraftError.invalid("Stop playback and finish the current edit before export.") }
    _ = try options.range(in:document)
    let snapshot = document, generation = layerPanelGeneration, operation = UUID()
    sequenceExportID = operation;geometryBusy = true;status = "Rendering image sequence…"
    let worker = Task.detached(priority:.userInitiated) { var output = try ImageSequenceExport.render(snapshot,options:options);if archive { output.archive = try output.zip() };return output };sequenceExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel:{worker.cancel()} };geometryTask = observer
    var completed = false
    defer { if sequenceExportID == operation { sequenceExportID = nil;sequenceExportWorker = nil;if layerPanelGeneration == generation { geometryBusy = false;geometryTask = nil };status = completed ? "Image sequence rendered" : "Image sequence export stopped" } }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
    try Task.checkCancellation();guard !worker.isCancelled,!observer.isCancelled,document == snapshot,layerPanelGeneration == generation else { throw CancellationError() };completed = true;return output
  }
  func presentImageSequenceExport() {
    guard canUseTimeline,document.animation != nil || document.videoTimeline != nil else { return }
    stopTimelinePlayback();let snapshot = document,generation = layerPanelGeneration
    let count = snapshot.animation?.frames.count ?? snapshot.videoTimeline!.durationFrames
    let prefix = NSTextField(string:"frame"),first = NSTextField(string:"1"),last = NSTextField(string:String(count)),start = NSTextField(string:"0"),digits = NSTextField(string:"4")
    let area=NSButton(checkboxWithTitle:"Use work area",target:nil,action:nil);area.isEnabled=snapshot.videoTimeline != nil
    let grid = NSGridView(views:zip(["Filename prefix:","First frame:","Last frame:","Starting number:","Digits:",""],[prefix,first,last,start,digits,area] as [NSView]).map{[NSTextField(labelWithString:$0),$1]});grid.rowSpacing = 8;grid.columnSpacing = 12
    [prefix,first,last,start,digits].forEach{$0.widthAnchor.constraint(equalToConstant:180).isActive = true}
    grid.setFrameSize(grid.fittingSize)
    let panel = NSOpenPanel();panel.title = "Export Image Sequence";panel.prompt = "Export";panel.canChooseDirectories = true;panel.canChooseFiles = false;panel.canCreateDirectories = true;panel.accessoryView = grid
    panel.message = "Creates a new <prefix>-sequence folder with PNG frames and timing metadata. Existing folders are preserved. Frame range is numbered from 1. HDR exports convert to SDR sRGB16."
    let window = NSApp.keyWindow
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let self, let parent = panel.url else { return }
      guard self.canUseTimeline,self.document == snapshot,self.layerPanelGeneration == generation,let a = Int(area.state == .on ? "1":first.stringValue),let b = Int(area.state == .on ? "1":last.stringValue),let n = Int(start.stringValue),let d = Int(digits.stringValue),a > 0,b > 0 else { self.error = "Choose valid settings and finish other document edits.";return }
      let options = ImageSequenceOptions(prefix:prefix.stringValue,firstFrame:area.state == .on ? 0:a-1,lastFrame:area.state == .on ? nil:b-1,startNumber:n,digits:d,useWorkArea:area.state == .on)
      do { _ = try options.range(in:snapshot) } catch { self.error = error.localizedDescription;return }
      let destination = parent.appendingPathComponent(options.prefix+"-sequence",isDirectory:true)
      let progress = NSAlert();progress.messageText = "Exporting Image Sequence";progress.informativeText = "Rendering PNG frames…";progress.addButton(withTitle:"Cancel")
      let task = Task { @MainActor in
        let scoped = parent.startAccessingSecurityScopedResource();defer { if scoped { parent.stopAccessingSecurityScopedResource() };if let window = progress.window.sheetParent { window.endSheet(progress.window,returnCode:.OK) } }
        do {
          let output = try await self.encodedImageSequence(options)
          let worker = Task.detached(priority:.userInitiated) { try PreparedSequenceFolder.prepare(output,destination:destination) }
          let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()};defer { prepared.discard() }
          guard self.document == snapshot,self.layerPanelGeneration == generation else { throw CancellationError() };try Task.checkCancellation();try prepared.commit();self.status = "Exported \(output.files.count-1) PNG frames"
        } catch is CancellationError { self.status = "Image sequence export cancelled" }
        catch { self.error = error.localizedDescription }
      }
      if let window { progress.beginSheetModal(for:window) { response in if response != .OK { task.cancel();self.sequenceExportWorker?.cancel() } } }
    }
    if let window { panel.beginSheetModal(for:window,completionHandler:finish) } else { panel.begin(completionHandler:finish) }
  }
}
