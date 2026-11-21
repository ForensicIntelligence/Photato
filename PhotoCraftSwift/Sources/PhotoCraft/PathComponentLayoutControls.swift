import AppKit
import PhotoCraftCore
import SwiftUI

@MainActor extension EditorStore {
  var usesPathComponentLayout: Bool { tool == .pathSelection || tool == .directSelection }
  var canApplyPathComponentLayout: Bool {
    canChangePathIsolation && !editingComponent && !editingMask && !smartFilterMaskEditing
  }

  var selectedLayoutComponents: [Int] {
    guard usesPathComponentLayout, canApplyPathComponentLayout, let target = pathTarget,
          selectedPathChoices.count == 1, case .components(let indices) = pathTransformSelection,
          indices.count >= 2, let path = try? PathTransform.editablePath(target, in: document),
          indices.allSatisfy({ path.components.indices.contains($0) && !path.components[$0].knots.isEmpty })
    else { return [] }
    return indices
  }

  func arrangePathComponents(_ operation: LayerLayoutOperation) {
    let indices = selectedLayoutComponents
    guard let target = pathTarget, indices.count >= PathComponentLayoutRequest.minimumCount(for: operation) else { return }
    let request = PathComponentLayoutRequest(target: target, components: indices, operation: operation)
    let selection = selectedPathChoices
    performPreparedGeometry(label: request.label, prepare: {
      try PreparedEdit(command: .layoutPathComponents(request), document: $0)
    }, validateCommit: {
      guard self.pathTarget == target, self.selectedPathChoices == selection else {
        throw CraftError.invalid("The path component selection changed.")
      }
    })
  }
}

struct PathComponentLayoutControls: View {
  @Bindable var store: EditorStore

  var body: some View {
    let count = store.selectedLayoutComponents.count
    Menu("Path Alignment") {
      ForEach(LayerAlignment.allCases, id: \.self) { edge in
        Button { store.arrangePathComponents(.align(edge)) } label: {
          Label(edge.rawValue, systemImage: edge.symbol)
        }
      }
    }
    .menuStyle(.borderlessButton)
    .controlSize(.small)
    .disabled(count < 2)
    .help("Align two or more components on the selected path.")
    .accessibilityIdentifier("path.components.align")

    Menu("Distribute Paths") {
      ForEach(LayerDistribution.allCases, id: \.self) { rule in
        Button(rule.rawValue) { store.arrangePathComponents(.distribute(rule)) }
      }
    }
    .menuStyle(.borderlessButton)
    .controlSize(.small)
    .disabled(count < 3)
    .help("Distribute three or more components on the selected path.")
    .accessibilityIdentifier("path.components.distribute")
  }
}

@MainActor extension CraftCanvas {
  func pathComponentLayoutMenu() -> NSMenu? {
    guard store.usesPathComponentLayout, store.pathTarget != nil else { return nil }
    let count = store.selectedLayoutComponents.count
    let menu = NSMenu()
    menu.autoenablesItems = false
    func addGroup(_ title: String, choices: [(String, LayerLayoutOperation)], enabled: Bool) {
      let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: title)
      submenu.autoenablesItems = false
      for (label, choice) in choices {
        let item = NSMenuItem(title: label, action: #selector(applyPathComponentLayout(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = choice
        item.isEnabled = enabled
        submenu.addItem(item)
      }
      parent.submenu = submenu
      parent.isEnabled = enabled
      menu.addItem(parent)
    }
    addGroup("Path Alignment", choices: LayerAlignment.allCases.map { ($0.rawValue, .align($0)) }, enabled: count >= 2)
    addGroup("Distribute Paths", choices: LayerDistribution.allCases.map { ($0.rawValue, .distribute($0)) }, enabled: count >= 3)
    return menu
  }

  @objc func applyPathComponentLayout(_ item: NSMenuItem) {
    guard let operation = item.representedObject as? LayerLayoutOperation else { return }
    store.arrangePathComponents(operation)
  }
}
