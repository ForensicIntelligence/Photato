import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class SelectionTransformSession {
  let original:CraftDocument
  var originalPath:SelectionContour?
  var pixelPreview:SelectedPixelTransformPreviewImage?
  private var pixelSource:SelectedPixelTransformPreviewSource?
  private let pixelLayerID:UUID?
  private let pixelBackgroundColor:Pixel?
  private let collectionLayerIDs:[UUID]?
  private let channelTarget:ChannelPlaneTarget?
  private let channelBackgroundValue:Float
  private let channelOverlay:Bool
  private let pixelMask:Bool
  private let maskViewMode:MaskViewMode?
  private let initialBounds:IntRect
  var previewPath:CGPath?
  var loading=true
  var previewBusy=false
  var committing=false
  var error:String?
  var task:Task<Void,Never>?
  var commitTask:Task<Void,Never>?
  private var latest:TransformDraft
  private var generation=0
  private(set) var closed=false
  init(_ document:CraftDocument,draft:TransformDraft){original=document;latest=draft;pixelLayerID=draft.selectedPixels ? draft.layerID:nil;pixelBackgroundColor=draft.selectedPixelsBackgroundColor;collectionLayerIDs=draft.collectionLayerIDs;channelTarget=draft.channelTarget;channelBackgroundValue=draft.channelBackgroundValue;channelOverlay=draft.channelOverlay;pixelMask=draft.pixelMask;maskViewMode=draft.pixelMaskViewMode;initialBounds=draft.bounds}
  func prepare()async {
    let original=original,pixels=pixelLayerID != nil,pixelMask=pixelMask,channelTarget=channelTarget,collectionLayerIDs=collectionLayerIDs,initialBounds=initialBounds
    do {
      let worker=Task.detached(priority:.userInitiated) { ()throws->(SelectionContour,SelectedPixelTransformPreviewSource?) in
        if collectionLayerIDs != nil || pixelMask || (channelTarget != nil && original.selection==nil){let path=CGPath(rect:CGRect(x:initialBounds.x,y:initialBounds.y,width:initialBounds.width,height:initialBounds.height),transform:nil);return(SelectionContour(path),try SelectedPixelTransformPreviewSource.prepare(original))}
        guard let mask=try original.coverageSelection(),let bounds=mask.bounds else{throw CraftError.invalid("The selection is empty.")}
        let path=try SelectionOutline.boundedPath(mask,region:bounds,sampleStep:max(1,(max(bounds.width,bounds.height)+511)/512))
        return (path,pixels ? try SelectedPixelTransformPreviewSource.prepare(original):nil)
      }
      let path=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
      guard !closed else{return};originalPath=path.0;pixelSource=path.1
    }catch{if !closed && !Task.isCancelled {self.error=error.localizedDescription}}
    loading=false;guard !closed,!Task.isCancelled else{return};refresh(latest)
  }
  func refresh(_ draft:TransformDraft) {
    latest=draft;generation+=1
    guard !closed,!committing,!loading,!previewBusy,let originalPath else{return}
    let generation=generation,pixelSource=pixelSource,pixelLayerID=pixelLayerID,pixelBackgroundColor=pixelBackgroundColor,pixelMask=pixelMask,maskViewMode=maskViewMode,channelTarget=channelTarget,channelBackgroundValue=channelBackgroundValue,channelOverlay=channelOverlay,collectionLayerIDs=collectionLayerIDs;previewBusy=true
    task=Task { [weak self] in
      do {
        let worker=Task.detached(priority:.userInitiated) { ()throws->(SelectionContour,SelectedPixelTransformPreviewImage?) in
          let projection=try draft.selectionProjection
          let contour:SelectionContour
          if let affine=try projection.affineValue() {
            var transform=CGAffineTransform(a:affine.a,b:affine.b,c:affine.c,d:affine.d,tx:affine.tx,ty:affine.ty)
            contour=SelectionContour(try SelectionContourCopy.copy(originalPath.path,transform:&transform))
          }else{
          let path=CGMutablePath();var failure:Error?
          originalPath.path.applyWithBlock { element in
            if failure != nil{return}
            do {try Task.checkCancellation();switch element.pointee.type {
              case .moveToPoint,.addLineToPoint:let p=element.pointee.points[0],q=try projection.point(p.x,p.y);if element.pointee.type == .moveToPoint{path.move(to:CGPoint(x:q.x,y:q.y))}else{path.addLine(to:CGPoint(x:q.x,y:q.y))}
              case .closeSubpath:path.closeSubpath()
              default:throw CraftError.invalid("Unexpected selection contour segment.")
            }}catch{failure=error}
          }
          if let failure{throw failure};contour=SelectionContour(path)
          }
          let preview=try pixelLayerID.flatMap{id in try pixelSource?.image(layerID:id,matrix:projection,interpolation:draft.interpolation,backgroundColor:pixelBackgroundColor,copy:draft.copySelectedPixels,pixelMask:pixelMask,maskViewMode:maskViewMode,channelTarget:channelTarget,channelBackgroundValue:channelBackgroundValue,channelOverlay:channelOverlay,collectionLayerIDs:collectionLayerIDs,collectionCopy:draft.movingLayers && draft.copyWholeLayers)}
          return (contour,preview)
        }
        let path=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        if let self,!self.closed,!self.committing,self.generation==generation{self.previewPath=path.0.path;self.pixelPreview=path.1;self.error=nil}
      }catch{if let self,!self.closed,!self.committing,self.generation==generation,!Task.isCancelled{self.error=error.localizedDescription}}
      guard let self else{return};self.previewBusy=false;if !Task.isCancelled,!self.closed,self.generation != generation{self.refresh(self.latest)}
    }
  }
  func close(){closed=true;task?.cancel();commitTask?.cancel()}
}
// Immutable copy failure is reported without a test-framework dependency.
private enum SelectionContourCopy {
  static func copy(_ path:CGPath,transform:inout CGAffineTransform)throws->CGPath {guard let result=path.copy(using:&transform) else{throw CraftError.invalid("Unable to transform the selection outline.")};return result}
}
@MainActor extension EditorStore {
  var canBeginSelectedPixelTransform:Bool {
    guard pathTarget==nil,!editingComponent,!editingMask,canManageSelection,let id=document.activeLayerID,selectedLayerIDs.isEmpty || selectedLayerIDs==[id] else{return false}
    return SelectedPixelTransform.available(document,layerID:id)
  }
  func beginSelectedPixelTransform() {
    guard canBeginSelectedPixelTransform,let bounds=document.selection,let id=document.activeLayerID else {error="Selected-pixel Free Transform requires one editable RGB raster or Background layer. Other target contexts remain unavailable.";return}
    finishNumericField();finishLayerName()
    var draft=TransformDraft(layerID:id,bounds:bounds);draft.selection=true;draft.selectedPixels=true;draft.selectedPixelsBackgroundColor=activeLayer?.isBackground == true ? backgroundColor:nil;draft.selectionQuad=draft.selectionCorners
    let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move
    session.task=Task{await session.prepare()};status="Free Transform · Return applies · Escape cancels"
  }
  var canBeginSelectionTransform:Bool {canModifySelection}
  func beginSelectionTransform() {
    guard canBeginSelectionTransform,let bounds=document.selection else{return}
    finishNumericField();finishLayerName()
    var draft=TransformDraft(layerID:document.id,bounds:bounds);draft.selection=true;draft.selectionQuad=draft.selectionCorners
    let session=SelectionTransformSession(document,draft:draft);selectionTransform=session;transformDraft=draft;tool = .move
    session.task=Task {await session.prepare()};status="Transform Selection · Return applies · Escape cancels"
  }
  func cancelSelectionTransform(){selectionTransform?.close();selectionTransform=nil}
  func commitSelectionTransform(_ draft:TransformDraft) {
    guard let session=selectionTransform,!session.committing else{return}
    let projection:ProjectiveTransform
    do{projection=try draft.selectionProjection}catch{session.error=error.localizedDescription;return}
    session.committing=true;session.task?.cancel();geometryBusy=true;let original=session.original,prepare=selectionTransformPreparation,pixelPrepare=selectedPixelTransformPreparation,movePrepare=selectedPixelMovePreparation,maskPrepare=pixelMaskTransformPreparation,channelPrepare=channelTransformPreparation,collectionPrepare=layerCollectionTransformPreparation,wholeMovePrepare=wholeLayerMovePreparation,generation=layerPanelGeneration
    session.commitTask=Task { [weak self,weak session] in
      do {
        let worker=Task.detached(priority:.userInitiated){
          let command:Command
          if draft.movingLayers,let ids=draft.collectionLayerIDs{command=try wholeMovePrepare(original,.init(layerIDs:ids,dx:draft.moveOffsetX,dy:draft.moveOffsetY,copy:draft.copyWholeLayers))}
          else if let ids=draft.collectionLayerIDs{let request:LayerCollectionTransformRequest;if let affine=try projection.affineValue(){request = .init(layerIDs:ids,matrix:affine,interpolation:draft.interpolation)}else{request = .init(layerIDs:ids,projection:projection,interpolation:draft.interpolation)};command=try collectionPrepare(original,request)}
          else if let target=draft.channelTarget{command=try channelPrepare(original,.init(target:target,matrix:projection,interpolation:draft.interpolation,backgroundValue:draft.channelBackgroundValue))}
          else if draft.pixelMask{command=try maskPrepare(original,.init(layerID:draft.layerID,matrix:projection,interpolation:draft.interpolation))}
          else if draft.movingPixels {command=try movePrepare(original,.init(layerID:draft.layerID,dx:Double(draft.moveOffsetX),dy:Double(draft.moveOffsetY),copy:draft.copySelectedPixels,backgroundColor:draft.selectedPixelsBackgroundColor))}
          else if draft.selectedPixels {command=try pixelPrepare(original,.init(layerID:draft.layerID,matrix:projection,interpolation:draft.interpolation,backgroundColor:draft.selectedPixelsBackgroundColor))}
          else {command=try prepare(original,projection,draft.interpolation)}
          return try PreparedEdit(command:command,document:original)
        }
        let edit=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,let session,self.selectionTransform === session,self.document==original,(!draft.pixelMask || (self.editingMask && !self.smartFilterMaskEditing && self.maskEditingLayerID==draft.layerID)),(draft.channelTarget==nil || self.editingChannel==draft.channelTarget),(draft.collectionLayerIDs==nil || self.groupSelectionIDs==(draft.collectionViewIDs ?? Set(draft.collectionLayerIDs!)) && Set(self.layerCollectionIDs)==Set(draft.collectionLayerIDs!)) else{throw CraftError.invalid("The document changed. Restart Transform Selection.")}
        try self.executeCompositePreparedEdit(edit,allowAuxiliary:draft.channelTarget != nil);if draft.movingLayers && draft.copyWholeLayers{self.selectMovedCopies(from:Set(original.layers.map(\.id)))};if self.document != original{self.onChange?(.changeDone)}
        self.transformDraft=nil;self.selectionTransform=nil;session.close();self.status=draft.movingPixels || draft.movingLayers ? "Move":draft.selectedPixels ? "Free Transform":"Transform Selection";self.render()
      }catch{if !Task.isCancelled {session?.error=error.localizedDescription;if draft.movingPixels || draft.movingLayers{self?.cancelTransform();self?.error=error.localizedDescription}}}
      session?.committing=false;if self?.layerPanelGeneration==generation {self?.geometryBusy=false}
    }
  }
  func chooseSelectionTransformMode(_ mode:SelectionTransformMode) {
    guard var draft=transformDraft,draft.selection,!geometryBusy,draft.supportsSelectionMode(mode) else{return};draft.selectionMode=mode;updateTransform(draft)
  }
}
extension AppDelegate {
  @objc func transformSelection(){store?.beginSelectionTransform()}
  private func chooseTransformMode(_ mode:SelectionTransformMode){
    if store?.transformDraft?.selection != true{store?.beginTransform()}
    store?.chooseSelectionTransformMode(mode)
  }
  @objc func transformScaleMode(){chooseTransformMode(.scale)}
  @objc func transformRotateMode(){chooseTransformMode(.rotate)}
  @objc func transformSkewMode(){chooseTransformMode(.skew)}
  @objc func transformDistortMode(){chooseTransformMode(.distort)}
  @objc func transformPerspectiveMode(){chooseTransformMode(.perspective)}
}
