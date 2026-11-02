import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct CropDraft: Equatable {
  var frame: TransformDraft
  var deletePixels = true
  var fill = CropRequest.Fill.transparent
  var ratio = "Free"
  var seed: UInt32 = 1
  init(document: CraftDocument) {
    let box = document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)
    frame = TransformDraft(layerID:document.id,bounds:box);frame.proportional = false;frame.allowsFlips = false
  }
  var width: Double { Double(frame.bounds.width)*frame.scaleX/100 }
  var height: Double { Double(frame.bounds.height)*frame.scaleY/100 }
  func request(background: Pixel) throws -> CropRequest {
    guard width.isFinite,height.isFinite,(1...Double(Surface.maxDimension)).contains(width),(1...Double(Surface.maxDimension)).contains(height),frame.centerX.isFinite,frame.centerY.isFinite,abs(frame.centerX) <= 1_000_000,abs(frame.centerY) <= 1_000_000 else { throw CraftError.invalid("Crop must be1–300,000 pixels per side.") }
    let w = Int(width.rounded()),h = Int(height.rounded());var value = CropRequest(x:Int(floor(frame.centerX-Double(w)/2)),y:Int(floor(frame.centerY-Double(h)/2)),width:w,height:h)
    value.angle = frame.angle;value.deleteCroppedPixels = deletePixels;value.fill = fill;value.seed = seed;value.backgroundColor = Pixel(background.r,background.g,background.b,1);try value.validate();return value
  }
  mutating func setRatio(_ name: String,document: CraftDocument) {
    ratio = name
    let values: [String:Double] = ["Original":Double(document.width)/Double(document.height),"1 : 1":1,"4 : 5":4/5,"5 : 7":5/7,"2 : 3":2/3,"16 : 9":16/9]
    guard let value = values[name] else { frame.proportional = false;return }
    frame.proportional = true
    if width/height > value { frame.scaleX = height*value/Double(frame.bounds.width)*100 } else { frame.scaleY = width/value/Double(frame.bounds.height)*100 }
  }
  mutating func straighten(from a: CGPoint,to b: CGPoint) {
    guard hypot(b.x-a.x,b.y-a.y) > 0.5 else { return }
    let degrees = atan2(b.y-a.y,b.x-a.x)*180/Double.pi
    frame.angle = degrees-(degrees/90).rounded()*90
  }
}
extension EditorStore {
  var canRetainCroppedPixels:Bool{document.restrictedMode==nil && document.inkMode==nil && !document.layers.contains(where:{$0.isBackground})}
  var cropState:[String:Any]{["available":canBeginCrop,"canRetainCroppedPixels":canRetainCroppedPixels,"workspaceOpen":cropDraft != nil,"previewBusy":cropBusy,"previewReady":cropDraft != nil && cropReadyDraft==cropDraft && cropPrepared != nil,"previewError":cropError as Any? ?? NSNull(),"maximumDimension":Surface.maxDimension,"maximumPixels":CropRequest.maximumPixels,"maximumPreviewDimension":1024]}
  var canBeginCrop: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && transformDraft == nil && !coalescingChanges && !editingMask && !editingComponent
  }
  func beginCrop() {
    guard cropDraft == nil,canBeginCrop else { return }
    cropDraft = CropDraft(document:document);cropShowPreview = true;cropStraighten = false;refreshCrop()
  }
  func updateCrop(_ draft: CropDraft) { guard cropDraft != nil else { return };cropDraft = draft;refreshCrop();cropRevision += 1 }
  func cancelCrop() {
    cropTask?.cancel();cropTask = nil;cropDraft = nil;cropReadyDraft = nil;cropPrepared = nil;cropPreviewImage = nil;cropBusy = false;cropError = nil;cropStraighten = false;cropRevision += 1
  }
  func refreshCrop() {
    cropTask?.cancel();cropReadyDraft = nil;cropPrepared = nil;cropError = nil
    guard let draft = cropDraft else { return };let original = document,background = backgroundColor,prepare=cropPreparation;cropBusy = true
    cropTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds:100_000_000)
        let request = try draft.request(background:background)
        let worker = Task.detached(priority:.userInitiated) { let edit = try prepare(request,original);return (edit,try CropPreparation.preview(edit.result)) }
        let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,self.cropDraft == draft,self.document == original else { return }
        self.cropPrepared = value.0;self.cropPreviewImage = value.1;self.cropReadyDraft = draft;self.cropBusy = false;self.cropRevision += 1
      } catch { guard !Task.isCancelled,let self,self.cropDraft == draft else { return };self.cropError = error.localizedDescription;self.cropBusy = false;self.cropRevision += 1 }
    }
  }
  @discardableResult func commitCrop() -> Bool {
    guard let draft = cropDraft,cropReadyDraft == draft,let edit = cropPrepared else { return false }
    cancelCrop();performGeometry(.cropDocument(edit),onSuccess:{ [weak self] in self?.fit() });return true
  }
}
