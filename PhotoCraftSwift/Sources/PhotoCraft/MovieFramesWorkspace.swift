import AppKit
import AVKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedMovieFramesSource: Sendable {
  let data: Data,name: String,url: URL,info: MovieFrameInfo
  static func prepare(_ source: URL) throws -> Self {
    let file = try FileHandle(forReadingFrom:source);defer {try? file.close()}
    var data = Data()
    while true {
      try Task.checkCancellation()
      guard let bytes = try file.read(upToCount:min(1_048_576,MovieSource.maximumBytes+1-data.count)),!bytes.isEmpty else {break}
      data.append(bytes);guard data.count <= MovieSource.maximumBytes else {throw CraftError.invalid("Choose a movie up to64MiB.")}
    }
    guard MovieIO.recognizes(data) else {throw CraftError.invalid("Choose a supported MOV or MP4 movie.")}
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photato-frame-preview-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    do {
      let url = directory.appendingPathComponent("source.mov");try data.write(to:url,options:.atomic)
      let info = try MovieFrames.info(url);try Task.checkCancellation()
      return Self(data:data,name:source.deletingPathExtension().lastPathComponent,url:url,info:info)
    } catch {try? FileManager.default.removeItem(at:directory);throw error}
  }
  func discard() {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
}
@MainActor @Observable final class MovieFramesWorkspace {
  weak var controller: CraftDocumentController?
  var source: PreparedMovieFramesSource?
  var options = MovieFrameImportOptions()
  var loading = false
  var busy = false
  var closed = false
  var error: String?
  var created: CraftNSDocument?
  @ObservationIgnored var player: AVPlayer?
  @ObservationIgnored var panel: NSOpenPanel?
  @ObservationIgnored var loadTask: Task<Void,Never>?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var worker: Task<CraftDocument,Error>?
  @ObservationIgnored var didImport: (() -> Void)?
  init(controller: CraftDocumentController) {self.controller = controller}
  func choose() {
    guard !loading,!busy,!closed,panel == nil else {return}
    let panel = NSOpenPanel();self.panel = panel;panel.title = "Import Video To Layers";panel.allowedContentTypes = [.quickTimeMovie,.mpeg4Movie];panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in guard let self else{return};self.panel = nil;if response == .OK,let url = panel.url {self.load(url)}}
  }
  func load(_ url: URL) {
    guard !loading,!busy,!closed else{return};loading = true;error = nil
    loadTask = Task { [weak self] in
      guard let self else{return};defer {self.loading = false}
      let scoped = url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
      do {
        let worker = Task.detached(priority:.userInitiated) {try PreparedMovieFramesSource.prepare(url)}
        let prepared = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        guard !Task.isCancelled,!self.closed else {prepared.discard();throw CancellationError()}
        self.player?.pause();self.player?.replaceCurrentItem(with:nil);self.source?.discard()
        self.source = prepared;self.options.start = 0;self.options.end = prepared.info.duration
        let asset = AVURLAsset(url:prepared.url,options:[AVURLAssetReferenceRestrictionsKey:UInt(0xffff)])
        self.player = AVPlayer(playerItem:AVPlayerItem(asset:asset))
      } catch is CancellationError {} catch {self.error = error.localizedDescription}
    }
  }
  func seekStart() {
    guard !loading,!busy,options.selectedRange,let source,options.start.isFinite,options.start >= 0,options.start <= source.info.duration else{return}
    player?.seek(to:CMTime(seconds:options.start,preferredTimescale:1_000_000),toleranceBefore:.zero,toleranceAfter:.zero)
  }
  func cancelImport() {task?.cancel();worker?.cancel()}
  func close() {
    closed = true;loadTask?.cancel();cancelImport();panel?.cancel(nil);panel = nil
    player?.pause();player?.replaceCurrentItem(with:nil);player = nil;source?.discard();source = nil
  }
  func run(display: Bool = true) {
    guard !closed,!loading,!busy,let source,let controller else{return}
    do {try options.validate();guard controller.canFinishMovieFrames else{throw CraftError.invalid("Finish document opening, closing or recovery before importing frames.")}} catch {self.error = error.localizedDescription;return}
    let options = options,opening = controller.documentOpening.generation,closing = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    busy = true;error = nil;player?.pause()
    task = Task { [weak self] in
      guard let self else{return};defer {self.busy = false;self.worker = nil}
      do {
        let worker = Task.detached(priority:.userInitiated) {try MovieFrames.decode(source.data,name:source.name,options:options)};self.worker = worker
        let model = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard !self.closed,controller.movieFramesWorkspace === self,controller.canFinishMovieFrames,controller.documentOpening.generation == opening,controller.documentClosing.state?.id == closing,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else {throw CraftError.invalid("Document state changed. Import the movie frames again.")}
        let document = CraftNSDocument(model:model);controller.addDocument(document);document.updateChangeCount(.changeDone);document.store.timelineVisible = model.animation != nil
        if display {document.makeWindowControllers();document.showWindows()}
        self.created = document;self.didImport?()
      } catch is CancellationError {self.error = "Frame import cancelled."} catch {self.error = error.localizedDescription}
    }
  }
}
