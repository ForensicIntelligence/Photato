import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum DuplicateDestination: Hashable {
  case document(UUID)
  case newDocument
}
struct DuplicateDocumentOption: Identifiable {
  let id: UUID
  let name: String
  let original: CraftDocument
}

@MainActor @Observable final class DuplicateLayerDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let selected: Set<UUID>
  let sourceIdentity: UUID
  let roots: [Layer]
  let documents: [DuplicateDocumentOption]
  let canCreateDocument: Bool
  var destination: DuplicateDestination
  var name: String
  var documentName: String
  var error: String?
  var processing = false
  init(store: EditorStore, roots: [Layer], documents: [DuplicateDocumentOption]) {
    original = store.document
    selected = store.groupSelectionIDs
    sourceIdentity = store.identity
    self.roots = roots
    self.documents = documents
    canCreateDocument = store.documentController != nil
    destination = .document(store.identity)
    name = roots.first!.name + " copy"
    documentName = store.documentController?.nextUntitledName ?? "Untitled-1"
  }
  var title: String {
    "Duplicate "
      + (roots.allSatisfy(\.isGroup)
        ? (roots.count == 1 ? "Group" : "Groups") : (roots.count == 1 ? "Layer" : "Layers"))
  }
  var valid: Bool {
    (roots.count != 1 || (try? LayerDuplication.validateName(name)) != nil)
      && (destination != .newDocument || (try? LayerDuplication.validateName(documentName)) != nil)
  }
  func changedDestination(from old: DuplicateDestination) {
    guard roots.count == 1 else { return }
    let oldDefault = roots[0].name + (old == .document(sourceIdentity) ? " copy" : "")
    if name == oldDefault {
      name = roots[0].name + (destination == .document(sourceIdentity) ? " copy" : "")
    }
  }
}

private enum DuplicateResult: Sendable {
  case existing(PreparedEdit)
  case newDocument(CraftDocument)
}

