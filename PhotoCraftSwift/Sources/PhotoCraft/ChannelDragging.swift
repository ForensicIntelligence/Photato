import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor enum ChannelDrag {
  nonisolated static let identifier = "ca.forensicintelligence.photato.channel-row"
  static let pasteboardType = NSPasteboard.PasteboardType(identifier)

  enum Destination {
    case trash, duplicate, canvas
    case reorder(SelectionChannelSource, after: Bool)
  }

  @MainActor private struct DocumentStamp {
    weak var store: EditorStore?
    weak var controller: CraftDocumentController?
    let documentID: UUID
    let session: UUID
    let generation: UUID
    let wasAttached: Bool

    init(_ store: EditorStore) {
      self.store = store
      documentID = store.document.id
      session = store.sessionGeneration
      generation = store.layerPanelGeneration
      controller = store.documentController
      wasAttached = controller != nil
    }

    var current: EditorStore? {
      guard let store, store.document.id == documentID, store.sessionGeneration == session,
        store.layerPanelGeneration == generation else { return nil }
      if wasAttached {
        guard let controller, store.documentController === controller,
          controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === store }) else {
          return nil
        }
      }
      return store
    }
  }

  private struct Capture {
    let stamp: DocumentStamp
    let source: SelectionChannelSource
    let token = UUID()
    var data: Data { Data(token.uuidString.utf8) }
  }

  private static var capture: Capture?

  static func provider(store: EditorStore, source: SelectionChannelSource) -> NSItemProvider {
    capture = nil
    let provider = NSItemProvider()
    guard store.canEditChannels, ChannelDuplication.sources(in: store.document).contains(source) else { return provider }
    let value = Capture(stamp: DocumentStamp(store), source: source)
    capture = value
    let data = value.data
    provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
      completion(data, nil)
      return nil
    }
    return provider
  }

  static func canReceive(_ destination: Destination, in target: EditorStore) -> Bool {
    guard let value = capture, let source = value.stamp.current, source.canEditChannels, target.canEditChannels else {
      return false
    }
    switch destination {
    case .trash:
      guard source === target else { return false }
      switch value.source {
      case .component(let index): return target.canDeleteProcessChannels([index])
      case .alpha(let id): return !LensBlurEngine.usesChannel(id, in: target.document)
      case .plate: return target.canEditInkChannels && target.document.inkChannelTargets.count > 1
      default: return false
      }
    case .duplicate:
      return source === target && ChannelDuplication.accepts(target.document, source: value.source, in: source.document)
    case .canvas:
      guard source !== target, let controller = source.documentController,
        target.documentController === controller, DocumentStamp(target).current != nil else { return false }
      return ChannelDuplication.accepts(target.document, source: value.source, in: source.document)
    case .reorder(let row, let after):
      return source === target && order(value.source, relativeTo: row, after: after, in: target) != nil
    }
  }

  private static func order(_ source: SelectionChannelSource, relativeTo row: SelectionChannelSource,
    after: Bool, in store: EditorStore) -> (UUID, Int)? {
    let ids: [UUID], sourceID: UUID, targetID: UUID
    switch (source, row) {
    case (.alpha(let a), .alpha(let b)):
      ids = (store.document.alphaChannels ?? []).map(\.id)
      (sourceID, targetID) = (a, b)
    case (.plate(let a), .plate(let b)):
      guard store.canEditInkChannels, case .multichannel(let raster) = store.document.inkMode else { return nil }
      ids = raster.plates.map(\.id)
      (sourceID, targetID) = (a, b)
    default: return nil
    }
    guard sourceID != targetID, let start = ids.firstIndex(of: sourceID), let row = ids.firstIndex(of: targetID) else { return nil }
    let insertion = row + (after ? 1 : 0)
    let end = start < insertion ? insertion - 1 : insertion
    return start == end ? nil : (sourceID, end)
  }

  static func receive(_ provider: NSItemProvider, destination: Destination, in target: EditorStore) async -> Bool {
    guard canReceive(destination, in: target), let token = capture?.token,
      provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
    let stamp = DocumentStamp(target)
    let data: Data? = await withCheckedContinuation { reply in
      _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
        reply.resume(returning: error == nil ? data : nil)
      }
    }
    guard !Task.isCancelled, let data, stamp.current === target, capture?.token == token else { return false }
    return receive(data, destination: destination, in: target)
  }

  static func receive(_ data: Data, destination: Destination, in target: EditorStore,
    activate: () -> Bool = { true }) -> Bool {
    guard let value = capture, data == value.data, canReceive(destination, in: target),
      activate(), capture?.token == value.token, canReceive(destination, in: target),
      let source = value.stamp.current else { return false }
    capture = nil
    do {
      switch destination {
      case .trash:
        switch value.source {
        case .component(let index): target.requestProcessChannelDeletion([index], immediate: true)
        case .alpha(let id): try target.executeEditorCommand(.channel(.delete(id)))
        case .plate(let id): target.performInkChannel(.delete(id))
        default: return false
        }
      case .reorder(let row, let after):
        guard let (id, position) = order(value.source, relativeTo: row, after: after, in: target) else { return false }
        if case .alpha = value.source { try target.executeEditorCommand(.channel(.move(id, position))) }
        else { target.performInkChannel(.move(id, position)) }
      case .duplicate, .canvas:
        duplicate(value, from: source, to: target)
      }
      return true
    } catch {
      target.error = error.localizedDescription
      return false
    }
  }

  private static func duplicate(_ value: Capture, from source: EditorStore, to target: EditorStore) {
    let original = source.document, destination = DocumentStamp(target)
    let sourceStamp = value.stamp, channel = value.source
    let name = channel.title(in: original) + (source === target ? " copy" : "")
    let sameDocument = source === target
    let previousAlpha = target.document.alphaChannels?.last?.id
    let previousInk = target.document.inkChannelTargets.last
    target.performPreparedGeometry(label: "Duplicate Channel", allowAuxiliary: true, prepare: { document in
      guard case .edit(let command, _) = try ChannelDuplication.prepare(channel, in: original, to: document, name: name) else {
        throw CraftError.invalid("The channel copy needs an open destination.")
      }
      return try PreparedEdit(command: command, document: document)
    }, validateCommit: {
      guard let source = sourceStamp.current, destination.current != nil, sameDocument || source.canEditChannels else {
        throw CraftError.invalid("A document changed or closed during the channel copy.")
      }
    }, onSuccess: { [weak target] in
      guard let target else { return }
      if let alpha = target.document.alphaChannels?.last?.id, alpha != previousAlpha {
        try? target.selectAlphaChannel(alpha)
      } else if let plate = target.document.inkChannelTargets.last, plate != previousInk {
        try? target.selectInkChannels([plate])
      }
    })
  }

  nonisolated static var capabilities: [String: Any] {
    [
      "duplicate": "Drag an individual channel to New Channel, or to another open image of matching dimensions. API equivalent: channel.duplicate.",
      "delete": "Drag an individual RGB, CMYK, Lab component, saved alpha, spot or removable Multichannel plate to the trash. API equivalents: channel.deleteProcess, channel.edit, ink.channel.manage.",
      "reorder": "Drag a saved alpha or spot among saved rows, or a Multichannel plate among its plates. API equivalents: channel.edit or ink.channel.manage with action move."
    ]
  }
}

