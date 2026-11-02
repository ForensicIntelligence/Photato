import AppKit
import SwiftUI
import PhotoCraftCore

@MainActor extension EditorStore {
  var canChangeLayerLinks:Bool{canBeginLayerCreation && !editingMask && !editingComponent && document.animation==nil && document.videoTimeline==nil}
  func linkTargets(_ context:UUID?=nil)->[UUID]{let ids=layerPanelSelection(context);return document.layers.filter{ids.contains($0.id)}.map(\.id)}
  func linkedSelection(_ ids:[UUID])->Bool{!ids.isEmpty && document.layers.filter{ids.contains($0.id)}.allSatisfy{$0.linkID != nil}}
  func linkMenuUnlinks(_ ids:[UUID])->Bool{let layers=document.layers.filter{ids.contains($0.id)},groups=Set(layers.compactMap(\.linkID));return !layers.isEmpty && layers.allSatisfy{$0.linkID != nil} && groups.count==1 && LayerLinks.related(in:document,layerIDs:Set(ids)).count>1}
  func canToggleLayerLinks(context:UUID?=nil)->Bool{let ids=linkTargets(context);return canChangeLayerLinks && (linkMenuUnlinks(ids) || (ids.count>=2 && document.layers.allSatisfy{!ids.contains($0.id) || !$0.isBackground}))}
  func canSelectLinkedLayers(context:UUID?=nil)->Bool{let ids=Set(linkTargets(context));return canChangeLayerLinks && LayerLinks.related(in:document,layerIDs:ids).count>1 && document.layers.contains{ids.contains($0.id) && $0.linkID != nil}}
  func toggleLayerLinks(context:UUID?=nil,temporary:Bool=false){
    guard canToggleLayerLinks(context:context) else{return};let ids=linkTargets(context)
    if temporary,linkedSelection(ids){let disabled=document.layers.filter{ids.contains($0.id)}.allSatisfy{$0.linkDisabled == true};perform(.layerLinks(.enabled(ids,disabled)))}
    else{perform(.layerLinks(linkMenuUnlinks(ids) ? .unlink(ids):.link(ids)))}
  }
  func toggleLayerLink(_ id:UUID,modifiers:NSEvent.ModifierFlags){
    guard canChangeLayerLinks,let layer=document.layers.first(where:{$0.id==id}),layer.linkID != nil else{return}
    perform(.layerLinks(modifiers.contains(.shift) ? .enabled([id],layer.linkDisabled == true):.unlink([id])))
  }
  func selectLinkedLayers(_ ids:[UUID])throws{
    guard canChangeLayerLinks,Set(ids).isSubset(of:Set(document.layers.map(\.id))),!ids.isEmpty else{throw CraftError.invalid("Finish the current edit and choose existing linked layers.")}
    let related=LayerLinks.related(in:document,layerIDs:Set(ids))
    guard related.count>1,document.layers.contains(where:{ids.contains($0.id) && $0.linkID != nil}) else{throw CraftError.invalid("Choose a linked layer.")}
    let active=document.activeLayerID.flatMap{related.contains($0) ? $0:nil} ?? document.layers.first{related.contains($0.id)}!.id
    select(active);selectedLayerIDs=related
  }
  func selectLinkedLayers(context:UUID?=nil){do{try selectLinkedLayers(linkTargets(context))}catch{self.error=error.localizedDescription}}
  var wholeLayerMoveIDs:[UUID]{let ids=LayerLinks.expanded(in:document,layerIDs:groupSelectionIDs);return document.layers.filter{ids.contains($0.id)}.map(\.id)}
  func canBeginWholeLayerMove(copy:Bool=false)->Bool{
    guard document.selection==nil,pathTarget==nil,!editingMask,!editingComponent,canSelectComponentTarget,LayerCollectionTransform.available(document,layerIDs:wholeLayerMoveIDs) else{return false}
    return !copy || LayerDuplication.canDuplicate(in:document,selected:Set(wholeLayerMoveIDs))
  }
  func selectMovedCopies(from originalIDs:Set<UUID>){let added=Set(document.layers.map(\.id)).subtracting(originalIDs);selectedLayerIDs=Set(document.layers.filter{added.contains($0.id) && document.ancestors(of:$0.id).allSatisfy{!added.contains($0.id)}}.map(\.id))}
  func beginWholeLayerMove(modifiers:NSEvent.ModifierFlags)->Bool{
    guard canBeginWholeLayerMove(copy:modifiers.contains(.option)),let active=document.activeLayerID else{return false}
    do{finishNumericField();finishLayerName();let ids=wholeLayerMoveIDs;var draft=TransformDraft(layerID:active,bounds:try layerCollectionBounds(ids));draft.collectionLayerIDs=ids;draft.collectionViewIDs=groupSelectionIDs;draft.selection=true;draft.selectedPixels=true;draft.movingLayers=true;draft.copyWholeLayers=modifiers.contains(.option);draft.selectionQuad=draft.selectionCorners
      let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;session.task=Task{await session.prepare()};status=draft.copyWholeLayers ? "Copy layers":"Move layers";return true
    }catch{self.error=error.localizedDescription;return false}
  }
  @discardableResult func nudgeWholeLayers(keyCode:UInt16,modifiers:NSEvent.ModifierFlags)->Bool{guard tool == .move,[123,124,125,126].contains(keyCode),!modifiers.contains(.command),!modifiers.contains(.control),canBeginWholeLayerMove(copy:modifiers.contains(.option)) else{return false};let step=modifiers.contains(.shift) ? 10:1;performGeometry(.moveLayers(.init(layerIDs:wholeLayerMoveIDs,dx:keyCode==123 ? -step:keyCode==124 ? step:0,dy:keyCode==125 ? step:keyCode==126 ? -step:0,copy:modifiers.contains(.option))));return true}
  func updateWholeLayerMove(_ original:TransformDraft,from start:CGPoint,to end:CGPoint,modifiers:NSEvent.ModifierFlags,zoom:Double){
    guard original.movingLayers,!geometryBusy else{return};var dx=Double(end.x-start.x),dy=Double(end.y-start.y)
    if modifiers.contains(.shift){let length=hypot(dx,dy),angle=(atan2(dy,dx)/(.pi/4)).rounded()*(.pi/4);dx=cos(angle)*length;dy=sin(angle)*length}
    if !modifiers.contains(.shift){(dx,dy)=guideMoveOffset(original.bounds,dx:dx,dy:dy,zoom:zoom,modifiers:modifiers)};dx=dx.rounded();dy=dy.rounded()
    guard dx.isFinite,dy.isFinite,abs(dx)<=1_000_000,abs(dy)<=1_000_000 else{return};var draft=original.selectionApplying(.translation(dx,dy));draft.moveOffsetX=Int(dx);draft.moveOffsetY=Int(dy);updateTransform(draft)
  }
}
extension ToolCursor {
  static func layerLink(modifiers:NSEvent.ModifierFlags,linked:Bool,disabled:Bool,available:Bool,unlink:Bool?=nil)->ToolCursor{
    guard available else{return .unavailable};return .symbol("link",linked && modifiers.contains(.shift) ? (disabled ? .add:.subtract):(unlink ?? linked) ? .subtract:.add)
  }
}
struct LayerLinkBadge:View {
  @Bindable var store:EditorStore
  let layer:Layer
  var body:some View{
    Button{store.toggleLayerLink(layer.id,modifiers:NSEvent.modifierFlags)}label:{Image(systemName:"link").font(.system(size:10)).frame(width:16,height:18).overlay{if layer.linkDisabled == true{DisabledMaskMark()}}}.buttonStyle(.plain)
      .disabled(!store.canChangeLayerLinks).help(layer.linkDisabled == true ? "Layer link disabled. Shift-click to enable; click to unlink.":"Linked layer. Shift-click to disable; click to unlink.")
      .accessibilityLabel("Layer link for \(layer.name)")
      .toolCursor{flags in ToolCursor.layerLink(modifiers:flags,linked:true,disabled:layer.linkDisabled == true,available:store.canChangeLayerLinks)}
  }
}
extension AppDelegate {
  @objc func linkSelectedLayers(){store?.toggleLayerLinks()}
  @objc func selectLinkedLayers(){store?.selectLinkedLayers()}
}