extension EditorStore {
  var duplicateRoots: [Layer] {
    (try? LayerDuplication.roots(in: document, selected: groupSelectionIDs)) ?? []
  }
  var canBeginDuplicate: Bool { canBeginLayerCreation && !duplicateRoots.isEmpty }
  var duplicateMenuTitle: String {
    let roots = duplicateRoots
    return "Duplicate "
      + (!roots.isEmpty && roots.allSatisfy(\.isGroup)
        ? (roots.count == 1 ? "Group…" : "Groups…") : (roots.count > 1 ? "Layers…" : "Layer…"))
  }
  func beginDuplicate(contextLayer: UUID? = nil) {
    finishLayerName()
    guard canBeginLayerCreation else { return }
    if let contextLayer, !groupSelectionIDs.contains(contextLayer) { select(contextLayer) }
    guard canBeginDuplicate else { return }
    var documents =
      documentController?.documents.compactMap { item -> DuplicateDocumentOption? in
        guard let document = item as? CraftNSDocument else { return nil }
        return .init(
          id: document.store.identity, name: document.displayName, original: document.store.document
        )
      } ?? []
    if !documents.contains(where: { $0.id == identity }) {
      documents.insert(.init(id: identity, name: document.name, original: document), at: 0)
    }
    duplicateLayerDraft = DuplicateLayerDraft(
      store: self, roots: duplicateRoots, documents: documents)
  }
  func cancelDuplicate() {
    duplicateTask?.cancel()
    if duplicateLayerDraft?.processing != true { duplicateLayerDraft = nil }
  }
  func commitDuplicate(_ draft: DuplicateLayerDraft) {
    guard duplicateLayerDraft === draft, draft.valid, !draft.processing else { return }
    guard document == draft.original, groupSelectionIDs == draft.selected,
      !geometryBusy, transformDraft == nil
    else {
      draft.error = "The source changed. Cancel and reopen Duplicate."
      return
    }
    let controller = documentController
    let target: EditorStore?
    let originalTarget: CraftDocument?
    switch draft.destination {
    case .newDocument:
      guard let controller,
        controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === self })
      else {
        draft.error = "The source document is no longer open."
        return
      }
      target = nil
      originalTarget = nil
    case .document(let identity):
      target =
        identity == self.identity
        ? self
        : controller?.documents.compactMap { ($0 as? CraftNSDocument)?.store }.first {
          $0.identity == identity
        }
      guard let target, let snapshot = draft.documents.first(where: { $0.id == identity }),
        target.document == snapshot.original
      else {
        draft.error = "The destination changed or closed. Cancel and reopen Duplicate."
        return
      }
      guard target === self || target.canBeginLayerCreation else {
        draft.error = "Finish the edit in the destination document first."
        return
      }
      originalTarget = target.document
    }
    let source = draft.original
    let selected = Set(draft.roots.map(\.id))
    let layerName = draft.roots.count == 1 ? draft.name : nil
    let documentName = draft.documentName
    let sameDocument = target === self
    draft.error = nil
    draft.processing = true
    geometryBusy = true
    target?.geometryBusy = true
    duplicateTask = Task { [weak self, weak controller] in
      let worker = Task.detached(priority: .userInitiated) {
        if let originalTarget {
          let command: Command
          if sameDocument {
            command = .duplicateLayers(selected, name: layerName)
          } else {
            let copied = try ClipboardRenderer.copy(source, layerIDs: selected)
            let converted = try ColorManagement.converted(copied, to: originalTarget)
            command = .duplicateLayersFrom(converted.document, selected, name: layerName)
          }
          return DuplicateResult.existing(
            try PreparedEdit(command: command, document: originalTarget))
        }
        return DuplicateResult.newDocument(
          try LayerDuplication.newDocument(
            from: source, selected: selected, layerName: layerName, documentName: documentName))
      }
      defer {
        self?.geometryBusy = false
        target?.geometryBusy = false
        draft.processing = false
        self?.duplicateTask = nil
      }
      do {
        let result = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self, self.duplicateLayerDraft === draft, self.document == source,
          self.groupSelectionIDs == draft.selected
        else { throw CraftError.invalid("The source changed during duplication.") }
        if draft.canCreateDocument {
          guard let controller,
            controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === self }),
            target == nil
              || controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === target }
              )
          else { throw CraftError.invalid("A document closed during duplication.") }
        }
        switch result {
        case .existing(let prepared):
          guard let target else { throw CraftError.invalid("The destination closed.") }
          let oldIDs = Set(target.document.layers.map(\.id))
          try target.executeCompositePreparedEdit(prepared)
          let added = Set(target.document.layers.map(\.id)).subtracting(oldIDs)
          target.selectedLayerIDs = Set(
            try LayerDuplication.roots(in: target.document, selected: added).map(\.id))
          target.maskEditingLayerID = nil
          target.selectPath(nil)
          target.onChange?(.changeDone)
          target.render()
          target.status = draft.title
          self.duplicateLayerDraft = nil
        case .newDocument(let model):
          guard let controller else {
            throw CraftError.invalid("No document controller is available.")
          }
          self.duplicateLayerDraft = nil
          self.geometryBusy = false
          let created = CraftNSDocument(model: model)
          created.store.selectedLayerIDs = Set(model.children(of: nil).map(\.id))
          controller.addDocument(created)
          created.updateChangeCount(.changeDone)
          created.makeWindowControllers()
          created.showWindows()
        }
      } catch is CancellationError {
        self?.duplicateLayerDraft = nil
      } catch {
        draft.error = error.localizedDescription
      }
    }
  }
}

