import Foundation
import PhotoCraftImaging
import PhotoCraftCore

enum RemoveMarkPreview {
  static func encode(_ request: RemoveRequest, _ source: CraftDocument) throws -> String {
    let mask = try RemovePreparation.markCoverage(request,in:source)
    try Task.checkCancellation(); let bytes = try mask.bytes
    try Task.checkCancellation(); return Data(bytes).base64EncodedString()
  }
}

extension AutomationService {
  func previewRemoveMarks(document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Allow document transfers before reading removal coverage.") }
    let store = document.store
    guard let draft = store.removeDraft, draft.hasMarks, store.removeSourceMatches(draft), store.removeStroke == nil else {
      throw AutomationFailure(status:409,message:"There are no current removal marks to preview.")
    }
    let expected = revision(store), expectedToken = token, expectedGeneration = generation
    let request = draft.request, source = draft.original
    let prepare = store.removePreviewPreparation
    let worker = Task.detached(priority:.userInitiated) { try prepare(request,source) }
    let encoded = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard isRunning, token == expectedToken, generation == expectedGeneration, documentTransfersEnabled,
      shares.contains(where: { $0.id == shareID && $0.document === document }), revision(store) == expected,
      store.removeSourceMatches(draft) else { throw AutomationFailure(status:409,message:"Removal marks, source, sharing or permissions changed during preview.") }
    return .json(["revision":expected,"removeTool":RemoveToolAPI.state(store),
      "removalMask":["width":source.width,"height":source.height,"coverageBase64":encoded,
        "meaning":"marksBeforeDocumentSelection"]])
  }
}
