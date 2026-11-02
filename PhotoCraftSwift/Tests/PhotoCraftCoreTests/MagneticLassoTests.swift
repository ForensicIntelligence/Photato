import XCTest
import PhotoCraftCore

final class MagneticLassoTests:XCTestCase {
  func image()throws->Surface {var image=try Surface(width:100,height:80,fill:.black);for y in 0..<80 {for x in 50..<100 {image.setPixel(x:x,y:y,.white)}};return image}
  func manual()->[MagneticLassoEvent] {[(4.0,4.0),(20,4),(20,18),(4,18)].map{.init(.anchor,point:.init($0.0,$0.1))}}
  func testSnapsToImageEdgeWithinWidthAndPressure()throws {
    let source=try image();var settings=MagneticLassoSettings()
    let events:[MagneticLassoEvent]=[.init(.anchor,point:.init(55,5)),.init(.move,point:.init(55,70))]
    let wide=try MagneticLassoTrace.replay(events,image:source,settings:settings)
    XCTAssertGreaterThan(wide.points.count,5);XCTAssertTrue(wide.points.dropFirst().allSatisfy{abs($0.x-50)<=1})
    settings.width=2;let narrow=try MagneticLassoTrace.replay(events,image:source,settings:settings);XCTAssertTrue(narrow.points.allSatisfy{$0.x==55})
    settings.width=10;settings.stylusPressure=true;var pressed=events;pressed[1].pressure=1
    let pressure=try MagneticLassoTrace.replay(pressed,image:source,settings:settings);XCTAssertTrue(pressure.points.allSatisfy{$0.x==55})
  }
  func testContrastAndColorGradientNotJustLuminance()throws {
    var source=try Surface(width:100,height:80,fill:Pixel(0.4,0.4,0.4));for y in 0..<80{for x in 50..<100{source.setPixel(x:x,y:y,Pixel(0.5,0.5,0.5))}}
    let events:[MagneticLassoEvent]=[.init(.anchor,point:.init(55,5)),.init(.move,point:.init(55,70))];var settings=MagneticLassoSettings();settings.contrast=20
    let high=try MagneticLassoTrace.replay(events,image:source,settings:settings);XCTAssertTrue(high.points.allSatisfy{$0.x==55})
    settings.contrast=5;let low=try MagneticLassoTrace.replay(events,image:source,settings:settings);XCTAssertLessThan(low.points.last!.x,52)
    var color=try Surface(width:100,height:80,fill:Pixel(1,0,0));for y in 0..<80{for x in 50..<100{color.setPixel(x:x,y:y,Pixel(0,0.297,0))}}
    settings.contrast=50;let chroma=try MagneticLassoTrace.replay(events,image:color,settings:settings);XCTAssertLessThan(chroma.points.last!.x,52)
  }
  func testFrequencyControlsAutomaticFastening()throws {
    let source=try image(),events:[MagneticLassoEvent]=[.init(.anchor,point:.init(55,5)),.init(.move,point:.init(55,75))];var settings=MagneticLassoSettings();settings.frequency=0
    let low=try MagneticLassoTrace.replay(events,image:source,settings:settings);settings.frequency=100;let high=try MagneticLassoTrace.replay(events,image:source,settings:settings)
    XCTAssertGreaterThan(high.anchors.count,low.anchors.count)
  }
  func testManualFreehandStraightWidthAndDelete()throws {
    let source=try image();var trace=try MagneticLassoTrace(settings:.init())
    try trace.append(.init(.anchor,point:.init(5,5)),image:source);try trace.append(.init(.freehand,point:.init(25,7)),image:source);try trace.append(.init(.straight,point:.init(25,25)),image:source)
    XCTAssertEqual(trace.points,[.init(5,5),.init(25,7),.init(25,25)]);XCTAssertEqual(trace.anchors,[0,2])
    try trace.append(.init(.remove),image:source);XCTAssertEqual(trace.points,[.init(5,5)]);XCTAssertEqual(trace.cursor,.init(5,5))
    try trace.append(.init(.width,width:27),image:source);XCTAssertEqual(trace.settings.width,27)
  }
  func testManualMaskIndependentCaptureAndFeather()throws {
    let source=try Surface(width:32,height:24,fill:.white);var settings=MagneticLassoSettings();settings.antiAlias=false
    let trace=try MagneticLassoTrace.replay(manual(),image:source,settings:settings),mask=try trace.mask(image:source,straight:true)
    XCTAssertEqual(try mask.bytes.filter{$0==255}.count,224);XCTAssertEqual(mask.bounds,.init(x:4,y:4,width:16,height:14))
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:["width":32,"height":24,"rectangle":[4,4,16,14],"bytes":try mask.bytes.map{Int($0)}],options:.sortedKeys).write(to:url.appendingPathComponent("magnetic-analytical.json"))
    }
    settings.feather=3;let soft=try MagneticLassoTrace.replay(manual(),image:source,settings:settings).mask(image:source,straight:true);XCTAssertTrue(try soft.bytes.contains{$0>0 && $0<255})
  }
  func testHistoryModesAndCoverageActions()throws {
    let image=try Surface(width:32,height:24,fill:.white),mask=try MagneticLassoTrace.replay(manual(),image:image,settings:.init()).mask(image:image,straight:true)
    var original=try CraftDocument(width:32,height:24);original.selection = .init(x:2,y:2,width:10,height:10)
    for mode in SelectionMode.allCases {
      var session=EditorSession(document:original);try session.startActionRecording(name:"Magnetic");try session.execute(.magneticSelection(mask,mode))
      XCTAssertEqual(session.undoStack.last?.label,"Magnetic Lasso");XCTAssertEqual(session.document.layers,original.layers)
      var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==session.document)
      let result=session.document;try session.undo();XCTAssertTrue(session.document==original);try session.redo();XCTAssertTrue(session.document==result)
    }
  }
  func testSparseMaximumDimensions()throws {
    let image=try Surface(width:300_000,height:300_000,fill:.white),trace=try MagneticLassoTrace.replay(manual(),image:image,settings:.init()),mask=try trace.mask(image:image,straight:true)
    XCTAssertTrue(mask.isPaged);XCTAssertEqual(mask.bounds,.init(x:4,y:4,width:16,height:14));XCTAssertEqual(mask.coverage(x:8,y:8),1);XCTAssertLessThan(mask.allocatedBytes,200_000)
  }
  func testInvalidEventsSettingsAndCancellation()async throws {
    let source=try image();var settings=MagneticLassoSettings();settings.width=0;XCTAssertThrowsError(try settings.validate());settings.width=10;settings.contrast=101;XCTAssertThrowsError(try settings.validate())
    for event in [MagneticLassoEvent(.move),.init(.width,width:257),.init(.remove,point:.init(1,1)),.init(.anchor,point:.init(-1,0)),.init(.move,point:.init(1,1),pressure:2)] {XCTAssertThrowsError(try MagneticLassoTrace.replay([event],image:source,settings:.init()))}
    let recorded=manual()
    let task=Task {while !Task.isCancelled{await Task.yield()};return try MagneticLassoTrace.replay(recorded,image:source,settings:.init())};task.cancel();do{_=try await task.value;XCTFail("Cancelled trace completed")}catch{XCTAssertTrue(error is CancellationError)}
  }
}