struct DuplicateLayerSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: DuplicateLayerDraft
  @FocusState private var nameFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.title).font(.headline)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 14) {
          Text(
            "Duplicate: \(draft.roots.count == 1 ? draft.roots[0].name : "\(draft.roots.count) selected items")"
          )
          .lineLimit(2)
          if draft.roots.count == 1 {
            HStack {
              Text("As:").frame(width: 66, alignment: .trailing)
              TextField("As", text: $draft.name).labelsHidden().focused($nameFocused)
                .accessibilityIdentifier("duplicate.name")
            }
          }
          GroupBox("Destination") {
            VStack(spacing: 12) {
              HStack {
                Text("Document:").frame(width: 66, alignment: .trailing)
                Picker("Document", selection: $draft.destination) {
                  ForEach(draft.documents) { document in
                    Text(document.name).tag(DuplicateDestination.document(document.id))
                  }
                  if draft.canCreateDocument { Text("New").tag(DuplicateDestination.newDocument) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                  .accessibilityIdentifier(
                    "duplicate.destination")
              }
              if draft.destination == .newDocument {
                HStack {
                  Text("Name:").frame(width: 66, alignment: .trailing)
                  TextField("Name", text: $draft.documentName).labelsHidden()
                    .accessibilityIdentifier("duplicate.documentName")
                }
              }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).disabled(draft.processing)
        VStack(spacing: 10) {
          Button("OK") { store.commitDuplicate(draft) }.keyboardShortcut(.defaultAction)
            .disabled(!draft.valid || draft.processing).frame(width: 76)
          Button("Cancel") { store.cancelDuplicate() }.keyboardShortcut(.cancelAction).frame(
            width: 76)
          if draft.processing { ProgressView().controlSize(.small) }
        }
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(20).frame(width: 560).font(.system(size: 12)).controlSize(.small)
      .onAppear { nameFocused = true }
      .onChange(of: draft.destination) { old, _ in draft.changedDestination(from: old) }
  }
}

extension AppDelegate {
  /// Diagnostic content only; no live interaction is established by this render.
  func duplicateLayerSnapshot() {
    do {
      var model = try CraftDocument(width: 3, height: 2, name: "Landscape")
      model.layers[0].name = "Mountain study"
      if CommandLine.arguments.contains("--snapshot-duplicate-group") {
        try Command.newGroup(.init(name: "Artwork"), children: [model.layers[0].id]).apply(
          to: &model)
      }
      if CommandLine.arguments.contains("--snapshot-duplicate-multiple") {
        try Command.addLayer(Layer(name: "Color Grade", content: .fill(.white))).apply(to: &model)
      }
      let document = CraftNSDocument(model: model)
      controller.addDocument(document)
      let store = document.store
      store.renderTask?.cancel()
      if CommandLine.arguments.contains("--snapshot-duplicate-multiple") {
        store.selectedLayerIDs = Set(model.layers.map(\.id))
      }
      store.beginDuplicate()
      guard let draft = store.duplicateLayerDraft else { return }
      if CommandLine.arguments.contains("--snapshot-duplicate-new") {
        let old = draft.destination
        draft.destination = .newDocument
        draft.changedDestination(from: old)
        draft.documentName = "Mountain details"
      }
      let host = NSHostingView(
        rootView: DuplicateLayerSheet(store: store, draft: draft)
          .background(StudioTheme.panel).preferredColorScheme(.dark))
      host.frame = .init(x: 0, y: 0, width: 560, height: 280)
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      window.appearance = NSAppearance(named: .darkAqua)
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [window, host, document] in
        do {
          window.layoutIfNeeded()
          host.layoutSubtreeIfNeeded()
          guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CraftError.invalid("Duplicate snapshot allocation failed.")
          }
          host.cacheDisplay(in: host.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("Duplicate snapshot encoding failed.")
          }
          let path = CommandLine.arguments.last ?? "/private/tmp/photato-duplicate.png"
          try data.write(to: URL(fileURLWithPath: path))
          print("Offscreen Duplicate snapshot: \(path)")
        } catch { print("Duplicate snapshot failed: \(error)") }
        document.close()
        NSApp.terminate(nil)
      }
    } catch {
      print("Duplicate snapshot setup failed: \(error)")
      NSApp.terminate(nil)
    }
  }
}
