import AppKit
import PhotoCraftCore

@MainActor extension EditorStore {
  var canBeginPixelMaskTransform:Bool {
    guard editingMask,!smartFilterMaskEditing,pathTarget==nil,!editingComponent,canManageSelection,
      let id=document.activeLayerID,maskEditingLayerID==id,selectedLayerIDs.isEmpty || selectedLayerIDs==[id] else{return false}
    return PixelMaskTransform.available(document,layerID:id)
  }
  func beginPixelMaskTransform(){
    guard canBeginPixelMaskTransform,let id=document.activeLayerID else{error="Unlink the pixel mask, select its thumbnail and deselect before Free Transform. Linked/selected/filter/channel masks need separate workflows.";return}
    do{
      finishNumericField();finishLayerName();var draft=TransformDraft(layerID:id,bounds:try PixelMaskTransform.bounds(document,layerID:id));draft.selection=true;draft.selectedPixels=true;draft.pixelMask=true;draft.pixelMaskViewMode=currentMaskView?.mode;draft.selectionQuad=draft.selectionCorners
      let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move;session.task=Task{await session.prepare()};status="Free Transform mask · Return applies · Escape cancels"
    }catch{self.error=error.localizedDescription}
  }
  func transformPixelMask(angle:Double,horizontal:Bool,vertical:Bool){
    guard canBeginPixelMaskTransform,let id=document.activeLayerID else{return}
    do{let box=try PixelMaskTransform.bounds(document,layerID:id),x=Double(box.x)+Double(box.width)/2,y=Double(box.y)+Double(box.height)/2,matrix=Transform2D.translation(x,y) * .rotation(angle) * .scale(horizontal ? -1:1,vertical ? -1:1) * .translation(-x,-y)
      performGeometry(.transformPixelMask(.init(layerID:id,matrix:.init(matrix))))
    }catch{self.error=error.localizedDescription}
  }
}
