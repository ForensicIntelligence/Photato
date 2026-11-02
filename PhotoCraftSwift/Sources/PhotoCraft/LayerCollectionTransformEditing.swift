import AppKit
import PhotoCraftCore

extension TransformDraft{
  func supportsSelectionMode(_ mode:SelectionTransformMode)->Bool{collectionLayerIDs==nil || collectionProjective || [.free,.scale,.rotate,.skew].contains(mode)}
}
@MainActor extension EditorStore{
  var wantsLayerCollectionTransform:Bool{layerCollectionIDs.count>1 || activeLayer?.isGroup == true || ProjectiveLayerTransform.available(document,layerIDs:layerCollectionIDs)}
  var layerCollectionIDs:[UUID]{let ids=LayerLinks.expanded(in:document,layerIDs:groupSelectionIDs);return document.layers.filter{ids.contains($0.id)}.map(\.id)}
  var canBeginLayerCollectionTransform:Bool{wantsLayerCollectionTransform && pathTarget==nil && !editingComponent && !editingMask && canSelectComponentTarget && LayerCollectionTransform.available(document,layerIDs:layerCollectionIDs)}
  func layerCollectionBounds(_ ids:[UUID])throws->IntRect{
    let boxes=try LayerCollectionTransform.roots(document,layerIDs:ids).map{try layerBounds($0)}
    guard let first=boxes.first else{throw CraftError.invalid("Choose layers with transformable content.")}
    let x=boxes.reduce(first.x){min($0,$1.x)},y=boxes.reduce(first.y){min($0,$1.y)},right=boxes.reduce(first.x+first.width){max($0,$1.x+$1.width)},bottom=boxes.reduce(first.y+first.height){max($0,$1.y+$1.height)}
    return .init(x:x,y:y,width:right-x,height:bottom-y)
  }
  var canBeginProjectiveLayerTransform:Bool{canBeginLayerCollectionTransform && ProjectiveLayerTransform.available(document,layerIDs:layerCollectionIDs)}
  var selectionTransformModes:[SelectionTransformMode]{SelectionTransformMode.allCases.filter{transformDraft?.supportsSelectionMode($0) != false}}
  func beginLayerCollectionTransform(){
    guard canBeginLayerCollectionTransform,let active=document.activeLayerID else{return}
    do{finishNumericField();finishLayerName();let ids=layerCollectionIDs;var draft=TransformDraft(layerID:active,bounds:try layerCollectionBounds(ids));draft.collectionLayerIDs=ids;draft.collectionViewIDs=groupSelectionIDs;draft.collectionProjective=ProjectiveLayerTransform.available(document,layerIDs:ids);draft.selection=true;draft.selectedPixels=true;draft.selectionQuad=draft.selectionCorners
      let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move;session.task=Task{await session.prepare()};status="Free Transform layers · Return applies · Escape cancels"
    }catch{self.error=error.localizedDescription}
  }
  func transformLayerCollection(angle:Double,horizontal:Bool,vertical:Bool){
    guard canBeginLayerCollectionTransform else{return}
    do{let ids=layerCollectionIDs,box=try layerCollectionBounds(ids),x=Double(box.x)+Double(box.width)/2,y=Double(box.y)+Double(box.height)/2,matrix=Transform2D.translation(x,y) * .rotation(angle) * .scale(horizontal ? -1:1,vertical ? -1:1) * .translation(-x,-y)
      performGeometry(.transformLayers(.init(layerIDs:ids,matrix:matrix)))
    }catch{self.error=error.localizedDescription}
  }
}
