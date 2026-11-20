import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum SpotChannelMergeAPI {
  static let name = "channel.mergeSpot"

  static func schema(_ key: String) -> [String: Any] {
    key == "channelID" ? ["type": "string", "format": "uuid"] : ["type": "boolean", "default": false]
  }

  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "eligibleChannelIDs": ["type": "array", "items": schema("channelID")],
      "selectedChannelAvailable": BrushAPI.flag,
      "requiresHiddenLayerConfirmation": BrushAPI.flag
    ], required: ["eligibleChannelIDs", "selectedChannelAvailable", "requiresHiddenLayerConfirmation"])
  }

  static var capabilities: [String: Any] {
    ["command": name, "state": "selectionChannels.spotMerge", "stateSchema": stateSchema,
     "result": "HTTP 200 returns current document state after one undoable revision.",
     "behavior": "Flattens visible RGB or CMYK artwork over paper, merges one saved spot channel with its Solidity and removes that channel. Other saved channels, profiles, resolution and selections remain. Explicit discardHiddenLayers:true acknowledges hidden-layer loss. Uses native sparse raster and component storage.",
     "actions": "Photato Actions 74 resolves the spot by its saved channel name and occurrence and reuses the same merge.",
     "limits": "Single static canvas. Indexed, Lab, Gray, Multichannel, Quick Mask and temporal documents are excluded. The process-color result uses the existing Photato spot preview and ColorSync interpretation. Exact Photoshop values and custom ink books remain under qualification.",
     "adobe": "The Adobe desktop event is mergeSpotChannel. No Firefly route or an unqualified actionJSON payload is added."]
  }
}

extension EditorStore {
  var spotChannelMergeState: [String: Any] {
    let document = document
    let spots = (document.alphaChannels ?? []).filter { $0.spot != nil }
    let valid = SpotChannelMerge.unavailableReason(document, channelID: spots.first?.id) == nil
    let ids = valid ? spots.map { $0.id.uuidString } : []
    return ["eligibleChannelIDs": ids, "selectedChannelAvailable": canMergeSpotChannel(alphaEditingID),
      "requiresHiddenLayerConfirmation": !ids.isEmpty && !FlattenImageEdit.hiddenLayerIDs(in: document).isEmpty]
  }
}

extension AutomationService {
  func mergeSpotChannel(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    let id = try command.actionUUID("channelID")
    let discard = try command.pathFlag("discardHiddenLayers", false)
    let store = document.store
    if let reason = SpotChannelMerge.unavailableReason(store.document, channelID: id) {
      throw AutomationFailure(status: 422, message: reason)
    }
    guard store.canEditChannels else {
      throw AutomationFailure(status: 409, message: "Finish the current interaction before merging channels.")
    }
    guard discard || FlattenImageEdit.hiddenLayerIDs(in: store.document).isEmpty else {
      throw AutomationFailure(status: 422, message: "Hidden layers require discardHiddenLayers:true.")
    }
    try await executePreparedOperation(document: document, shareID: share.id, revision: command.revision,
      allowAuxiliary: true) { source in
      try SpotChannelMerge.command(source, channelID: id, discardHiddenLayers: discard)
    }
    store.showMergedSpotChannelResult()
    return .json(state(share, document: document))
  }
}
