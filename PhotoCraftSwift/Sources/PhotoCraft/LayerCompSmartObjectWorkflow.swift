import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LayerCompSourceFiles {
  static func read(_ grants: [UUID: LinkedArtworkGrant]) throws -> [UUID: LinkedArtworkRead] {
    var files: [UUID: LinkedArtworkRead] = [:]
    for (id, grant) in grants { try Task.checkCancellation(); files[id] = try LinkedArtworkRead.read(grant) }
    return files
  }
  static func validate(_ files: [UUID: LinkedArtworkRead]) throws {
    for file in files.values { guard try LinkedArtworkRead.signature(file.grant) == file.signature else { throw DocumentPersistenceConflict.changed } }
  }
  static func targets(_ options: LayerCompExportOptions, document: CraftDocument) throws -> Set<UUID> {
    var ids = Set<UUID>()
    for comp in try options.selected(in: document) { ids.formUnion(try LayerCompIO.requiredSmartObjectLayers(for: .apply(comp.id), in: document)) }
    return ids
  }
}
extension EditorStore {
  func layerCompGrants(_ targetIDs: Set<UUID>) throws -> [UUID: LinkedArtworkGrant] {
    var grants: [UUID: LinkedArtworkGrant] = [:]
    for layer in document.layers where targetIDs.contains(layer.id) {
      guard let object = layer.smartObject, object.data.isEmpty, let link = object.linkedSource, grants[object.sourceID] == nil else { continue }
      grants[object.sourceID] = try linkedSourceRegistry.resolve(link, documentID: document.id, documentURL: linkedArtworkDocumentURL)
    }
    return grants
  }
  func editPreparedLayerComp(_ operation: LayerCompCommand) throws {
    guard canEditLayerComps else { throw CraftError.invalid("Finish the current edit before using Layer Comps.") }
    let required = try LayerCompIO.requiredSmartObjectLayers(for: operation, in: document)
    guard !required.isEmpty else { try executeEditorCommand(.layerComp(operation)); return }
    let grants = try layerCompGrants(Set(required)), registry = linkedSourceRegistry
    performPreparedGeometry(label: operation.label, allowLinkedSmartObject: true,
      prepare: { original in
        let files = try LayerCompSourceFiles.read(grants)
        let edit = try PreparedEdit(command: LayerCompIO.command(operation, in: original, sourceData: files.mapValues(\.data)), document: original)
        try LayerCompSourceFiles.validate(files); return edit
      }, validateCommit: {
        guard grants.values.allSatisfy({ registry.stillAuthorizes($0) }) else { throw CraftError.invalid("Linked artwork authorization changed.") }
      })
  }
}
extension AutomationService {
  func layerCompGrants(_ ids: Set<UUID>, store: EditorStore) throws -> [UUID: LinkedArtworkGrant] {
    var grants: [UUID: LinkedArtworkGrant] = [:]
    for layer in store.document.layers where ids.contains(layer.id) {
      guard let object = layer.smartObject, object.data.isEmpty, let link = object.linkedSource, grants[object.sourceID] == nil else { continue }
      grants[object.sourceID] = try linkedArtworkGrant(link, store: store)
    }
    return grants
  }
  func validateLayerCompGrants(_ grants: [UUID: LinkedArtworkGrant], store: EditorStore) throws {
    guard grants.values.allSatisfy({ grant in store.linkedSourceRegistry.stillAuthorizes(grant) && linkedArtworkAssets.values.contains(where: { $0.id == grant.id && $0.generation == grant.generation }) }) else { throw AutomationFailure(status: 409, message: "Linked artwork authorization was revoked.") }
  }
  func cancelSharedLayerCompEdit(_ share: Share) {
    if layerCompEditShares.contains(share.id) { share.document?.store.geometryTask?.cancel() }
  }
  func executeLayerComp(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws {
    let store = document.store
    guard case .layerComp(let operation) = try command.layerCompCommand(in: store.document) else { throw AutomationFailure(status: 400, message: "Invalid Layer Comp operation.") }
    let targets = try LayerCompIO.requiredSmartObjectLayers(for: operation, in: store.document), grants = try layerCompGrants(Set(targets), store: store)
    layerCompEditShares.insert(shareID); if !grants.isEmpty { layerCompFileShares.insert(shareID) }
    defer { layerCompEditShares.remove(shareID); layerCompFileShares.remove(shareID) }
    let preparation = parentLayerCompPreparation
    let _: [UUID: LinkedArtworkRead] = try await executePreparedResult(document: document, shareID: shareID, revision: command.revision, allowLinkedSmartObject: !targets.isEmpty,
      validatePreparedOutput: LayerCompSourceFiles.validate,
      validateCommit: { [weak self, weak store] in
        guard let self, let store else { throw CancellationError() }; try self.validateLayerCompGrants(grants, store: store)
      }) { original in
        let files = try LayerCompSourceFiles.read(grants)
        return (try await preparation(operation, original, files.mapValues(\.data)), files)
      }
  }
}
