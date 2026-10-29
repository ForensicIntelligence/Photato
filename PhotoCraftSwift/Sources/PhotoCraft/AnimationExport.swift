import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  /// UI and API share this cancellable snapshot encoder. Encoding adds no history.
  func encodedAnimation(alphaThreshold: Double = 0.5) async throws -> Data {
    guard canUseTimeline, timelineTask == nil, animationExportID == nil else { throw CraftError.invalid("Stop playback and finish the current edit before export.") }
    let snapshot = document, operation = UUID(), generation = layerPanelGeneration
    animationExportID = operation; geometryBusy = true; status = "Exporting animated GIF…"
    let worker = Task.detached(priority: .userInitiated) { try AnimationGIF.encode(snapshot, alphaThreshold: alphaThreshold) }
    animationExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    geometryTask = observer
    var completed = false
    defer {
      if animationExportID == operation {
        animationExportWorker = nil; animationExportID = nil
        if !completed { status = "Animation export stopped" }
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let bytes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == snapshot, layerPanelGeneration == generation else { throw CancellationError() }
    completed = true
    return bytes
  }
  func presentAnimationExport() {
    guard canUseTimeline, document.animation != nil else { return }
    stopTimelinePlayback()
    let snapshot = document
    let panel = NSSavePanel(); panel.title = "Export Animated GIF"; panel.allowedContentTypes = [.gif]
    panel.nameFieldStringValue = snapshot.name + ".gif"
    panel.message = "Exports every Timeline frame. GIF uses up to 256 colors, one-bit transparency and delays rounded to 0.01 seconds. Your editable document stays unchanged."
    let window = NSApp.keyWindow
    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let self, let url = panel.url else { return }
      guard self.canUseTimeline, self.document == snapshot else { self.error = "The document changed while choosing the export file."; return }
      let progress = NSAlert(); progress.messageText = "Exporting Animated GIF"; progress.informativeText = "Rendering all Timeline frames…"; progress.addButton(withTitle: "Cancel")
      let task = Task { @MainActor in
        defer { if let parent = progress.window.sheetParent { parent.endSheet(progress.window, returnCode: .OK) } }
        do {
          let bytes = try await self.encodedAnimation()
          try Task.checkCancellation()
          // Cancellation is checked before atomic commit; a failed export preserves the destination.
          try AnimationExport.write(bytes, to: url)
          self.status = "Exported animated GIF"
        } catch is CancellationError { self.status = "Animation export cancelled" }
        catch { self.error = error.localizedDescription }
      }
      if let window {
        progress.beginSheetModal(for: window) { response in if response != .OK { task.cancel(); self.animationExportWorker?.cancel() } }
      }
    }
    if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
    else { panel.begin(completionHandler: completion) }
  }
}
enum AnimationExport {
  static func write(_ bytes: Data, to url: URL) throws {
    let writer = try AtomicFileWriter(to: url, maximumBytes: AnimationGIF.maximumOutputBytes)
    try writer.append(bytes); try Task.checkCancellation(); try writer.commit()
  }
}
extension AutomationService {
  func exportAnimation(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting an animation.") }
    guard try command.string("format") == "gif" else { throw AutomationFailure(status: 400, message: "Animation export currently supports gif.") }
    let threshold = try command.parameters["alphaThreshold"] == nil ? 0.5 : command.number("alphaThreshold", range: 0...1)
    let snapshot = document.store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let bytes = try await document.store.encodedAnimation(alphaThreshold: threshold)
    prune()
    guard isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == shareID && $0.document === document }),
      document.store.document == snapshot, revision(document.store) == command.revision else {
      throw AutomationFailure(status: 409, message: "Animation export was revoked or its source changed.")
    }
    document.store.status = "Exported animated GIF"
    return .init(status: 200, contentType: "image/gif", body: bytes)
  }
}
