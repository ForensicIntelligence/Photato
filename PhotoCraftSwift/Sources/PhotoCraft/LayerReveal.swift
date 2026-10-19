import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

/// Persisted document IDs can be shared by separately opened copies. A read/revert
/// within the same store also starts a new panel observation scope.
struct LayerRevealObservation: Equatable {
  let storeID: UUID
  let generation: UUID
  let documentID: UUID
  let activeID: UUID?

  @MainActor init(_ store: EditorStore) {
    storeID = store.identity
    generation = store.layerPanelGeneration
    documentID = store.document.id
    activeID = store.document.activeLayerID
  }

  func sameDocument(as other: Self) -> Bool {
    storeID == other.storeID && generation == other.generation && documentID == other.documentID
  }
}

@MainActor @Observable final class LayerRevealTracker {
  struct Request: Equatable {
    let token = UUID()
    let observation: LayerRevealObservation
    let layerID: UUID
    let nameDraftID: UUID?
  }
  private var seen: LayerRevealObservation?
  private var pending: Request?
  private var isVisible = false
  var currentRequest: Request? { pending }

  func appear(_ store: EditorStore) -> Request? {
    WorkspaceLayoutDiagnostics.log("reveal.appear")
    isVisible = true
    let selection = track(store)
    // Rename can reveal the panel without changing the active layer. Its explicit
    // request must still expose the editor when this is the first panel frame.
    return rename(store) ?? selection
  }
  func end() {
    isVisible = false
    pending = nil
  }
  func track(_ store: EditorStore) -> Request? {
    guard isVisible else { return nil }
    let now = LayerRevealObservation(store)
    let before = seen
    seen = now
    pending = nil
    guard let before, now.sameDocument(as: before), now.activeID != before.activeID,
      let id = now.activeID, store.canBeginLayerCreation,
      store.document.layers.contains(where: { $0.id == id })
    else { return nil }
    let closed = Set(
      store.document.ancestors(of: id).filter { $0.group?.expanded == false }.map(\.id))
    // Disclosure is view metadata. It must not add dirty/history or render work.
    do {
      if !closed.isEmpty { try store.session.setGroupExpansion(closed, expanded: true) }
    } catch {
      store.error = error.localizedDescription
      return nil
    }
    return prepare(
      id, store: store,
      nameDraftID: store.layerNameDraft?.layerID == id ? store.layerNameDraft?.id : nil)
  }
  func rename(_ store: EditorStore) -> Request? {
    guard isVisible, let draft = store.layerNameDraft,
      draft.layerID == store.document.activeLayerID
    else {
      return nil
    }
    return prepare(draft.layerID, store: store, nameDraftID: draft.id)
  }
  private func prepare(_ id: UUID, store: EditorStore, nameDraftID: UUID? = nil) -> Request {
    let request = Request(
      observation: LayerRevealObservation(store), layerID: id, nameDraftID: nameDraftID)
    pending = request
    WorkspaceLayoutDiagnostics.log(
      "reveal.prepare",
      [
        "token": request.token.uuidString,
        "layer": id.uuidString, "draft": nameDraftID?.uuidString ?? "",
      ])
    return request
  }
  func consume(_ request: Request, store: EditorStore, visibleIDs: [UUID]) -> Bool {
    WorkspaceLayoutDiagnostics.log(
      "reveal.consume",
      [
        "token": request.token.uuidString,
        "pending": pending?.token.uuidString ?? "", "visible": isVisible,
        "canBegin": store.canBeginLayerCreation,
        "sameObservation": request.observation == LayerRevealObservation(store),
        "inList": visibleIDs.contains(request.layerID),
        "draft": store.layerNameDraft?.id.uuidString ?? "",
      ])
    guard isVisible, pending == request else { return false }
    let valid = canConsume(request, store: store, visibleIDs: visibleIDs)
    pending = nil
    return valid
  }
  func canConsume(_ request: Request, store: EditorStore, visibleIDs: [UUID]) -> Bool {
    isVisible && pending == request && request.observation == LayerRevealObservation(store)
      && store.canBeginLayerCreation && visibleIDs.contains(request.layerID)
      && (request.nameDraftID == nil || request.nameDraftID == store.layerNameDraft?.id)
  }
}
