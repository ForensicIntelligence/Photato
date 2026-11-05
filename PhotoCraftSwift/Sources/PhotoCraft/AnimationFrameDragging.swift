import AppKit
import SwiftUI
import PhotoCraftCore

/// The drag contains only a process-local token. Frame content stays in the document.
@MainActor enum AnimationFrameDrag {
  nonisolated static let identifier = "ca.forensicintelligence.photato.animation-frame"
  private static let prefix = "photato-frame-v1:"
  @MainActor private final class Capture {
    weak var store: EditorStore?
    weak var controller: CraftDocumentController?
    let attached: Bool
    let token = UUID()
    let documentID: UUID
    let session: UUID
    let panel: UUID
    let frameID: UUID
    init(_ store: EditorStore, frameID: UUID) {
      self.store = store; controller = store.documentController; attached = controller != nil
      documentID = store.document.id; session = store.sessionGeneration
      panel = store.timelinePanelGeneration; self.frameID = frameID
    }
  }
  private static var capture: Capture?
  static func cancel(store: EditorStore) {
    if capture?.store === store { capture = nil }
  }
  static func operation(_ modifiers: NSEvent.ModifierFlags) -> DropOperation { .move }
  private static func current(_ store: EditorStore) -> Capture? {
    guard let value = capture, value.store === store, store.timelineVisible,
      store.canUseTimeline, store.timelineTask == nil,
      value.documentID == store.document.id, value.session == store.sessionGeneration,
      value.panel == store.timelinePanelGeneration,
      store.document.animation?.selectedFrameID == value.frameID else { return nil }
    if value.attached {
      guard let controller = value.controller, store.documentController === controller,
        controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === store }) else { return nil }
    }
    return value
  }
  static func provider(store: EditorStore, frameID: UUID) -> NSItemProvider {
    capture = nil
    let provider = NSItemProvider()
    guard store.timelineVisible, store.canUseTimeline, store.timelineTask == nil,
      store.document.animation?.frames.contains(where: { $0.id == frameID }) == true else { return provider }
    do {
      if store.document.animation?.selectedFrameID != frameID { try store.selectTimelineFrame(frameID) }
      let value = Capture(store, frameID: frameID); capture = value
      let data = Data((prefix + value.token.uuidString).utf8)
      provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
        completion(data, nil); return nil
      }
    } catch { store.error = error.localizedDescription }
    return provider
  }
  /// Insertion edges become the existing command's final zero-based frame index.
  static func destination(store: EditorStore, target: UUID, after: Bool) -> Int? {
    guard let value = current(store), let frames = store.document.animation?.frames,
      let sourceIndex = frames.firstIndex(where: { $0.id == value.frameID }),
      let targetIndex = frames.firstIndex(where: { $0.id == target }) else { return nil }
    let insertion = targetIndex + (after ? 1 : 0)
    let result = insertion - (sourceIndex < insertion ? 1 : 0)
    return result == sourceIndex ? nil : result
  }
  static func receive(_ provider: NSItemProvider, store: EditorStore, target: UUID, after: Bool) async -> Bool {
    guard destination(store: store, target: target, after: after) != nil,
      let expected = current(store)?.token, provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
        continuation.resume(returning: error == nil ? data : nil)
      }
    }
    guard !Task.isCancelled, let data, data.count <= 96,
      String(data: data, encoding: .utf8) == prefix + expected.uuidString,
      current(store)?.token == expected,
      let index = destination(store: store, target: target, after: after),
      let animation = store.document.animation else { return false }
    var order = animation.frames.map(\.id)
    let moved = order.remove(at: animation.selectedIndex); order.insert(moved, at: index)
    capture = nil
    store.editTimeline(.reorder(index))
    return store.document.animation?.frames.map(\.id) == order
  }
  nonisolated static var apiCapabilities: [String: Any] {
    ["command": "animation.edit", "operation": "reorder", "parameter": "index (final zero-based position)",
     "selection": "animation.view frameID selects the source without adding content history. Native thumbnail dragging selects its source, then uses the same reorder command as the arrows.",
     "native": "Drop on the left or right half of a thumbnail to insert before or after it. An insertion line previews that edge. One native Undo retains frame IDs, delays, layer states, content and selected-frame appearance.",
     "modifiers": "Single-frame move only. Every modifier combination proposes and dispatches move; no duplicate or multi-frame action is advertised.",
     "guards": "Private own-process non-content token; captured document/session/panel lifetime and weak document ownership. Reject stale, closed, hidden, superseded, cancelled, busy, playing, foreign, malformed, multiple-provider and no-op drops.",
     "limits": "Full multi-frame/duplicate modifier behavior, auto-scroll, physical system feedback and exact current Photoshop defaults/output/platform fidelity remain open. Semantic animation Action recording remains unavailable. No new command, Adobe route, archive or Actions version."]
  }
}

@MainActor struct AnimationFrameDropDelegate: @preconcurrency DropDelegate {
  let store: EditorStore
  let target: UUID
  let width: CGFloat
  @Binding var highlightedAfter: Bool?
  private func after(_ info: DropInfo) -> Bool { info.location.x >= width / 2 }
  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [AnimationFrameDrag.identifier])
      && info.itemProviders(for: [AnimationFrameDrag.identifier]).count == 1
      && AnimationFrameDrag.destination(store: store, target: target, after: after(info)) != nil
  }
  func dropEntered(info: DropInfo) { highlightedAfter = validateDrop(info: info) ? after(info) : nil }
  func dropExited(info: DropInfo) { highlightedAfter = nil }
  func dropUpdated(info: DropInfo) -> DropProposal? {
    highlightedAfter = validateDrop(info: info) ? after(info) : nil
    return DropProposal(operation: highlightedAfter == nil ? .cancel : AnimationFrameDrag.operation(NSEvent.modifierFlags))
  }
  func performDrop(info: DropInfo) -> Bool {
    guard validateDrop(info: info), let provider = info.itemProviders(for: [AnimationFrameDrag.identifier]).first else { return false }
    let after = after(info); highlightedAfter = nil
    Task { @MainActor in _ = await AnimationFrameDrag.receive(provider, store: store, target: target, after: after) }
    return true
  }
}

@MainActor struct AnimationFrameDropTarget: ViewModifier {
  let store: EditorStore
  let frameID: UUID
  @State private var width: CGFloat = 84
  @State private var highlightedAfter: Bool?
  func body(content: Content) -> some View {
    content.background {
      GeometryReader { geometry in
        Color.clear.onAppear { width = geometry.size.width }
          .onChange(of: geometry.size.width) { _, value in width = value }
      }
    }
    .onDrag { AnimationFrameDrag.provider(store: store, frameID: frameID) }
    .onDrop(of: [AnimationFrameDrag.identifier], delegate: AnimationFrameDropDelegate(
      store: store, target: frameID, width: width, highlightedAfter: $highlightedAfter))
    .overlay {
      if let after = highlightedAfter {
        HStack(spacing: 0) {
          if after { Spacer(minLength: 0) }
          Rectangle().fill(Color.accentColor).frame(width: 2)
          if !after { Spacer(minLength: 0) }
        }.allowsHitTesting(false)
      }
    }
    .onChange(of: store.sessionGeneration) { _, _ in highlightedAfter = nil }
    .onChange(of: store.timelinePanelGeneration) { _, _ in highlightedAfter = nil }
  }
}
