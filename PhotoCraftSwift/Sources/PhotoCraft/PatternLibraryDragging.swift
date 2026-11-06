import AppKit
import SwiftUI
import PhotoCraftCore

@MainActor enum PatternLibraryDrag {
  nonisolated static let identifier="ca.forensicintelligence.photato.pattern-library"
  private static let prefix="photato-pattern-v1:"
  @MainActor private final class Capture {
    weak var store:EditorStore?
    weak var controller:CraftDocumentController?
    let attached:Bool
    let source:PatternDialogSource
    let token=UUID()
    let ids,descendants:Set<UUID>
    init(_ store:EditorStore,ids:Set<UUID>) {
      self.store=store;controller=store.documentController;attached=controller != nil
      source=PatternDialogSource(store);self.ids=ids
      descendants=ids.reduce(into:Set<UUID>()){$0.formUnion(store.patterns.state.descendants(of:$1))}
    }
    func matches(_ target:EditorStore,allowBusy:Bool=false)->Bool {
      guard let store,source.matches(store),store.patterns===target.patterns,
        (!store.patterns.busy || allowBusy),!store.geometryBusy,!target.geometryBusy else{return false}
      if attached {
        guard let controller,controller.documents.contains(where:{($0 as? CraftNSDocument)?.store===store})else{return false}
      }
      if let controller=target.documentController {
        guard controller.documents.contains(where:{($0 as? CraftNSDocument)?.store===target})else{return false}
      }
      return true
    }
  }
  private static var capture:Capture?
  static func operation(_ modifiers:NSEvent.ModifierFlags)->DropOperation{.move}
  static func provider(store:EditorStore,nodeID:UUID)->NSItemProvider {
    capture=nil;let provider=NSItemProvider()
    guard !store.geometryBusy,!store.patterns.busy,store.patterns.state.node(nodeID) != nil else{return provider}
    do {
      if !store.patterns.state.selectedNodes.contains(nodeID) {
        try store.patterns.select([nodeID],active:store.patterns.state.node(nodeID)?.isGroup==false ? nodeID:nil)
      }
      let value=Capture(store,ids:store.patterns.state.selectedNodes);capture=value
      let data=Data((prefix+value.token.uuidString).utf8)
      provider.registerDataRepresentation(forTypeIdentifier:identifier,visibility:.ownProcess){completion in completion(data,nil);return nil}
    }catch{store.error=error.localizedDescription}
    return provider
  }
  static func canReceive(store:EditorStore,parent:UUID?,before:UUID?)->Bool {
    guard let value=capture,value.matches(store),!value.ids.isEmpty else{return false}
    let state=store.patterns.state
    if let parent{guard state.node(parent)?.isGroup==true,!value.descendants.contains(parent)else{return false}}
    if let before{guard let node=state.node(before),node.parentID==parent,!value.descendants.contains(before)else{return false}}
    return true
  }
  static func receive(_ provider:NSItemProvider,store:EditorStore,parent:UUID?,before:UUID?)async->Bool {
    guard canReceive(store:store,parent:parent,before:before),let expected=capture,
      provider.hasItemConformingToTypeIdentifier(identifier)else{return false}
    let data:Data?=await withCheckedContinuation{continuation in
      _=provider.loadDataRepresentation(forTypeIdentifier:identifier){data,error in continuation.resume(returning:error==nil ? data:nil)}
    }
    guard !Task.isCancelled,let data,data.count<=96,String(data:data,encoding:.utf8)==prefix+expected.token.uuidString,
      capture?.token==expected.token,canReceive(store:store,parent:parent,before:before)else{return false}
    capture=nil
    do {
      _=try await store.patterns.mutate(.move(expected.ids,parent:parent,before:before),authorize:{[weak store]in store.map{expected.matches($0,allowBusy:true)} ?? false})
      return true
    }catch{store.error=error.localizedDescription;return false}
  }
}
@MainActor private struct PatternDropDelegate:@preconcurrency DropDelegate {
  let store:EditorStore
  let parent,before:UUID?
  @Binding var highlighted:Bool
  func validateDrop(info:DropInfo)->Bool {
    info.itemProviders(for:[PatternLibraryDrag.identifier]).count==1 && PatternLibraryDrag.canReceive(store:store,parent:parent,before:before)
  }
  func dropEntered(info:DropInfo){highlighted=validateDrop(info:info)}
  func dropExited(info:DropInfo){highlighted=false}
  func dropUpdated(info:DropInfo)->DropProposal? {
    highlighted=validateDrop(info:info)
    return DropProposal(operation:highlighted ? PatternLibraryDrag.operation(NSEvent.modifierFlags):.cancel)
  }
  func performDrop(info:DropInfo)->Bool {
    guard validateDrop(info:info),let provider=info.itemProviders(for:[PatternLibraryDrag.identifier]).first else{return false}
    highlighted=false
    Task{@MainActor in _=await PatternLibraryDrag.receive(provider,store:store,parent:parent,before:before)}
    return true
  }
}
@MainActor struct PatternLibraryDropTarget:ViewModifier {
  let store:EditorStore
  let parent,before:UUID?
  @State private var highlighted=false
  func body(content:Content)->some View {
    content.overlay(Rectangle().stroke(highlighted ? StudioTheme.accent:.clear,lineWidth:2))
      .onDrop(of:[PatternLibraryDrag.identifier],delegate:PatternDropDelegate(store:store,parent:parent,before:before,highlighted:$highlighted))
  }
}
