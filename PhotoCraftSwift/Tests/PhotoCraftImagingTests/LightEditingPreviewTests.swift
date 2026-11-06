import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LightEditingPreviewTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:192,height:128,depth:depth)
    var s=try Surface(width:d.width,height:d.height,depth:depth)
    for y in 0..<d.height {for x in 0..<d.width {s.setPixel(x:x,y:y,Pixel(Float(x+1)/194,Float(y+1)/130,0.4,0.8))}}
    d.layers[0].content = .raster(s)
    var light=ModernAdjustment(.light);light.values["shadows"]=45;light.values["exposure"]=0.7
    d.layers.append(try light.layer(in:d));return d
  }
  func testProjectionOnlyPausesSpatialLightAboveEditedInputAndRetainsSource()throws {
    let d=try fixture(),original=d,id=d.layers[0].id,lightID=d.layers[1].id
    let plan=LightEditingPreview(document:d,editingLayers:[id]);XCTAssertEqual(plan.pausedLayerIDs,[lightID])
    let preview=plan.project(d);XCTAssertEqual(preview.layers[1].visible,d.layers[1].visible);XCTAssertEqual(d,original)
    var noLight=d;noLight.layers[1].visible=false
    XCTAssertEqual(try Renderer.composite(preview),try Renderer.composite(noLight))
    XCTAssertNotEqual(try Renderer.composite(preview),try Renderer.composite(d))
    var multiply=d;multiply.layers[1].blendMode = .multiply
    let neutral=LightEditingPreview(document:multiply,editingLayers:[id]).project(multiply)
    XCTAssertEqual(try Renderer.composite(neutral),try Renderer.composite(noLight))
    XCTAssertEqual(preview.layers[0],d.layers[0]);XCTAssertEqual(preview.layers[1].mask,d.layers[1].mask)
    XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[lightID]).pausedLayerIDs.isEmpty)
    var pointwise=d;if case .adjustment(.modern(var value))=pointwise.layers[1].content {value.values["shadows"]=0;pointwise.layers[1].content = .adjustment(.modern(value))}
    XCTAssertTrue(LightEditingPreview(document:pointwise,editingLayers:[id]).pausedLayerIDs.isEmpty)
    var clarity=d;var c=ModernAdjustment(.clarityDehaze);c.values["clarity"]=50;clarity.layers[1].content = .adjustment(.modern(c))
    XCTAssertTrue(LightEditingPreview(document:clarity,editingLayers:[id]).pausedLayerIDs.isEmpty)
    var hidden=d;hidden.layers[1].visible=false;XCTAssertTrue(LightEditingPreview(document:hidden,editingLayers:[id]).pausedLayerIDs.isEmpty)
    var foreign=d;foreign.id=UUID();XCTAssertEqual(plan.project(foreign),foreign)
    var replaced=d;replaced.layers[1].content = .fill(.white);XCTAssertEqual(plan.project(replaced),replaced)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
  }
  func testHierarchyIsolationPassThroughClippingHiddenAndMultipleTargets()throws {
    var d=try fixture();let bottom=d.layers[0],light=d.layers[1]
    var group=Layer(name:"Folder",content:.group(.init(passThrough:false)))
    var inside=bottom;inside.id=UUID();inside.parentID=group.id
    var local=light;local.id=UUID();local.parentID=group.id
    d.layers=[bottom,inside,local,group]
    XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs.isEmpty)
    XCTAssertEqual(LightEditingPreview(document:d,editingLayers:[inside.id]).pausedLayerIDs,[local.id])
    group.content = .group(.init(passThrough:true));d.layers[3]=group
    XCTAssertEqual(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs,[local.id])
    group.visible=false;d.layers[3]=group;XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[inside.id]).pausedLayerIDs.isEmpty)
    var clip=light;clip.clipped=true;var base=bottom;base.id=UUID()
    d.layers=[bottom,base,clip]
    XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs.isEmpty)
    XCTAssertEqual(LightEditingPreview(document:d,editingLayers:[base.id]).pausedLayerIDs,[clip.id])
    base.blendClippedAsGroup=false;d.layers[1]=base
    XCTAssertEqual(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs,[clip.id])
    d.layers=[clip,bottom];XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs.isEmpty)
    var second=light;second.id=UUID();d.layers=[bottom,light,second]
    XCTAssertEqual(LightEditingPreview(document:d,editingLayers:[bottom.id,light.id]).pausedLayerIDs,[light.id,second.id])
    d.layers[0].visible=false;XCTAssertTrue(LightEditingPreview(document:d,editingLayers:[bottom.id]).pausedLayerIDs.isEmpty)
  }
  func testPausedLightRetainsAttachedClippedLayers() throws {
    var d=try fixture()
    var clip=Layer(name:"Clipped red",content:.fill(Pixel(1,0,0)))
    clip.clipped=true;d.layers.append(clip)
    let plan=LightEditingPreview(document:d,editingLayers:[d.layers[0].id])
    XCTAssertEqual(plan.pausedLayerIDs,[d.layers[1].id])
    let projected=plan.project(d),image=try Renderer.composite(projected)
    XCTAssertEqual(image.pixel(x:40,y:40),Pixel(1,0,0,0.8))
    XCTAssertEqual(projected.layers[2],d.layers[2])
  }
  func testIncrementalBrushPausesOnlyDisplayThenCommitsExactFullAdjustmentBothDepths()throws {
    for depth in [PixelDepth.u8,.u16] {
      let d=try fixture(depth),id=d.layers[0].id
      var brush=Brush();brush.color = .black;brush.size=6;brush.opacity=0.8;brush.settings = .init();brush.settings?.smoothing.amount=0
      let points=[StrokePoint(x:12,y:24,time:0),.init(x:20,y:28,time:8),.init(x:84,y:44,time:16)]
      let preview=try IncrementalBrushRenderer(document:d,layerID:id,brush:brush,pausingLightWhileEditing:true)
      let a=try preview.append(Array(points.prefix(2)),reusing:nil,includingReleaseTail:false)
      let b=try preview.append([points[2]],reusing:a,includingReleaseTail:false)
      XCTAssertTrue(b.document.layers[1].visible);if case .adjustment(.modern(let value))=b.document.layers[1].content{XCTAssertTrue(value.isIdentity)}else{XCTFail("Missing paused Light")};if case .region=b.update {}else{XCTFail("Paused frames must reuse local brush damage")}
      let prepared=try preview.prepareEdit(points:points);var session=EditorSession(document:d);try session.executePrepared(prepared)
      var expected=d;try Command.stroke(id,points,brush).apply(to:&expected)
      XCTAssertEqual(session.document,expected);XCTAssertEqual(session.document.layers[1],d.layers[1])
      let final=try Renderer.render(session.document,reusing:b)
      XCTAssertEqual(final.surface,try Renderer.composite(expected));XCTAssertEqual(final.update,.full)
      try session.undo();XCTAssertEqual(session.document,d)
      let unpaused=try IncrementalBrushRenderer(document:d,layerID:id,brush:brush)
      let regular=try unpaused.append(points,reusing:nil)
      XCTAssertEqual(regular.document,expected);XCTAssertTrue(regular.document.layers[1].visible)
    }
  }
}
