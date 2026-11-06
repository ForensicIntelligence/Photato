import AppKit
import PhotoCraftCore
import PhotoCraftImaging

/// NSTextView retains native rich input/IME/Undo; its visible geometry follows the path.
@MainActor final class CanvasPathTypeEditor:CanvasTypeEditor {
  static func supports(_ text:TextContent)->Bool {
    text.typography?.writingOrientation == .horizontal && text.typography?.geometry.map{[.path,.circle,.arch,.bow].contains($0.mode)} == true
  }
  private(set) var pathGeometry:PathTextEditingGeometry?
  private(set) var pathError:String?
  private(set) var pathRendering=false
  private(set) var previewTask:Task<Void,Never>?
  private var image:CGImage?
  private var rasterRect=CGRect.zero
  private var lastText:TextContent?
  private var lastDPI:Double?
  private var generation=0
  private var selectionAnchor=0
  private var blinkOn=true
  private var blinkTimer:Timer?
  var sourceToView=CGAffineTransform.identity {didSet{needsDisplay=true;inputContext?.invalidateCharacterCoordinates()}}
  override var isOpaque:Bool{false}
  isolated deinit{previewTask?.cancel();blinkTimer?.invalidate()}
  override func configureContainer() {
    super.configureContainer()
    guard let store,let draft=store.typeEditingDraft,draft.id==draftID else{return}
    var text=draft.content;text.importedAppearance=nil
    let dpi=store.document.pixelsPerInch
    guard lastText != text || lastDPI != dpi else{return}
    lastText=text;lastDPI=dpi;generation+=1;let current=generation
    previewTask?.cancel();pathError=nil
    do{pathGeometry=try ShapedTextLayout.pathEditingGeometry(text,dpi:dpi)}
    catch{pathGeometry=nil;pathError=error.localizedDescription;image=nil;pathRendering=false;needsDisplay=true;return}
    pathRendering=true;needsDisplay=true
    let document=store.document
    previewTask=Task{[weak self] in
      do{
        let worker=Task.detached(priority:.userInitiated){[text,document,dpi] ()throws->(CGImage,CGRect) in
          let m=try NativeTextLayout.editingMetrics(text,dpi:dpi),surface=try NativeTextLayout.render(text,document:document)
          return(try RasterIO.displayImage(surface),CGRect(x:m.origin.x,y:m.origin.y,width:Double(m.width),height:Double(m.height)))
        }
        let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        guard let self,self.generation==current,self.store?.typeEditingDraft?.id==self.draftID,!Task.isCancelled else{return}
        self.image=result.0;self.rasterRect=result.1;self.pathRendering=false;self.needsDisplay=true
      }catch{
        guard let self,self.generation==current,!Task.isCancelled else{return}
        self.pathError=error.localizedDescription;self.pathRendering=false;self.image=nil;self.needsDisplay=true
      }
    }
  }
  func stopPathPreview(){generation+=1;previewTask?.cancel();previewTask=nil;blinkTimer?.invalidate();blinkTimer=nil;pathRendering=false;lastText=nil}
  override func viewWillMove(toWindow newWindow:NSWindow?) {
    if newWindow==nil{stopPathPreview()}
    super.viewWillMove(toWindow:newWindow)
  }
  override func viewDidMoveToWindow(){super.viewDidMoveToWindow();if window != nil{configureContainer()}}
  override func becomeFirstResponder()->Bool {
    let result=super.becomeFirstResponder()
    if result{blinkOn=true;blinkTimer?.invalidate();blinkTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self]_ in MainActor.assumeIsolated{self?.blinkOn.toggle();self?.needsDisplay=true}}}
    return result
  }
  override func resignFirstResponder()->Bool {
    let result=super.resignFirstResponder();if result{blinkTimer?.invalidate();blinkTimer=nil};return result
  }
  override func textViewDidChangeSelection(_ notification:Notification) {
    super.textViewDidChangeSelection(notification);blinkOn=true;needsDisplay=true;inputContext?.invalidateCharacterCoordinates()
  }
  func viewPoint(_ p:PathPoint)->CGPoint{CGPoint(x:p.x,y:p.y).applying(sourceToView)}
  func modelPoint(_ p:NSPoint)->PathPoint{let p=p.applying(sourceToView.inverted());return .init(p.x,p.y)}
  override func hitTest(_ point:NSPoint)->NSView? {
    let local=convert(point,from:superview)
    guard bounds.contains(local),store?.typeEditingDraft?.id==draftID,let geometry=pathGeometry else{return nil}
    let height=geometry.carets.map{hypot($0.top.x-$0.bottom.x,$0.top.y-$0.bottom.y)}.max() ?? 20
    return geometry.baseline.nearestFraction(to:modelPoint(local),tolerance:max(12,height)) == nil ? nil:self
  }
  override func drawInsertionPoint(in rect:NSRect,color:NSColor,turnedOn flag:Bool){needsDisplay=true}
  override func resetCursorRects(){addCursorRect(visibleRect,cursor:.iBeam)}
  override func characterIndexForInsertion(at point:NSPoint)->Int{pathGeometry?.insertionIndex(at:modelPoint(point)) ?? 0}
  override func characterIndex(for point:NSPoint)->Int {
    guard let window else{return 0};return characterIndexForInsertion(at:convert(window.convertPoint(fromScreen:point),from:nil))
  }
  override func firstRect(forCharacterRange range:NSRange,actualRange:NSRangePointer?)->NSRect {
    guard let window,let geometry=pathGeometry else{return .zero}
    let index=min(geometry.utf16Count,range.location==NSNotFound ? selectedRange().location:range.location)
    guard let caret=geometry.caret(at:index)else{return .zero}
    actualRange?.pointee=NSRange(location:caret.utf16Index,length:0)
    let a=viewPoint(caret.top),b=viewPoint(caret.bottom)
    let rect=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:max(1,abs(a.x-b.x)),height:max(1,abs(a.y-b.y)))
    return window.convertToScreen(convert(rect,to:nil))
  }
  override func mouseDown(with event:NSEvent) {
    window?.makeFirstResponder(self)
    let index=characterIndexForInsertion(at:convert(event.locationInWindow,from:nil))
    selectionAnchor=event.modifierFlags.contains(.shift) ? selectedRange().location:index
    var range=NSRange(location:min(selectionAnchor,index),length:abs(index-selectionAnchor))
    if event.clickCount>1{range=selectionRange(forProposedRange:NSRange(location:index,length:0),granularity:event.clickCount>2 ? .selectByParagraph:.selectByWord)}
    setSelectedRange(range);blinkOn=true;needsDisplay=true
  }
  override func mouseDragged(with event:NSEvent) {
    let index=characterIndexForInsertion(at:convert(event.locationInWindow,from:nil))
    setSelectedRange(NSRange(location:min(selectionAnchor,index),length:abs(index-selectionAnchor)));needsDisplay=true
  }
  override func mouseUp(with event:NSEvent){needsDisplay=true}
  override func draw(_ dirtyRect:NSRect) {
    guard let c=NSGraphicsContext.current?.cgContext,let geometry=pathGeometry else{return}
    c.saveGState();defer{c.restoreGState()};c.clip(to:bounds)
    func polygon(_ points:[PathPoint]) {
      guard let first=points.first else{return};c.beginPath();c.move(to:viewPoint(first));for p in points.dropFirst(){c.addLine(to:viewPoint(p))};c.closePath();c.fillPath()
    }
    c.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.3).cgColor)
    for strip in geometry.selectionStrips(selectedRange()){polygon(strip)}
    if let image {
      c.saveGState();c.concatenate(sourceToView);c.translateBy(x:rasterRect.minX,y:rasterRect.maxY);c.scaleBy(x:1,y:-1)
      c.draw(image,in:CGRect(origin:.zero,size:rasterRect.size));c.restoreGState()
    }
    c.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.65).cgColor);c.setLineWidth(1)
    c.beginPath();if let first=geometry.baseline.points.first{c.move(to:viewPoint(first));for point in geometry.baseline.points.dropFirst(){c.addLine(to:viewPoint(point))}};c.strokePath()
    if hasMarkedText(){c.setFillColor(NSColor.labelColor.withAlphaComponent(0.2).cgColor);for strip in geometry.selectionStrips(markedRange()){polygon(strip)}}
    if selectedRange().length==0,window?.firstResponder === self,blinkOn,let caret=geometry.caret(at:selectedRange().location) {
      c.setStrokeColor(insertionPointColor.cgColor);c.setLineWidth(1.5);c.move(to:viewPoint(caret.top));c.addLine(to:viewPoint(caret.bottom));c.strokePath()
    }
    if geometry.overset,let last=geometry.carets.last(where:{$0.visible}) {
      let p=viewPoint(last.baseline);c.setStrokeColor(NSColor.systemRed.cgColor);c.stroke(CGRect(x:p.x-4,y:p.y-4,width:8,height:8));c.move(to:CGPoint(x:p.x-2,y:p.y));c.addLine(to:CGPoint(x:p.x+2,y:p.y));c.move(to:CGPoint(x:p.x,y:p.y-2));c.addLine(to:CGPoint(x:p.x,y:p.y+2));c.strokePath()
    }
  }
}
