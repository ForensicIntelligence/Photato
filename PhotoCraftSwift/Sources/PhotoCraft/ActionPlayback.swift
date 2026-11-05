import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func recordClipboardCopy(ids: Set<UUID>, merged: Bool) {
    guard session.actionRecording != nil else { return }
    let targets = merged ? [] : document.layers.filter { ids.contains($0.id) }.map { ActionLayerTarget($0.id, in: document) }
    session.recordActionOperation(.clipboardCopy(targets, merged: merged), name: merged ? "Copy Merged" : "Copy")
    actionRevision += 1
  }
  func playPreparedAction(_ action: RecordedAction) {
    do {
      try action.validate()
      if try applyLayerSelectionAction(action) { status = "Play \(action.name)"; return }
      let original = document, generation = layerPanelGeneration
      let clipboardRevision = clipboard.changeCount
      let input = try action.requiresInitialClipboard ? clipboard.read() : nil
      let masterDocuments = action.usesMasterPalette || action.usesExternalRetouchSources ? NSDocumentController.shared.documents.compactMap { $0 as? CraftNSDocument }
        .filter { $0.store.document.id != original.id && (action.usesExternalRetouchSources || ($0.store.document.depth == .u8 && [.rgb, .grayscale].contains($0.store.document.colorMode))) } : []
      let masters = masterDocuments.map { $0.store.document }
      geometryBusy = true; renderTask?.cancel(); status = "Play \(action.name)"
      geometryTask = Task { [weak self] in
        let worker = Task.detached(priority: .userInitiated) {
          let result = try RecordedActionRenderer.prepare(action, in: original, clipboard: input?.decoded(), masters: masters)
          return (try PreparedEdit(command: result.command, document: original), try result.clipboard.map(ClipboardRepresentations.init), result.lastIndexedPalette)
        }
        do {
          let (prepared, output, lastPalette) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard let self, self.layerPanelGeneration == generation else { return }
          guard self.document == original else { throw CraftError.invalid("The document changed during Actions playback.") }
          if action.requiresInitialClipboard || action.writesClipboard {
            guard self.clipboard.changeCount == clipboardRevision else { throw CraftError.invalid("The clipboard changed during Actions playback.") }
          }
          for (index, master) in masterDocuments.enumerated() {
            guard NSDocumentController.shared.documents.contains(where: { $0 === master }), master.store.document == masters[index] else {
              throw CraftError.invalid("A master palette source changed or closed during Actions playback.")
            }
          }
          // Validate the history transaction before publishing clipboard side effects.
          var candidate = self.session; try candidate.executePrepared(prepared)
          if let output { try self.clipboard.write(output) }
          try self.executeCompositePreparedEdit(prepared)
          self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
          if let lastPalette { self.previousIndexedPalette = lastPalette }
          if self.document != original { self.onChange?(.changeDone) }
          self.status = prepared.label
        } catch is CancellationError {
          if self?.layerPanelGeneration == generation { self?.status = "Operation cancelled" }
        } catch {
          if self?.layerPanelGeneration == generation { self?.error = error.localizedDescription }
        }
        guard let self, self.layerPanelGeneration == generation else { return }
        self.geometryBusy = false; self.render()
      }
    } catch { self.error = error.localizedDescription }
  }
}
