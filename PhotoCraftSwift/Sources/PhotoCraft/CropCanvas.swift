import AppKit
import PhotoCraftCore

extension CraftCanvas {
  func drawCrop(in c: CGContext) {
    guard let draft = store.cropDraft,let request = try? draft.request(background:store.backgroundColor),let inverse = try? request.transform.inverted() else { return }
    let points = draft.frame.handles.map(viewPoint)
    let path = CGMutablePath();path.move(to:points[0]);for i in [2,4,6] { path.addLine(to:points[i]) };path.closeSubpath()
    c.saveGState();c.addRect(bounds);c.addPath(path);c.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor);c.fillPath(using:.evenOdd);c.restoreGState()
    if store.cropShowPreview,store.cropReadyDraft == draft,let image = store.cropPreviewImage {
      c.saveGState();c.addPath(path);c.clip();c.translateBy(x:imageRect.minX,y:imageRect.minY);c.scaleBy(x:scale,y:scale)
      c.concatenate(CGAffineTransform(a:inverse.a,b:inverse.b,c:inverse.c,d:inverse.d,tx:inverse.tx,ty:inverse.ty));c.translateBy(x:0,y:CGFloat(request.height));c.scaleBy(x:1,y:-1)
      c.interpolationQuality = scale >= 1 ? .none:.high;c.draw(image,in:CGRect(x:0,y:0,width:request.width,height:request.height));c.restoreGState()
    }
    c.saveGState();c.setStrokeColor(NSColor.white.cgColor);c.setLineWidth(1);c.addPath(path);c.strokePath()
    let frame = draft.frame
    for fraction in [1.0/3,2.0/3] {
      let a = frame.delta.point(Double(frame.bounds.x)+Double(frame.bounds.width)*fraction,Double(frame.bounds.y)),b = frame.delta.point(Double(frame.bounds.x)+Double(frame.bounds.width)*fraction,Double(frame.bounds.y+frame.bounds.height))
      c.move(to:viewPoint(CGPoint(x:a.x,y:a.y)));c.addLine(to:viewPoint(CGPoint(x:b.x,y:b.y)))
      let p = frame.delta.point(Double(frame.bounds.x),Double(frame.bounds.y)+Double(frame.bounds.height)*fraction),q = frame.delta.point(Double(frame.bounds.x+frame.bounds.width),Double(frame.bounds.y)+Double(frame.bounds.height)*fraction)
      c.move(to:viewPoint(CGPoint(x:p.x,y:p.y)));c.addLine(to:viewPoint(CGPoint(x:q.x,y:q.y)))
    };c.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor);c.strokePath()
    for point in points { c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:point.x-4,y:point.y-4,width:8,height:8));c.setStrokeColor(NSColor.black.cgColor);c.stroke(CGRect(x:point.x-4,y:point.y-4,width:8,height:8)) }
    if cropLineGesture,let start,let end { c.setStrokeColor(NSColor.systemYellow.cgColor);c.setLineWidth(2);c.move(to:viewPoint(start));c.addLine(to:viewPoint(end));c.strokePath() }
    c.restoreGState()
  }
  func beginCropGesture(_ event: NSEvent,at point: CGPoint) -> Bool {
    guard store.tool == .crop,!spaceHeld else { return false }
    if store.cropDraft == nil { store.beginCrop() }
    guard let draft = store.cropDraft else { return true }
    cropStart = draft;start = point;end = point;cropLineGesture = store.cropStraighten
    if !cropLineGesture {
      let nearest = draft.frame.handles.enumerated().min { hypot($0.element.x-point.x,$0.element.y-point.y) < hypot($1.element.x-point.x,$1.element.y-point.y) }
      if let nearest,hypot(nearest.element.x-point.x,nearest.element.y-point.y)*scale < 12 { cropHandle = nearest.offset }
      else { let local = try? draft.frame.delta.inverted().point(point.x,point.y);let box = draft.frame.bounds
        let inside = local.map { $0.x >= Double(box.x) && $0.y >= Double(box.y) && $0.x <= Double(box.x+box.width) && $0.y <= Double(box.y+box.height) } ?? false
        cropHandle = inside ? -1:8
      }
    };needsDisplay = true;return true
  }
  func dragCropGesture(_ event: NSEvent) -> Bool {
    guard var draft = cropStart,let start else { return false };end = docPoint(event)
    if !cropLineGesture { draft.frame = draft.frame.dragging(handle:cropHandle,from:start,to:end!,shift:event.modifierFlags.contains(.shift),option:event.modifierFlags.contains(.option));store.updateCrop(draft) }
    needsDisplay = true;return true
  }
  func endCropGesture(_ event: NSEvent) -> Bool {
    guard var draft = cropStart else { return false }
    if cropLineGesture,let start { draft.straighten(from:start,to:docPoint(event));store.updateCrop(draft);store.cropStraighten = false }
    return true
  }
  func cropKey(_ event: NSEvent) -> Bool {
    guard store.cropDraft != nil else { return false }
    switch event.keyCode {
    case 36,76:store.commitCrop();return true
    case 53:store.cancelCrop();cropStart = nil;start = nil;end = nil;return true
    case 123,124,125,126:
      if var draft = store.cropDraft { let step: Double = event.modifierFlags.contains(.shift) ? 10:1
        if event.keyCode == 123 { draft.frame.centerX -= step };if event.keyCode == 124 { draft.frame.centerX += step };if event.keyCode == 125 { draft.frame.centerY += step };if event.keyCode == 126 { draft.frame.centerY -= step };store.updateCrop(draft)
      };return true
    default:return false
    }
  }
}
