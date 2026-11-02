import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

enum ColorRangePreview:String,CaseIterable,Sendable {
  case none="None",grayscale="Grayscale",black="Black Matte",white="White Matte",quickMask="Quick Mask"
}
enum ColorRangeSampler:String,CaseIterable,Sendable { case sample,add,subtract }

@MainActor @Observable final class ColorRangeWorkspace:Identifiable {
  let id=UUID()
  let original:CraftDocument
  var settings=ColorRangeSettings()
  var sampler:ColorRangeSampler = .sample
  var preview:ColorRangePreview = .none
  var showImage=false
  var sourceImage:CGImage?
  var selectionImage:CGImage?
  var previewImage:CGImage?
  var input:ColorRangeInput?
  var mask:SelectionMask?
  var error:String?
  var loading=true
  var rendering=false
  var committing=false
  var task:Task<Void,Never>?
  var commitTask:Task<Void,Never>?
  private var generation=0
  private(set) var closed=false
  var ready:Bool { !closed && !loading && !committing && input != nil }
  var canCommit:Bool { ready && !rendering && mask != nil && error == nil }
  init(_ original:CraftDocument) { self.original=original }
  func prepare(using preparation:@escaping @Sendable (CraftDocument)throws->ColorRangeInput) async {
    do {
      let original=original
      let worker=Task.detached(priority:.userInitiated) { ()throws->(ColorRangeInput,CGImage) in
        let input=try preparation(original),request=try RasterPreviewRequest.overview(width:original.width,height:original.height)
        return (input,try RasterIO.displayImage(request.reducing(input.guide)))
      }
      let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
      try Task.checkCancellation();guard !closed else{return}
      input=result.0;sourceImage=result.1
    } catch { if !closed && !Task.isCancelled { self.error=error.localizedDescription } }
    loading=false;if !closed && input != nil { refresh() }
  }
  func change(_ value:ColorRangeSettings) {
    guard ready else{return}
    do {try value.validate();settings=value;error=nil;refresh()}catch{self.error=error.localizedDescription}
  }
  func sample(x:Double,y:Double,mode:ColorRangeSampler) {
    guard ready,settings.kind == .sampled,let input,x>=0,y>=0,x<Double(original.width),y<Double(original.height) else{return}
    let x=min(original.width-1,Int(x)),y=min(original.height-1,Int(y)),p=input.guide.pixel(x:x,y:y)
    guard p.a>0 else {error="Sample a visible image pixel.";return}
    var next=settings
    let sample=ToneColorSample(color:Pixel(p.r,p.g,p.b),point:.init((Double(x)+0.5)/Double(original.width),(Double(y)+0.5)/Double(original.height)),subtract:mode == .subtract)
    if mode == .sample {next.samples=[sample]} else {
      guard next.samples.count<128 else {error="Color Range supports 128 samples. Use the first eyedropper to start again.";return}
      // Position the initial default sample when entering localized mode for the first time.
      next.samples.append(sample)
    }
    change(next)
  }
  func setLocalized(_ enabled:Bool) {
    var next=settings;next.localized=enabled
    if enabled { for i in next.samples.indices where next.samples[i].point == nil {next.samples[i].point = .init(0.5,0.5)} }
    change(next)
  }
  func reset() {change(ColorRangeSettings())}
  func refresh() {
    generation+=1;guard ready,!rendering,let input else{return}
    let generation=generation,settings=settings,preview=preview
    rendering=true
    task=Task { [weak self] in
      do {
        let worker=Task.detached(priority:.userInitiated) { ()throws->(SelectionMask,CGImage,CGImage) in
          let mask=try input.mask(settings),request=try RasterPreviewRequest.overview(width:mask.width,height:mask.height)
          let guide=try request.reducing(input.guide),coverage=try request.reducing(mask.coverageSurface())
          let selection=try RasterIO.displayImage(coverage)
          var out=guide
          for y in 0..<out.height {try Task.checkCancellation();for x in 0..<out.width {
            let p=guide.pixel(x:x,y:y),a=coverage.pixel(x:x,y:y).r
            let checker:Float=(x/12+y/12)%2 == 0 ? 0.7:0.55
            let base=p.rgb*p.a+SIMD3<Float>(repeating:checker*(1-p.a))
            let rgb:SIMD3<Float>
            switch preview {
            case .none:rgb=base
            case .grayscale:rgb=SIMD3(repeating:a)
            case .black:rgb=p.rgb*p.a*a
            case .white:rgb=p.rgb*p.a*a+SIMD3(repeating:1-p.a*a)
            case .quickMask:let k=(1-a)*0.5;rgb=base*(1-k)+SIMD3(1,0,0)*k
            }
            out.setPixel(x:x,y:y,Pixel(rgb.x,rgb.y,rgb.z))
          }}
          return (mask,selection,try RasterIO.displayImage(out))
        }
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        if let self,!self.closed,self.generation==generation {self.mask=result.0;self.selectionImage=result.1;self.previewImage=result.2;self.error=nil}
      }catch{if let self,!self.closed,self.generation==generation,!Task.isCancelled {self.error=error.localizedDescription}}
      guard let self else{return};self.rendering=false
      if !self.closed && self.generation != generation { self.refresh() }
    }
  }
  func load(_ data:Data) {do{change(try ColorRangeSettings.preset(data))}catch{self.error=error.localizedDescription}}
  func close() {closed=true;task?.cancel();commitTask?.cancel()}
}

@MainActor extension EditorStore {
  var canBeginColorRange:Bool {canEditFileInfo && !editingComponent && !editingMask && !smartFilterMaskEditing && document.colorMode == .rgb}
  func beginColorRange() {
    guard canBeginColorRange else{return};finishNumericField();finishLayerName()
    let draft=ColorRangeWorkspace(document);draft.settings=colorRangeSettings;colorRangeDraft=draft;let preparation=colorRangePreparation;draft.task=Task {await draft.prepare(using:preparation)}
  }
  func cancelColorRange() {colorRangeDraft?.close();colorRangeDraft=nil;render()}
  func commitColorRange() {
    guard let draft=colorRangeDraft,draft.canCommit,let input=draft.input else{return}
    draft.committing=true;let settings=draft.settings
    draft.commitTask=Task { [weak self,weak draft] in
      do {
        let worker=Task.detached(priority:.userInitiated) {try PreparedEdit(command:input.command(settings),document:input.original)}
        let edit=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self,let draft,self.colorRangeDraft === draft,self.document == input.original else {throw CraftError.invalid("The document changed. Reopen Color Range.")}
        try self.executeCompositePreparedEdit(edit)
        if self.document != input.original {self.onChange?(.changeDone)}
        self.colorRangeSettings=settings;self.colorRangeDraft=nil;draft.close();self.status="Color Range";self.render()
      }catch{if !Task.isCancelled {draft?.error=error.localizedDescription}}
      draft?.committing=false
    }
  }
}
extension AppDelegate { @objc func colorRange() {store?.beginColorRange()} }