@MainActor extension View {
  @ViewBuilder func channelDragSource(_ source: SelectionChannelSource?, store: EditorStore) -> some View {
    if let source, store.canEditChannels { onDrag { ChannelDrag.provider(store: store, source: source) } }
    else { self }
  }
}

@MainActor struct ChannelDropTarget: ViewModifier {
  let store: EditorStore
  let destination: ChannelDrag.Destination
  var rowHeight: CGFloat? = nil
  @State private var edge: VerticalEdge?

  func body(content: Content) -> some View {
    content.onDrop(of: [ChannelDrag.identifier], delegate: Delegate(
      store: store, destination: destination, rowHeight: rowHeight, edge: $edge))
      .overlay {
        if let edge {
          if rowHeight != nil {
            Rectangle().fill(Color.accentColor).frame(height: 2)
              .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
              .allowsHitTesting(false).accessibilityHidden(true)
          } else {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      }
  }

  @MainActor private struct Delegate: @preconcurrency DropDelegate {
    let store: EditorStore
    let destination: ChannelDrag.Destination
    let rowHeight: CGFloat?
    @Binding var edge: VerticalEdge?

    func validateDrop(info: DropInfo) -> Bool {
      guard info.itemProviders(for: [ChannelDrag.identifier]).count == 1 else { return false }
      if case .reorder(let row, _) = destination {
        return ChannelDrag.canReceive(.reorder(row, after: false), in: store)
          || ChannelDrag.canReceive(.reorder(row, after: true), in: store)
      }
      return ChannelDrag.canReceive(destination, in: store)
    }

    func dropExited(info: DropInfo) { edge = nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      let (operation, position) = intent(at: info.location.y)
      let valid = ChannelDrag.canReceive(operation, in: store)
      edge = valid ? position : nil
      if !valid { return DropProposal(operation: .cancel) }
      if case .duplicate = operation { return DropProposal(operation: .copy) }
      return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
      edge = nil
      let providers = info.itemProviders(for: [ChannelDrag.identifier])
      let (operation, _) = intent(at: info.location.y)
      guard providers.count == 1, let provider = providers.first, ChannelDrag.canReceive(operation, in: store) else { return false }
      Task { @MainActor in _ = await ChannelDrag.receive(provider, destination: operation, in: store) }
      return true
    }

    private func intent(at y: CGFloat) -> (ChannelDrag.Destination, VerticalEdge) {
      if let rowHeight, case .reorder(let row, _) = destination {
        let after = y >= rowHeight / 2
        return (.reorder(row, after: after), after ? .bottom : .top)
      }
      return (destination, .top)
    }
  }
}
