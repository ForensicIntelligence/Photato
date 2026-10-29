import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class WarpWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false) throws -> CraftDocument {
    var d=try CraftDocument(width:48,height:40,depth:depth),s=try Surface(width:24,height:20,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<20 { for x in 0..<24 { let p=Pixel(Float(x)/24,Float(y)/20,0.3,1);if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } } }
    var layer=Layer(name:"Warp target",content:.raster(s));layer.x=12;layer.y=10;d.layers=[layer];d.activeLayerID=layer.id
    if smart { try SmartObjectIO.convert(in:d,selected:[layer.id]).apply(to:&d) };return d
  }
  func arch()->WarpDefinition { var w=WarpDefinition();w.style = .arch;w.bend=50;return w }
  func testPresetsMatchOriginalRustBothOrientations() throws {
    let url=Bundle.module.resourceURL!.appendingPathComponent("Fixtures/Warp/original.json")
    let oracle=try JSONDecoder().decode([String:[ [Double] ]].self,from:Data(contentsOf:url))
    for style in WarpStyle.allCases where style != .none && style != .custom {
      for vertical in [false,true] {
        var w=WarpDefinition();w.style=style;w.bend=43;w.horizontalDistortion=17;w.verticalDistortion = -23;w.vertical=vertical
        let key=style.rawValue.prefix(1).uppercased()+style.rawValue.dropFirst()+"-"+(vertical ? "True":"False"),expected=try XCTUnwrap(oracle[key])
        for (i,p) in [PathPoint(0,0),PathPoint(120,80),PathPoint(60,40),PathPoint(19,27),PathPoint(102,13)].enumerated() {
          let q=w.point(p.x,p.y,width:120,height:80);XCTAssertEqual(q.x,expected[i][0],accuracy:1e-9,key);XCTAssertEqual(q.y,expected[i][1],accuracy:1e-9,key)
        }
      }
    }
  }
  func testMeshExactSplitsRemovalAndValidation() throws {
    var w=try arch().custom(width:120,height:80),mesh=try XCTUnwrap(w.mesh);mesh.points[5].x += 8
    let original=mesh
    try mesh.split(at:0.37,vertical:true);try mesh.split(at:0.61,vertical:false)
    for y in 0...20 { for x in 0...20 { let a=original.point(Double(x)/20,Double(y)/20),b=mesh.point(Double(x)/20,Double(y)/20);XCTAssertEqual(a.x,b.x,accuracy:1e-9);XCTAssertEqual(a.y,b.y,accuracy:1e-9) } }
    try mesh.removeSplit(index:1,vertical:true);try mesh.removeSplit(index:1,vertical:false)
    for (a,b) in zip(original.points,mesh.points) { XCTAssertEqual(a.x,b.x,accuracy:1e-9);XCTAssertEqual(a.y,b.y,accuracy:1e-9) }
    XCTAssertThrowsError(try mesh.split(at:0,vertical:true));mesh.us=[0,0,1];XCTAssertThrowsError(try mesh.validate())
    w.mesh=nil;XCTAssertThrowsError(try w.validate());w=arch();w.bend = .nan;XCTAssertThrowsError(try w.validate())
  }
  func testRasterTranslationAnalyticalAllDepthsAndHDR() throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id
      var w=try WarpDefinition().custom(width:24,height:20);w.interpolation = .nearest
      w.mesh!.points=w.mesh!.points.map{PathPoint($0.x+3,$0.y+2)}
      let edit=try WarpEdit.prepare(d,layerID:id,warp:w),layer=edit.result.layers[0]
      XCTAssertEqual(layer.x,15);XCTAssertEqual(layer.y,12)
      guard case .raster(let a)=d.layers[0].content,case .raster(let b)=layer.content else { return XCTFail() }
      XCTAssertEqual(b.width,24);XCTAssertEqual(b.height,20)
      for y in 0..<20 { for x in 0..<24 { XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:x,y:y)) } }
      var session=EditorSession(document:d);try session.execute(.warp(edit));try session.undo();XCTAssertTrue(session.document == d);try session.redo();XCTAssertTrue(session.document == edit.result)
    }
    var s=try Surface(width:3,height:3,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:1,y:1,Pixel(4.25,-0.2,2.5,0.7))
    let p=WarpRaster.sample(s,PathPoint(1.5,1.5),method:.bicubic);XCTAssertEqual(p.r,4.25,accuracy:1e-6);XCTAssertEqual(p.g,-0.2,accuracy:1e-6);XCTAssertEqual(p.a,0.7,accuracy:1e-6)
  }
  func testSmartSourceRetentionNative24ReplacementAndRasterization() throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth,smart:true),id=d.layers[0].id
      var session=EditorSession(document:d);try session.execute(.warp(WarpEdit.prepare(d,layerID:id,warp:arch())))
      let warped=session.document;XCTAssertEqual(warped.layers[0].content,d.layers[0].content);XCTAssertEqual(warped.layers[0].smartObject,d.layers[0].smartObject);XCTAssertEqual(warped.minimumArchiveVersion,24)
      for data in [try NativeArchive.encode(warped),try NativeArchive.encodeChunked(warped)] { XCTAssertTrue(try NativeArchive.decode(data) == warped) }
      let output=try Renderer.composite(warped);XCTAssertNotEqual(output,try Renderer.composite(d))
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(warped,format:.psd))
      let pixels=try Renderer.layerSurface(warped.layers[0],in:warped);try session.execute(.rasterize(id,pixels));XCTAssertNil(session.document.layers[0].smartObject);XCTAssertNil(session.document.layers[0].warp)
      XCTAssertEqual(try Renderer.composite(session.document),output)
      try session.undo();XCTAssertTrue(session.document == warped)
      try session.execute(.resetSmartObjectTransform(id));XCTAssertNil(session.document.layers[0].warp);try session.undo();XCTAssertTrue(session.document == warped)
      try session.execute(.warp(WarpEdit.prepare(session.document,layerID:id,warp:WarpDefinition())));XCTAssertTrue(session.document == d)
    }
    var d=try fixture(smart:true),w=try arch().custom(width:24,height:20);w.mesh!.points[5].x += 2
    try Command.warp(WarpEdit.prepare(d,layerID:d.layers[0].id,warp:w)).apply(to:&d)
    let source=try CraftDocument(width:48,height:40),before=d.layers[0].warp!.mesh!.points
    try SmartObjectIO.replacement(in:d,layerID:d.layers[0].id,source:source,preserveSize:true).apply(to:&d)
    XCTAssertEqual(d.layers[0].warp!.mesh!.points[5].x,before[5].x*2,accuracy:1e-9)
  }
  func testMasksFilterOrderBoundsAndUnsupportedContexts() throws {
    var d=try fixture(smart:true),mask=try Surface(width:24,height:20,fill:.white);mask.setPixel(x:10,y:10,.black)
    d.layers[0].mask=mask;let id=d.layers[0].id
    var w=try WarpDefinition().custom(width:24,height:20);w.interpolation = .nearest;w.mesh!.points=w.mesh!.points.map{PathPoint($0.x+3,$0.y+2)}
    let edit=try WarpEdit.prepare(d,layerID:id,warp:w),baked=try SmartFilterEngine.renderedLayer(edit.result.layers[0],in:edit.result)
    XCTAssertEqual(baked.mask?.pixel(x:10,y:10).r,0)
    var filtered=edit.result;try SmartFilterEngine.append(RasterFilter(.mosaic),to:id,in:&filtered)
    let filteredPixels=try Renderer.composite(filtered);XCTAssertNotEqual(filteredPixels,try Renderer.composite(edit.result))
    var unlinked=d;unlinked.layers[0].maskProperties=MaskProperties();unlinked.layers[0].maskProperties?.linked=false
    let fixed=try WarpEdit.prepare(unlinked,layerID:id,warp:w);let result=try SmartFilterEngine.renderedLayer(fixed.result.layers[0],in:fixed.result)
    XCTAssertEqual(result.maskCoordinateTransform,unlinked.layers[0].maskCoordinateTransform)
    d.layers[0].locked=true;XCTAssertThrowsError(try WarpEdit.prepare(d,layerID:id,warp:w));d.layers[0].locked=false
    d.selection=IntRect(x:0,y:0,width:2,height:2);XCTAssertThrowsError(try WarpEdit.prepare(d,layerID:id,warp:w))
    var changed=edit.source;changed.name="Changed";XCTAssertThrowsError(try edit.applied(to:changed))
  }
  func testRasterWarpRetainsDisabledMaskPixelsAndEditableSettings() throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth),mask=try Surface(width:24,height:20,depth:depth,fill:.white)
      mask.setPixel(x:10,y:10,Pixel(0.25,0.25,0.25,1));d.layers[0].mask=mask
      var props=MaskProperties();props.enabled=false;props.inverted=true;props.density=0.6;props.feather=2;props.outside=0.3
      d.layers[0].maskProperties=props
      var w=try WarpDefinition().custom(width:24,height:20);w.interpolation = .nearest;w.mesh!.points=w.mesh!.points.map{PathPoint($0.x+3,$0.y+2)}
      let edit=try WarpEdit.prepare(d,layerID:d.layers[0].id,warp:w),layer=edit.result.layers[0]
      XCTAssertEqual(layer.maskProperties,props);XCTAssertEqual(layer.mask?.depth,depth)
      XCTAssertEqual(try XCTUnwrap(layer.mask).pixel(x:10,y:10).r,mask.pixel(x:10,y:10).r,accuracy:0.00001)
      XCTAssertEqual(try MaskSampler(layer:layer).coverage(x:25.5,y:22.5),1)
      var revealed=layer;revealed.maskProperties?.enabled=true;revealed.maskProperties?.inverted=false;revealed.maskProperties?.density=1;revealed.maskProperties?.feather=0
      XCTAssertEqual(try MaskSampler(layer:revealed).coverage(x:25.5,y:22.5),mask.pixel(x:10,y:10).r,accuracy:0.00001)
    }
  }
  @MainActor func testNativePreviewLocalUndoCancelCommitAndAPI() async throws {
    let d=try fixture(smart:true),id=d.layers[0].id,store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    store.beginWarp();let model=try XCTUnwrap(store.warpDraft);model.change(arch());await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    XCTAssertTrue(store.document == d);model.undo();await model.task?.value;XCTAssertTrue(model.settings.isIdentity);model.redo();await model.task?.value
    let view=NSHostingView(rootView:WarpSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:820,height:610);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,700)
    await model.task?.value
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();try png.write(to:root.appendingPathComponent("artifacts/warp-offscreen.png")) } }
    let expected=try XCTUnwrap(model.edit).result;store.commitWarp();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertTrue(store.document == expected);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();store.renderTask?.cancel();XCTAssertTrue(store.document == d);store.beginWarp();let cancelled=try XCTUnwrap(store.warpDraft);cancelled.change(arch());let pending=cancelled.task;store.cancelWarp();await pending?.value;XCTAssertNil(store.warpDraft);XCTAssertTrue(store.document == d)
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,doc in
      doc.store.session=EditorSession(document:d);service.setDocumentTransfersEnabled(true);try service.share(doc)
      let api=AutomationTests(),params:[String:Any]=["layerID":id.uuidString,"settings":["style":"arch","bend":50]],revision=service.revision(doc.store)
      let code=try await api.edit(service,doc,"layer.warp",params);XCTAssertEqual(code,200);XCTAssertTrue(doc.store.document == expected)
      let stale=try await api.edit(service,doc,"layer.warp",params,revision:revision);XCTAssertEqual(stale,409)
      let invalid=try await api.edit(service,doc,"layer.warp",["layerID":id.uuidString,"settings":["style":"custom"]]);XCTAssertEqual(invalid,400)
      let share=try XCTUnwrap(service.shares.first?.id)
      let rejected=try await api.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"23"]);XCTAssertEqual(rejected.0.statusCode,422)
      let saved=try await api.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"24"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1) == expected)
      doc.store.beginWarp();let busy=try await api.edit(service,doc,"layer.warp",params);XCTAssertEqual(busy,409);doc.store.cancelWarp()
      let undo=try await api.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(doc.store.document == d)
    }
  }
}
