import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

@MainActor private final class LookupLatencyPulse {
  var started=false
  func measure()async->[Double]{
    started=true;var gaps:[Double]=[]
    while !Task.isCancelled{
      let start=ProcessInfo.processInfo.systemUptime
      do{try await Task.sleep(for:.milliseconds(2))}catch{break}
      gaps.append((ProcessInfo.processInfo.systemUptime-start)*1000)
    }
    return gaps
  }
}
final class LookupPropertyResponsivenessTests:XCTestCase {
  func dense(_ width:Int,_ height:Int,imageLayers:Int)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height),pixels=try Surface(width:width,height:height)
    pixels.mapPixels{x,y,_ in Pixel(Float(x)/Float(width),Float(y)/Float(height),0.4)}
    d.layers=(0..<imageLayers).map{i in var layer=Layer(name:"Image \(i+1)",content:.raster(pixels));layer.visible=i==0;return layer}
    var lookup=Layer(name:"Lookup",content:.adjustment(.colorLookup(.init())))
    lookup.mask=try Surface(width:width,height:height,fill:.white);d.layers.append(lookup);d.activeLayerID=lookup.id
    return d
  }
  func statistics(_ values:[Double])->[String:Any]{
    guard !values.isEmpty else{return ["samples":0]};let sorted=values.sorted()
    return ["samples":values.count,"p50_ms":sorted[Int(ceil(Double(sorted.count)*0.5))-1],"p95_ms":sorted[Int(ceil(Double(sorted.count)*0.95))-1],"max_ms":sorted.last!,"raw_ms":values]
  }
  /// Opt-in observations; timing thresholds are deliberately not CI assertions.
  @MainActor func testMeasuredNativePropertyEdits()async throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_LOOKUP_RESPONSIVENESS_REPORT"] else{return}
    let samples=20;var cases:[[String:Any]]=[]
    for (width,height,layers) in [(6000,4000,1),(6000,6000,1),(1024,1024,32)]{
      let original=try dense(width,height,imageLayers:layers),id=try XCTUnwrap(original.activeLayerID)
      try original.validate()
      for edge in [33,129]{
        let value=ColorLookupAdjustment(lut:try ColorLUT.generated(title:"Owned swap",size:edge){SIMD3($0.z,$0.x,$0.y)},dither:false)
        var submit:[Double]=[],completion:[Double]=[],gaps:[Double]=[],busy:[Bool]=[]
        for _ in 0..<samples{
          let store=EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary())
          store.renderTask?.cancel();await store.renderTask?.value
          let pulse=LookupLatencyPulse(),worker=Task{@MainActor in await pulse.measure()}
          while !pulse.started{await Task.yield()}
          let start=ProcessInfo.processInfo.systemUptime
          store.setColorLookup(id,value)
          submit.append((ProcessInfo.processInfo.systemUptime-start)*1000);busy.append(store.geometryBusy)
          await store.geometryTask?.value
          completion.append((ProcessInfo.processInfo.systemUptime-start)*1000)
          store.renderTask?.cancel();await store.renderTask?.value
          try await Task.sleep(for:.milliseconds(4));worker.cancel();gaps += await worker.value
          XCTAssertTrue(Thread.isMainThread);XCTAssertNil(store.error)
          XCTAssertEqual(store.session.undoStack.count,1);XCTAssertTrue(store.activeLayer?.content == .adjustment(.colorLookup(value)))
          XCTAssertEqual(store.document.layers[0],original.layers[0]);XCTAssertEqual(store.activeLayer?.mask,original.layers.last?.mask)
          store.geometryTask?.cancel();store.renderTask?.cancel()
        }
        cases.append(["width":width,"height":height,"image_layers":layers,"lookup_edge":edge,"samples":samples,"submit_main_actor":statistics(submit),"completion":statistics(completion),"main_actor_2ms_timer_gaps":statistics(gaps),"busy_at_return":busy])
      }
    }
    let report:[String:Any]=["cases":cases,"os":ProcessInfo.processInfo.operatingSystemVersionString,"active_processor_count":ProcessInfo.processInfo.activeProcessorCount,
      "scope":"Optimized in-process native setter on owned dense RGB8 gradients,24/36MP single-layer and1MP/32image layers sharing one immutable pixel buffer (only base visible),33/129edge generated LUT.20fresh-session single edits per case, one Undo each. Submission includes synchronous setter; completion awaits geometry task; rendering cancelled/excluded. MainActor2ms timer gaps include scheduling and render-task-drain contention; they are not physical input/display latency or frame rate. Shared host load is uncontrolled; no60fps/fullQ03claim."]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
  }
}
