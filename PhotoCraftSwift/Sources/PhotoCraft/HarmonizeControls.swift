import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  var harmonizeTarget: UUID? {
    guard canSelectComponentTarget, !editingComponent, !smartFilterMaskEditing, pathTarget == nil,
      generativeFillDraft == nil, cropDraft == nil, regionRetouchDraft == nil,
      clipboardLayerIDs.count == 1 else { return nil }
    return Harmonize.foreground(in: document)
  }

  func applyHarmonize() {
    guard let subject = harmonizeTarget else { return }
    performGeometry(label: "Harmonize", prepare: { original in
      try Harmonize.apply(in: original, foregroundID: subject)
    }, onSuccess: { [weak self] in self?.finishBackgroundReplacement() })
  }

  func chooseHarmonize(_ choice: Harmonize.Variation, groupID: UUID) {
    guard clipboardTargetAvailable else { return }
    performGeometry(label: "Harmonize Variation", prepare: { original in
      try Harmonize.select(choice, in: original, groupID: groupID)
    })
  }
}

extension AppDelegate {
  @objc func harmonizeSubject() { store?.applyHarmonize() }
}

struct HarmonizeControls: View {
  let store: EditorStore
  let choices: Harmonize.Choices

  var body: some View {
    Picker("Harmonize Variation", selection: Binding(
      get: { choices.selected },
      set: { if let option = $0 { store.chooseHarmonize(option, groupID: choices.groupID) } }
    )) {
      if choices.selected == nil { Text("Custom Visibility").tag(nil as Harmonize.Variation?) }
      ForEach(choices.variations, id: \.self) { option in
        Text(option.name).tag(Optional(option))
      }
    }
    .disabled(!store.clipboardTargetAvailable || store.document.isLocked(choices.groupID))
    .accessibilityIdentifier("harmonize.variation")
  }
}

enum HarmonizeAPI {
  static let apply = "harmonize.apply"
  static let variation = "harmonize.variation"

  static var names: [String] { Harmonize.Variation.allCases.map { $0.name.lowercased() } }

  static func parameters(_ name: String) -> [String: Any] {
    let option = BrushAPI.enumeration(names)
    if name == apply {
      return BrushAPI.object(["foregroundLayerID": VariablesAPI.uuid, "variation": option], required: [])
    }
    return BrushAPI.object(["groupID": VariablesAPI.uuid, "variation": option], required: ["groupID", "variation"])
  }

  static var schema: [String: Any] {
    let nullable = ["anyOf": [BrushAPI.enumeration(names), ["type": "null"]]]
    return BrushAPI.object([
      "foregroundLayerID": VariablesAPI.nullableUUID,
      "groupID": VariablesAPI.nullableUUID,
      "selected": nullable,
      "choices": ["type": "array", "items": BrushAPI.enumeration(names)],
    ], required: ["foregroundLayerID", "groupID", "selected", "choices"])
  }

  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let choices = Harmonize.choices(in: store.document)
    return [
      "foregroundLayerID": store.harmonizeTarget?.uuidString as Any? ?? NSNull(),
      "groupID": choices?.groupID.uuidString as Any? ?? NSNull(),
      "selected": choices?.selected?.name.lowercased() as Any? ?? NSNull(),
      "choices": choices?.variations.map { $0.name.lowercased() } ?? [],
    ]
  }

  static func choice(_ command: AutomationCommand) throws -> Harmonize.Variation {
    guard command.parameters["variation"] != nil else { return .balanced }
    let name = try command.string("variation")
    guard let choice = Harmonize.Variation.allCases.first(where: { $0.name.lowercased() == name }) else {
      throw AutomationFailure(status: 400, message: "Choose subtle, balanced, or ambient.")
    }
    return choice
  }
}
