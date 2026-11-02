import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum SmartObjectLayerCompAPI {
  static let name = "smartObject.layerComp"
  static var stateSchema: [String: Any] {
    ["anyOf": [["type": "null"], BrushAPI.object([
      "entries": ["type": "array", "maxItems": LayerComps.maximumComps, "items": BrushAPI.object(["id": VariablesAPI.uuid, "name": ["type": "string", "minLength": 1, "maxLength": 1024]], required: ["id", "name"])],
      "selectedID": VariablesAPI.nullableUUID], required: ["entries"])]]
  }
  static var capabilities: [String: Any] {
    ["command": name, "stateSchema": stateSchema, "nativeArchiveVersion": 80,
     "selection": "compID is a source comp UUID or null for Last Document State as saved in source bytes. Refreshes choices when an older placed native source lacks its derived catalogue. One instance changes; original source bytes and shared sourceID remain unchanged.",
     "history": "Shared desktop/API preparation and atomic Undo; retains parent transform, masks, warp, projection, styles and Smart Filters. Source replacement rerenders each instance with its retained comp choice and stack mode. Missing selected comps reject atomically; reset to Last Document State before replacing them.",
     "parentComps": "Parent layerComps.edit smartObjects capture/apply/restoreLast and exports record source/choice IDs and render current sources; native81 retains these records.",
     "linked": "Retained owned bytes work offline. Otherwise requires an unchanged linked original and existing native/API session artwork authorization; no network fetch or implicit file permission.",
     "remaining": ["Parent-comp child selection records, changing appearance and cached-only linked comp descriptors", "Unresolved imported linked preview and full source-change/missing-comp Photoshop behavior", "Live Photoshop/Photato, factory defaults, Actions/ATN, large capacity and supported-platform qualification"],
     "adobe": "No dedicated published Layer Comp endpoint. Adobe execute-actions comp descriptors remain unsupported; no new route is invented."]
  }
}
extension AutomationCommand {
  func smartObjectCompID() throws -> UUID? {
    guard let value = parameters["compID"] else { throw AutomationFailure(status: 400, message: "Supply a comp UUID or null for Last Document State.") }
    if case .null = value { return nil }
    guard case .string(let text) = value, let id = UUID(uuidString: text) else { throw AutomationFailure(status: 400, message: "compID must be a UUID or null.") }
    return id
  }
}
extension EditorStore {
  var canChooseSmartObjectComp: Bool {
    canManageLinkedArtwork && timelineTask == nil && activeLayer.map { !document.isImageLocked($0.id) && $0.smartObject != nil && $0.smartObject?.pdfSource == nil && $0.smartObject?.rawDevelopment == nil } == true
  }
  func chooseSmartObjectComp(_ compID: UUID?) {
    guard canChooseSmartObjectComp, let layer = activeLayer, let object = layer.smartObject else { return }
    if let link = object.linkedSource, object.data.isEmpty {
      do {
        let grant = try linkedSourceRegistry.resolve(link, documentID: document.id, documentURL: linkedArtworkDocumentURL)
        performLinkedArtwork(label: "Set Smart Object Layer Comp", grant: grant) { original, file in
          try SmartObjectLayerCompIO.selection(in: original, layerID: layer.id, compID: compID, sourceData: file.data)
        }
      } catch { self.error = error.localizedDescription }
    } else {
      performGeometry(label: "Set Smart Object Layer Comp", allowLinkedSmartObject: true) { original in
        try SmartObjectLayerCompIO.selection(in: original, layerID: layer.id, compID: compID)
      }
    }
  }
}
struct SmartObjectLayerCompControls: View {
  @Bindable var store: EditorStore
  let source: SmartObject
  var body: some View {
    if let choices = source.layerComps {
      Picker("Layer Comp", selection: Binding(get: { source.layerComps?.selectedID }, set: { store.chooseSmartObjectComp($0) })) {
        Text("Last Document State").tag(nil as UUID?)
        ForEach(choices.entries) { Text($0.name).tag(Optional($0.id)) }
      }.disabled(!store.canChooseSmartObjectComp)
    } else if source.mediaType == "application/vnd.photato.document" {
      Button("Load Layer Comps") { store.chooseSmartObjectComp(nil) }.disabled(!store.canChooseSmartObjectComp)
    }
  }
}
extension AutomationService {
  func cancelSharedSmartObjectComp(_ share: Share) {
    if smartObjectCompShares.contains(share.id) { share.document?.store.geometryTask?.cancel() }
  }
  func executeSmartObjectComp(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws {
    let id = try command.actionUUID("layerID"), compID = try command.smartObjectCompID(), store = document.store
    guard store.timelineTask == nil else { throw AutomationFailure(status:409,message:"Stop Timeline playback before choosing a source Layer Comp.") }
    let preparation = smartObjectCompPreparation
    guard let object = store.document.layers.first(where: { $0.id == id })?.smartObject else { throw AutomationFailure(status: 404, message: "Smart Object not found.") }
    let grant: LinkedArtworkGrant? = try object.data.isEmpty && object.linkedSource != nil ? linkedArtworkGrant(object.linkedSource!, store: store) : nil
    smartObjectCompShares.insert(shareID)
    if grant != nil { smartObjectCompFileShares.insert(shareID) }
    defer { smartObjectCompShares.remove(shareID); smartObjectCompFileShares.remove(shareID) }
    let _: LinkedArtworkRead? = try await executePreparedResult(document: document, shareID: shareID, revision: command.revision, allowLinkedSmartObject: true,
      validatePreparedOutput: { file in
        if let file { guard try LinkedArtworkRead.signature(file.grant) == file.signature else { throw DocumentPersistenceConflict.changed } }
      }, validateCommit: { [weak self, weak store] in
        if let grant {
          guard let self, let store, store.linkedSourceRegistry.stillAuthorizes(grant), self.linkedArtworkAssets.values.contains(where: { $0.id == grant.id && $0.generation == grant.generation }) else { throw AutomationFailure(status: 409, message: "Linked artwork authorization was revoked.") }
        }
      }) { original in
        let file = try grant.map(LinkedArtworkRead.read)
        return (try await preparation(original, id, compID, file?.data), file)
      }
  }
}
