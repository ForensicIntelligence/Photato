import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

/// Controlled native-model pacing. These timings do not measure WindowServer presentation.
final class MaskPreviewResponsivenessTests:XCTestCase {
  @MainActor func testPacedRasterMaskAndAdjustmentPreviewsRetainCanonicalCommit()async throws {
    _ = NSApplication.shared
    var source=try CraftDocument(width:3072,height:3072)
    var pixels=try Surface(width:source.width,height:source.height)
    for y in 0..<source.height {for x in 0..<source.width {
      pixels.setPixel(x:x,y:y,Pixel(Float(8+(x/8)%240)/255,Float(8+(y/8)%240)/255,Float(40+(x+y)%192)/255))
    }}
    XCTAssertGreaterThan(pixels.allocatedBytes,1_048_576)
    source.layers[0].content = .raster(pixels)
    let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map{URL(fileURLWithPath:$0)}
      ?? FileManager.default.temporaryDirectory.appendingPathComponent("photato-paced-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    for kind in ["raster","layerMask","existingAdjustment","newAdjustment"] {
      var document=source
      if kind == "layerMask" {document.layers[0].mask=try Surface(width:source.width,height:source.height,fill:.white)}
      if kind == "existingAdjustment" {
        var layer=Layer(name:"Colour",content:.adjustment(AdjustmentBrushKind.colorVibrance.initial))
        layer.mask=try Surface(width:source.width,height:source.height,fill:.black)
        document.layers.append(layer);document.activeLayerID=layer.id
      }
      let suite="Photato.PacedPreview."+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
      defer{defaults.removePersistentDomain(forName:suite)}
      let store=EditorStore(document:document,actions:ActionLibrary(),brushes:BrushLibrary(),paintPalette:PaintPalette(defaults:defaults))
      defer{store.cancelBrush();store.renderTask?.cancel()}
      store.tool = kind.contains("Adjustment") ? .adjustmentBrush:.brush
      if kind == "layerMask" {store.maskEditingLayerID=document.layers[0].id}
      store.adjustmentBrushKind = .colorVibrance
      store.brush.size=100;store.brush.hardness=0.8;store.brush.opacity=1;store.brush.color = .black
      store.brushOptions.pressureSize=false;store.brushOptions.pressureOpacity=false;store.brushOptions.flow=1
      store.updateViewport(size:.init(width:800,height:800),backingScale:1);store.setZoom(800.0/3072,center:true)
      await store.renderTask?.value
      let directory=root.appendingPathComponent(kind);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
      let trace=CanvasFrameTrace(directory:directory);store.canvasFrameTrace=trace
      func point(_ index:Int)->StrokePoint {
        .init(x:300+Double(index)*10,y:1400+sin(Double(index)/18)*450,time:Double(index)*1000/120)
      }
      store.beginBrush(point(0),zoom:800.0/3072)
      for i in 1..<240 {
        try await Task.sleep(for:.nanoseconds(8_333_333))
        store.extendBrush(point(i))
      }
      let gesture=try XCTUnwrap(store.brushGesture),inputCount=gesture.points.count
      XCTAssertEqual(inputCount,240)
      let command=gesture.adjustmentRequest.map(Command.adjustmentBrush) ?? gesture.command
      store.finishBrush()
      let reportTask=try XCTUnwrap(trace.flush())
      await store.geometryTask?.value;await store.renderTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      var expected=document;try command.apply(to:&expected)
      XCTAssertEqual(store.document,expected,"\(kind) must retain complete command pixels and metadata")
      let written=await reportTask.value
      let url=try XCTUnwrap(written),data=try Data(contentsOf:url)
      let report=try JSONDecoder().decode(CanvasFrameTrace.Report.self,from:data)
      XCTAssertFalse(report.physicalPresentationMeasured);XCTAssertEqual(report.droppedEvents,0)
      let events=report.events,first=try XCTUnwrap(events.first),end=try XCTUnwrap(events.first{$0.kind=="end"})
      let ready=events.filter{$0.kind=="ready"},prepare=Dictionary(uniqueKeysWithValues:events.filter{$0.kind=="prepare"}.compactMap{e in e.revision.map{($0,e.uptime)}})
      let latency=ready.compactMap{e in e.inputUptime.map{(e.uptime-$0)*1000}}.sorted()
      let preparation=ready.compactMap{e in e.revision.flatMap{prepare[$0]}.map{(e.uptime-$0)*1000}}.sorted()
      func stats(_ values:[Double])->[String:Any] {
        guard !values.isEmpty else{return ["count":0]}
        return ["count":values.count,"medianMS":values[values.count/2],"p95MS":values[min(values.count-1,Int(Double(values.count)*0.95))],"maximumMS":values.last!]
      }
      let seconds=end.uptime-first.uptime
      let summary:[String:Any]=["target":kind,"inputs":inputCount,"actualInputDurationSeconds":seconds,"acceptedPreviews":ready.count,
        "acceptedPreviewsPerSecond":Double(ready.count)/seconds,"inputToReady":stats(latency),"prepareToReady":stats(preparation),
        "canonicalCommitExact":true,"historySteps":1,"physicalPresentationMeasured":false,"inputSource":"Paced native model calls, no OS events or native window drawing"]
      try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys,.prettyPrinted]).write(to:directory.appendingPathComponent("summary.json"))
      print("Paced preview measurement: "+String(decoding:try JSONSerialization.data(withJSONObject:summary,options:.sortedKeys),as:UTF8.self))
    }
  }
}
