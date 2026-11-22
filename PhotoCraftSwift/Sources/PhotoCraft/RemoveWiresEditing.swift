import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canRemoveWires: Bool {
    canUseRemoveTarget && removeSettings.mode != .generativeOn && removeDraft == nil && removeStroke == nil && removeApplying == nil
      && removeDetectionID == nil && removeWiresID == nil
  }

  func removeWiresAndCables() {
    guard canRemoveWires, let layerID = activeLayer?.id else { return }
    let id = UUID(), prepare = removeWiresPreparation, settings = removeSettings
    let original = document
    removeWiresID = id
    performPreparedGeometry(label: "Removing wires and cables…", prepare: { source in
      let result = try prepare(source, layerID, settings)
      return try PreparedEdit(command: .regionRetouch(result.edit), document: source)
    }, validateCommit: { [weak self] in
      guard self?.removeWiresID == id else { throw CancellationError() }
    }, onCommit: { [weak self] prepared in
      guard let self else { return }
      if self.document != original {
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
      }
      self.status = prepared.label
    })
    let processing = geometryTask
    removeCompletionTask = Task { [weak self] in
      await processing?.value
      if self?.removeWiresID == id { self?.removeWiresID = nil }
    }
  }
}
