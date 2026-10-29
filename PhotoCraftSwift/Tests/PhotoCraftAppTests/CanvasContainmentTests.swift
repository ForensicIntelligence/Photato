import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class CanvasContainmentTests:XCTestCase {
  @MainActor func testZoomPanAndResizeKeepImageShadowAndOverlaysInsideViewport()throws {
    let document=try CraftNSDocument.blankModel(width:1200,height:800),store=EditorStore(document:document)
    defer { store.renderTask?.cancel() }
    store.showRulers=true;store.showLayerBounds=true;store.tool = .move
    let canvas=CraftCanvas(store:store),width=360,height=260
    for (index,entry) in [(CGSize(width:220,height:160),1.0,CGSize.zero),(CGSize(width:220,height:160),4.0,CGSize(width:-260,height:-220)),(CGSize(width:140,height:95),2.0,CGSize(width:170,height:120))].enumerated() {
      canvas.frame=CGRect(origin:.zero,size:entry.0);store.zoom=entry.1;store.pan=entry.2
      let context=try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(red:0.85,green:0.05,blue:0.7,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
      let baseline=Data(bytes:try XCTUnwrap(context.data),count:width*height*4)
      NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
      context.translateBy(x:60,y:50);canvas.draw(canvas.bounds)
      NSGraphicsContext.restoreGraphicsState()
      let actual=Data(bytes:try XCTUnwrap(context.data),count:width*height*4),viewport=CGRect(x:60,y:50,width:entry.0.width,height:entry.0.height)
      var changedOutside=0,changedInside=0
      for y in 0..<height { for x in 0..<width { let offset=(y*width+x)*4
        if actual[offset..<offset+4] != baseline[offset..<offset+4] {
          if viewport.contains(CGPoint(x:Double(x)+0.5,y:Double(height-y)-0.5)) { changedInside+=1 } else { changedOutside+=1 }
        }
      } }
      XCTAssertEqual(changedOutside,0,"Drawing escaped viewport in zoom/pan/resize scenario \(index)")
      XCTAssertGreaterThan(changedInside,100,"Viewport content must still draw")
      if let image=context.makeImage(),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/canvas-containment")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try png.write(to:root.appendingPathComponent("case\(index)-\(UUID()).png"))
      }
    }
    XCTAssertTrue(canvas.clipsToBounds);XCTAssertTrue(canvas.layer?.masksToBounds == true)
    XCTAssertEqual(store.document,document);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
