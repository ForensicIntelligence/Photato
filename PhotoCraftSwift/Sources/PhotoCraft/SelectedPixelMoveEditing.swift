import AppKit
import PhotoCraftCore

@MainActor extension EditorStore {
  var canBeginSelectedPixelMove:Bool {canBeginSelectedPixelTransform}
  @discardableResult func beginSelectedPixelMove(at point:CGPoint,modifiers:NSEvent.ModifierFlags)->Bool {
    guard canBeginSelectedPixelMove,point.x.isFinite,point.y.isFinite,point.x>=0,point.y>=0,point.x<Double(document.width),point.y<Double(document.height),document.selectionCoverage(x:Int(point.x),y:Int(point.y))>0,let bounds=document.selection,let id=document.activeLayerID else{return false}
    finishNumericField();finishLayerName();var draft=TransformDraft(layerID:id,bounds:bounds);draft.selection=true;draft.selectedPixels=true;draft.movingPixels=true;draft.copySelectedPixels=modifiers.contains(.option);draft.interpolation = .nearest;draft.selectedPixelsBackgroundColor=activeLayer?.isBackground == true ? backgroundColor:nil;draft.selectionQuad=draft.selectionCorners
    let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move;session.task=Task{await session.prepare()};status=draft.copySelectedPixels ? "Copy selected pixels":"Move selected pixels";return true
  }
  func updateSelectedPixelMove(_ original:TransformDraft,from start:CGPoint,to end:CGPoint,modifiers:NSEvent.ModifierFlags,zoom:Double) {
    guard original.movingPixels,transformDraft?.movingPixels == true,!geometryBusy else{return}
    var dx=Double(end.x-start.x),dy=Double(end.y-start.y)
    if !modifiers.contains(.shift){(dx,dy)=guideMoveOffset(original.bounds,dx:dx,dy:dy,zoom:zoom,modifiers:modifiers)}
    do {let offset=try SelectedPixelMoveRequest(layerID:original.layerID,dx:dx,dy:dy,constrain:modifiers.contains(.shift)).offset();var next=original.selectionApplying(.translation(Double(offset.x),Double(offset.y)));next.moveOffsetX=offset.x;next.moveOffsetY=offset.y;updateTransform(next)}catch{selectionTransform?.error=error.localizedDescription}
  }
  @discardableResult func nudgeSelectedPixels(keyCode:UInt16,modifiers:NSEvent.ModifierFlags)->Bool {
    guard tool == .move,[123,124,125,126].contains(keyCode),!modifiers.contains(.command),!modifiers.contains(.control),canBeginSelectedPixelMove,let layer=activeLayer else{return false}
    let step=modifiers.contains(.shift) ? 10.0:1.0,dx=keyCode==123 ? -step:keyCode==124 ? step:0,dy=keyCode==125 ? step:keyCode==126 ? -step:0
    performGeometry(.movePixels(.init(layerID:layer.id,dx:dx,dy:dy,copy:modifiers.contains(.option),backgroundColor:layer.isBackground ? backgroundColor:nil)));return true
  }
}
