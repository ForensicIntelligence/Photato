import AppKit
import PhotoCraftCore
import SwiftUI

@MainActor extension EditorStore {
  var pathComponentOperationSelection: [Int] {
    guard usesPathComponentLayout, canApplyPathComponentLayout, selectedPathChoices.count == 1,
          case .components(let indices) = pathTransformSelection, !indices.isEmpty,
          let path = selectedVectorPath, indices.allSatisfy(path.components.indices.contains) else { return [] }
    return indices
  }

  func pathComponentOperationEnabled(_ operation: PathComponentOperation) -> Bool {
    guard usesPathComponentLayout, canApplyPathComponentLayout, selectedPathChoices.count == 1,
          let target = pathTarget, let path = try? PathTransform.editablePath(target, in: document) else { return false }
    if operation == .merge {
      let indices: [Int]
      switch pathTransformSelection {
      case .all: indices = Array(path.components.indices)
      case .components(let selection): indices = selection
      case .anchors: return false
      }
      let chosen = Set(indices)
      let groups = PathComponentEdit.groups(in: path).filter { $0.contains(where: chosen.contains) }
      return groups.count >= 2 && groups.joined().allSatisfy { path.components[$0].closed }
    }
    let indices = pathComponentOperationSelection
    if PathComponentOperation.stacking.contains(operation) {
      return PathComponentEdit.canReorder(path, components: indices, operation: operation)
    }
    return !indices.isEmpty
  }

  func applyPathComponentOperation(_ operation: PathComponentOperation) {
    guard pathComponentOperationEnabled(operation), let target = pathTarget else { return }
    let components = pathComponentOperationSelection
    let request = PathComponentEditRequest(target: target, components: components.isEmpty ? nil : components, operation: operation)
    let selection = selectedPathChoices
    performPreparedGeometry(label: operation.title, prepare: { source in
      let edit = try PathComponentEdit.prepare(request, in: source)
      return try PreparedEdit(command: .editPathComponents(edit), document: source)
    }, validateCommit: {
      guard self.pathTarget == target, self.selectedPathChoices == selection else {
        throw CraftError.invalid("The path component selection changed.")
      }
    }, onCommit: { prepared in
      guard let edit = prepared.pathComponentEdit else { return }
      self.applyMarqueeSelection(edit.selection)
      if let mode = operation.overlapMode { self.pathOperation = mode }
    })
  }
}

struct PathComponentOperationMenus: View {
  @Bindable var store: EditorStore

  var body: some View {
    Menu("Path Operations") {
      buttons(PathComponentOperation.overlap)
      Divider()
      buttons([.merge])
    }
    .menuStyle(.borderlessButton)
    .controlSize(.small)
    .accessibilityIdentifier("path.components.operations")

    Menu("Path Arrangement") {
      buttons(PathComponentOperation.stacking)
    }
    .menuStyle(.borderlessButton)
    .controlSize(.small)
    .disabled(!PathComponentOperation.stacking.contains(where: store.pathComponentOperationEnabled))
    .accessibilityIdentifier("path.components.arrangement")
  }

  private func buttons(_ operations: [PathComponentOperation]) -> some View {
    ForEach(operations, id: \.self) { operation in
      Button(operation.title) { store.applyPathComponentOperation(operation) }
        .disabled(!store.pathComponentOperationEnabled(operation))
    }
  }
}

@MainActor extension CraftCanvas {
  func addPathComponentOperations(to menu: NSMenu) {
    func submenu(_ title: String, operations: [PathComponentOperation]) {
      let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let group = NSMenu(title: title)
      group.autoenablesItems = false
      for operation in operations {
        if operation == .merge { group.addItem(.separator()) }
        let item = NSMenuItem(title: operation.title, action: #selector(applyComponentOperation(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = operation.rawValue
        item.isEnabled = store.pathComponentOperationEnabled(operation)
        group.addItem(item)
      }
      parent.submenu = group
      parent.isEnabled = group.items.contains { $0.isEnabled && !$0.isSeparatorItem }
      menu.addItem(parent)
    }
    submenu("Path Operations", operations: PathComponentOperation.overlap + [.merge])
    submenu("Path Arrangement", operations: PathComponentOperation.stacking)
  }

  @objc func applyComponentOperation(_ item: NSMenuItem) {
    guard let name = item.representedObject as? String, let operation = PathComponentOperation(rawValue: name) else { return }
    store.applyPathComponentOperation(operation)
  }
}
