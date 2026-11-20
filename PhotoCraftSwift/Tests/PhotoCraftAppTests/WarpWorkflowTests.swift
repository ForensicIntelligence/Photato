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
    for style in WarpStyle.analyticPresets {
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
      let photoshop = try PSDCodec.read(PSDCodec.writeRasterLayers(warped, format: .psd))
      XCTAssertEqual(photoshop.layers[0].warp, arch())
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
    XCTAssertEqual(model.guidePoint(0.38, 0.24), arch().point(0.38 * 24, 0.24 * 20, width: 24, height: 20))
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

  @MainActor func testReopenedQuiltCanBeEditedInWarpWorkspaceAndBothAPIsReportSavedPlacement() async throws {
    var source = try CraftDocument(width: 100, height: 80)
    let pixels = try Surface(width: 20, height: 16, fill: Pixel(0.2, 0.6, 0.4))
    let original = try RasterIO.encoded(pixels)
    var layer = try SmartObjectIO.placed(data: original, fileName: "Warp artwork.png", in: source, fit: false)
    layer.x = 18; layer.y = 15
    layer.sourceProjection = try SelectionTransform.projection(
      bounds: .init(x: 0, y: 0, width: 20, height: 16),
      corners: [.init(0, 0), .init(24, 2), .init(28, 25), .init(-2, 22)])
    var warp = try WarpDefinition().custom(width: 20, height: 16)
    try warp.mesh?.split(at: 0.25, vertical: true)
    warp.mesh?.points[0].x = -4
    layer.warp = warp
    source.layers = [layer]; source.activeLayerID = layer.id
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: .psd))
    XCTAssertNil(DocumentIO.persistenceIssue(reopened, format: .psd))
    XCTAssertNil(DocumentIO.persistenceIssue(reopened, format: .psb))

    let store = EditorStore(document: reopened)
    defer { store.cancelWarp(); store.renderTask?.cancel() }
    store.beginWarp()
    let workspace = try XCTUnwrap(store.warpDraft)
    XCTAssertEqual(workspace.settings, warp)
    workspace.refresh()
    await workspace.task?.value
    XCTAssertEqual(workspace.edit?.result, reopened)
    let view = NSHostingView(rootView: WarpSheet(store: store, model: workspace))
    view.frame = NSRect(x: 0, y: 0, width: 820, height: 610)
    view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 700)
    workspace.drag(0, to: .init(-11, -4))
    workspace.endGesture()
    await workspace.task?.value
    XCTAssertTrue(workspace.ready, workspace.error ?? "Warp is not ready.")
    let editedWarp = workspace.settings
    XCTAssertEqual(editedWarp.mesh?.points[0], PathPoint(-11, -4))
    store.commitWarp()
    await store.geometryTask?.value
    XCTAssertEqual(store.activeLayer?.warp, editedWarp)
    XCTAssertEqual(store.activeLayer?.smartObject?.data, original)
    XCTAssertEqual(store.session.undoStack.count, 1)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: store.document)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/file.psb")
      XCTAssertEqual(response.0.statusCode, 200)
      let saved = try PSDCodec.read(response.1)
      XCTAssertEqual(saved.layers[0].warp, editedWarp)
      XCTAssertEqual(saved.layers[0].smartObject?.data, original)

      let expected = try XCTUnwrap(PSDCodec.warpedSmartObjectPlacementCorners(saved.layers[0]))
      let identified = try AdobeLayerIdentifiers.assigning(in: saved)
      for data in [try AdobeDocumentManifest.encode(identified, title: "Warp.psb", includeXmp: false),
                   try AdobeArtboardRequest.manifest(saved)] {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layers = try XCTUnwrap(raw["layers"] as? [[String: Any]])
        let smart = try XCTUnwrap(layers.first?["smartObject"] as? [String: Any])
        let details = try XCTUnwrap(smart["smartObjectData"] as? [String: Any])
        XCTAssertEqual(details["transform"] as? [Double], expected.flatMap { [$0.x, $0.y] })
      }
    }
    await store.undo()
    XCTAssertEqual(store.document, reopened)
  }

  @MainActor func testCylinderControlsUndoCommitAndAuthenticatedAPI() async throws {
    var source = try CraftDocument(width: 100, height: 90)
    let pixels = try Surface(width: 40, height: 32, fill: Pixel(0.3, 0.4, 0.8))
    let original = try RasterIO.encoded(pixels)
    var layer = try SmartObjectIO.placed(data: original, fileName: "Wrap artwork.png", in: source, fit: false)
    layer.x = 21; layer.y = 16
    source.layers = [layer]; source.activeLayerID = layer.id
    let store = EditorStore(document: source)
    defer { store.cancelWarp(); store.renderTask?.cancel() }
    store.beginWarp()
    let workspace = try XCTUnwrap(store.warpDraft)
    workspace.choose(.cylinder)
    let initial = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertEqual(initial.photoshopValues, [0, 32, 40, 0, 0.5, 0.5, 0.15])
    for handle in CylinderHandle.allCases {
      let cursor = ToolCursor.cylinderWarp(handle, dragging: false, flags: [])
      for flags: NSEvent.ModifierFlags in [.control, .command, .option, [.control, .command, .option]] {
        XCTAssertEqual(ToolCursor.cylinderWarp(handle, dragging: false, flags: flags), cursor)
      }
      let constrained = ToolCursor.cylinderConstrained(handle, flags: .shift)
      XCTAssertEqual(constrained, handle == .topRight || handle == .bottomLeft)
      XCTAssertEqual(ToolCursor.cylinderWarp(handle, dragging: false, flags: .shift) != cursor, constrained)
    }
    XCTAssertEqual(ToolCursor.cylinderWarp(.body, dragging: true, flags: .shift), .closedHand)

    func drag(_ handle: CylinderHandle, _ x: Double, _ y: Double, shift: Bool = false) {
      workspace.dragCylinder(handle, from: .init(0, 0), to: .init(x, y), constrain: shift)
      workspace.endGesture()
    }
    drag(.topRight, 10, -9, shift: true)
    let resized = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertEqual((resized.right - resized.left) / (resized.bottom - resized.top), 40.0 / 32, accuracy: 1e-10)
    XCTAssertEqual(resized.left, initial.left)
    XCTAssertEqual(resized.bottom, initial.bottom)
    drag(.bottomLeft, -4, 3)
    let expanded = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertEqual(expanded.left, resized.left - 4)
    XCTAssertEqual(expanded.bottom, resized.bottom + 3)
    drag(.topRim, 0, -3)
    let rims = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertLessThan(rims.topDepth, expanded.topDepth)
    XCTAssertLessThan(rims.bottomDepth, expanded.bottomDepth)
    drag(.bottomRim, 0, 2)
    XCTAssertEqual(workspace.settings.cylinder?.topDepth, rims.topDepth)
    XCTAssertGreaterThan(try XCTUnwrap(workspace.settings.cylinder).bottomDepth, rims.bottomDepth)
    drag(.wrap, 6, 0)
    let wrapped = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertGreaterThan(wrapped.wrap, initial.wrap)
    drag(.body, 3, 4)
    let moved = try XCTUnwrap(workspace.settings.cylinder)
    XCTAssertEqual(moved.right, wrapped.right + 3)
    XCTAssertEqual(moved.top, wrapped.top + 4)
    workspace.undo(); XCTAssertEqual(workspace.settings.cylinder, wrapped)
    workspace.redo(); XCTAssertEqual(workspace.settings.cylinder, moved)
    workspace.grid(3); workspace.split(vertical: true)
    XCTAssertEqual(workspace.settings.cylinder, moved)
    await workspace.task?.value
    XCTAssertTrue(workspace.ready, workspace.error ?? "Cylinder Warp preview is not ready.")
    let view = NSHostingView(rootView: WarpSheet(store: store, model: workspace))
    view.frame = NSRect(x: 0, y: 0, width: 820, height: 610)
    view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 700)
    XCTAssertLessThanOrEqual(view.fittingSize.height, 620)
    let expected = try XCTUnwrap(workspace.edit).result
    store.commitWarp()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.activeLayer?.smartObject?.data, original)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, source)
    store.beginWarp(); store.warpDraft?.choose(.cylinder); store.cancelWarp()
    XCTAssertNil(store.warpDraft)
    XCTAssertEqual(store.document, source)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: source)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first?.id)
      let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(moved)) as? [String: Any])
      let response = try await helper.edit(service, shared, "layer.warp", [
        "layerID": layer.id.uuidString, "settings": ["style": "cylinder", "cylinder": fields],
      ])
      XCTAssertEqual(response, 200)
      XCTAssertEqual(shared.store.document, expected)
      let old = try await helper.request(service, path: "/v1/documents/\(share)/file.photato",
        headers: ["X-Photato-Archive-Version": "97"])
      XCTAssertEqual(old.0.statusCode, 422)
      let native = try await helper.request(service, path: "/v1/documents/\(share)/file.photato",
        headers: ["X-Photato-Archive-Version": "98"])
      XCTAssertEqual(native.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decodePaged(native.1), expected)
      let download = try await helper.request(service, path: "/v1/documents/\(share)/file.psb")
      XCTAssertEqual(download.0.statusCode, 200)
      let opened = try PSDCodec.read(download.1)
      XCTAssertEqual(opened.layers[0].warp?.cylinder, moved)
      let invalid = try await helper.edit(service, shared, "layer.warp", [
        "layerID": layer.id.uuidString, "settings": ["style": "cylinder", "cylinder": ["wrap": 0.3]],
      ])
      XCTAssertEqual(invalid, 400)
      XCTAssertEqual(shared.store.document, expected)
    }
  }
}
