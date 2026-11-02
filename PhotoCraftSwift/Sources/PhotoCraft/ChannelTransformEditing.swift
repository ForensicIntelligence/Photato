import AppKit
import PhotoCraftCore

@MainActor extension EditorStore{
  var channelTransformBackgroundValue:Float{unit(0.2126*backgroundColor.r+0.7152*backgroundColor.g+0.0722*backgroundColor.b)}
  var canBeginChannelTransform:Bool{
    guard let target=editingChannel,isCompositeColorTarget,!editingMask,!smartFilterMaskEditing,pathTarget==nil,canEditChannels else{return false}
    return ChannelTransform.available(document,target:target)
  }
  func beginChannelTransform(){
    guard canBeginChannelTransform,let target=editingChannel else{error="Choose an auxiliary channel or Quick Mask and finish the current interaction before Free Transform.";return}
    finishNumericField();finishLayerName();var draft=TransformDraft(layerID:document.activeLayerID ?? document.id,bounds:document.selection ?? .init(x:0,y:0,width:document.width,height:document.height));draft.channelTarget=target;draft.channelBackgroundValue=channelTransformBackgroundValue;draft.channelOverlay=target == .quickMask || alphaOverlay;draft.selection=true;draft.selectedPixels=true;draft.selectionQuad=draft.selectionCorners
    let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move;session.task=Task{await session.prepare()};status="Free Transform channel · Return applies · Escape cancels"
  }
  func transformChannel(angle:Double,horizontal:Bool,vertical:Bool){
    guard canBeginChannelTransform,let target=editingChannel else{return}
    let box=document.selection ?? .init(x:0,y:0,width:document.width,height:document.height),x=Double(box.x)+Double(box.width)/2,y=Double(box.y)+Double(box.height)/2,matrix=Transform2D.translation(x,y) * .rotation(angle) * .scale(horizontal ? -1:1,vertical ? -1:1) * .translation(-x,-y)
    performGeometry(.transformChannel(.init(target:target,matrix:.init(matrix),backgroundValue:channelTransformBackgroundValue)))
  }
}
