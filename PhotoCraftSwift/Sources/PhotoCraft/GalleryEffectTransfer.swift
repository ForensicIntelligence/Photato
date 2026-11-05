import AppKit
import SwiftUI

enum GalleryEffectTransfer {
  static let identifier = "ca.forensicintelligence.photato.gallery-effect"
  @MainActor static func provider(model: ArtisticGalleryWorkspace, index: Int) -> NSItemProvider {
    let provider = NSItemProvider()
    guard let payload=model.beginEffectDrag(at:index) else { return provider }
    provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
      completion(Data(payload.utf8), nil)
      return nil
    }
    return provider
  }
  @MainActor static func receive(_ provider: NSItemProvider, model: ArtisticGalleryWorkspace, target: Int) async -> Bool {
    guard model.canAcceptEffectDrop(at:target),provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier:identifier) { data,error in
        continuation.resume(returning:error == nil ? data:nil)
      }
    }
    guard !Task.isCancelled,let data,data.count<=160,let value=String(data:data,encoding:.utf8) else { return false }
    return model.receiveEffectDrop(value,at:target)
  }
  static var apiCapabilities: [String: Any] {
    ["commands": ["filter.apply", "smartFilter.set"],
      "array": "filter.artistic.effects (or stack.filters[].filter.artistic.effects). Supply the complete ordered effect array; first runs first and is shown at the bottom of the native list.",
      "native": "Arrow buttons and effect-row dragging use the same move operation. Drop moves the source to the target row position and retains every effect's values, colors and visibility. One local Undo per changed order; preview/Cancel leaves the document unchanged, OK creates one native edit.",
      "guards": "Private process-local drag format captures the workspace, settings revision and source index. Stale, malformed, cross-workspace, closed, invalid-index, multi-provider and no-op drops do not reorder. The drop proposal is move; no implicit duplicate or delete.",
      "persistence": "Order uses the existing Gallery settings schema, native archive and resolved portable filter Actions. No command, schema parameter or serialization version is added.",
      "qualification": "Physical drag hit testing/system feedback, exact Photoshop modifiers/defaults/pixels and broader platform acceptance remain open."]
  }
}

@MainActor struct GalleryEffectDropDelegate: @preconcurrency DropDelegate {
  let model: ArtisticGalleryWorkspace
  let target: Int
  @Binding var highlighted: Int?

  func validateDrop(info: DropInfo) -> Bool {
    model.canAcceptEffectDrop(at:target) && info.hasItemsConforming(to:[GalleryEffectTransfer.identifier])
      && info.itemProviders(for:[GalleryEffectTransfer.identifier]).count==1
  }
  func dropEntered(info: DropInfo) {
    if validateDrop(info:info) { highlighted=target }
  }
  func dropExited(info: DropInfo) {
    if highlighted==target { highlighted=nil }
  }
  func dropUpdated(info: DropInfo) -> DropProposal? {
    validateDrop(info:info) ? DropProposal(operation:.move):nil
  }
  func performDrop(info: DropInfo) -> Bool {
    guard validateDrop(info:info) else { return false }
    let providers=info.itemProviders(for:[GalleryEffectTransfer.identifier])
    guard providers.count==1 else { return false }
    highlighted=nil
    let provider=providers[0]
    Task { @MainActor in _ = await GalleryEffectTransfer.receive(provider,model:model,target:target) }
    return true
  }
}
