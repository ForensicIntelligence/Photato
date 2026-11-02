import XCTest
import PhotoCraftCore

final class ColorRangeTests:XCTestCase {
  func strip(_ colors:[Pixel])throws->Surface {var s=try Surface(width:colors.count,height:1);for (x,p) in colors.enumerated(){s.setPixel(x:x,y:0,p)};return s}
  func testExactSamplesAddSubtractAndAlpha()throws {
    let image=try strip([Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel(1,0,0,0.5),Pixel(1,0,0,0)])
    var s=ColorRangeSettings();s.fuzziness=0;s.samples=[.init(color:Pixel(1,0,0))]
    XCTAssertEqual(try ColorRangeSelection.mask(image,settings:s).bytes,[255,0,0,128,0])
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
      var rows:[[String:Any]]=[]
      for invert in [false,true] {var value=s;value.invert=invert;rows.append(["invert":invert,"bytes":try ColorRangeSelection.mask(image,settings:value).bytes.map{Int($0)}])}
      try JSONSerialization.data(withJSONObject:["source":"owned analytical red/green/blue/half-alpha/transparent strip","rows":rows],options:[.sortedKeys]).write(to:url.appendingPathComponent("color-range-analytical.json"))
    }

    s.samples.append(.init(color:Pixel(0,1,0)));XCTAssertEqual(try ColorRangeSelection.mask(image,settings:s).bytes,[255,255,0,128,0])
    s.samples.append(.init(color:Pixel(1,0,0),subtract:true));XCTAssertEqual(try ColorRangeSelection.mask(image,settings:s).bytes,[0,255,0,0,0])
    s.invert=true;XCTAssertEqual(try ColorRangeSelection.mask(image,settings:s).bytes,[255,0,255,128,0])
  }
  func testFuzzinessBroadensSoftCoverageWithoutEditingSource()throws {
    let image=try strip([Pixel(1,0,0),Pixel(0.8,0.1,0.1),Pixel(0.5,0.2,0.2),Pixel(0,1,0)])
    var s=ColorRangeSettings();s.samples=[.init(color:Pixel(1,0,0))];s.fuzziness=20
    let narrow=try ColorRangeSelection.mask(image,settings:s);s.fuzziness=100;let broad=try ColorRangeSelection.mask(image,settings:s)
    XCTAssertEqual(broad.byte(at:0),255);XCTAssertGreaterThan(broad.byte(at:1),narrow.byte(at:1));XCTAssertGreaterThan(broad.byte(at:2),0);XCTAssertLessThan(broad.byte(at:2),255);XCTAssertEqual(image.pixel(x:0,y:0),Pixel(1,0,0))
  }
  func testHuePresetsChooseCorrespondingColorsAndIgnoreGray()throws {
    let colors:[Pixel]=[Pixel(1,0,0),Pixel(1,1,0),Pixel(0,1,0),Pixel(0,1,1),Pixel(0,0,1),Pixel(1,0,1),Pixel(0.5,0.5,0.5)]
    for (i,kind) in [ColorRangeSettings.Kind.reds,.yellows,.greens,.cyans,.blues,.magentas].enumerated() {
      var s=ColorRangeSettings();s.kind=kind;s.fuzziness=0
      let mask=try ColorRangeSelection.mask(strip(colors),settings:s)
      XCTAssertEqual(try mask.bytes,(0..<7).map{$0==i ? 255:0})
    }
  }
  func testTonalWindowsAndInversion()throws {
    let image=try strip([.black,Pixel(0.25,0.25,0.25),Pixel(0.5,0.5,0.5),Pixel(0.75,0.75,0.75),.white])
    var s=ColorRangeSettings();s.fuzziness=0;s.minimum=100;s.maximum=160
    for (kind,expected) in [(ColorRangeSettings.Kind.shadows,[255,255,255,0,0]),(.midtones,[0,0,255,0,0]),(.highlights,[0,0,255,255,255])] {
      s.kind=kind;XCTAssertEqual(try ColorRangeSelection.mask(image,settings:s).bytes,expected.map{UInt8($0)})
    }
  }
  func testLocalizedClustersUsePositionsAndInvertOutside()throws {
    let image=try Surface(width:101,height:1,fill:Pixel(1,0,0));var s=ColorRangeSettings();s.samples=[.init(color:Pixel(1,0,0),point:.init(0.5,0.5))];s.localized=true;s.range=10;s.fuzziness=0
    let mask=try ColorRangeSelection.mask(image,settings:s)
    XCTAssertEqual(mask.byte(at:50),255);XCTAssertEqual(mask.byte(at:0),0);XCTAssertGreaterThan(mask.byte(at:55),0);XCTAssertLessThan(mask.byte(at:55),255)
    s.invert=true;let inverse=try ColorRangeSelection.mask(image,settings:s);for i in 0..<101{XCTAssertEqual(Int(mask.byte(at:i))+Int(inverse.byte(at:i)),255)}
  }
  func testSparseMaximumCanvasAndCancellation()async throws {
    var image=try Surface(width:300_000,height:300_000,fill:.white);image.setPixel(x:12,y:25,.black)
    var s=ColorRangeSettings();s.fuzziness=0
    let mask=try ColorRangeSelection.mask(image,settings:s);XCTAssertTrue(mask.isPaged);XCTAssertEqual(mask.bounds,.init(x:12,y:25,width:1,height:1));XCTAssertEqual(mask.byte(at:25*300_000+12),255);XCTAssertEqual(mask.byte(at:0),0);XCTAssertLessThan(mask.allocatedBytes,100_000)
    let captured=s
    let task=Task {while !Task.isCancelled {await Task.yield()};return try ColorRangeSelection.mask(image,settings:captured)};task.cancel()
    do{_=try await task.value;XCTFail("Cancelled classification completed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testPresetsValidationAndUnknownVersion()throws {
    var s=ColorRangeSettings();XCTAssertEqual(try ColorRangeSettings.preset(s.presetData()),s)
    s.localized=true;XCTAssertThrowsError(try s.validate());s.samples[0].point = .init(0.4,0.3);XCTAssertNoThrow(try s.validate())
    s.minimum=200;s.maximum=100;XCTAssertThrowsError(try s.validate());s.minimum=100;s.maximum=200;s.fuzziness = .infinity;XCTAssertThrowsError(try s.validate())
    XCTAssertThrowsError(try ColorRangeSettings.preset(Data(repeating:0,count:131_073)))
    let data=try ColorRangeSettings().presetData(),object=try JSONSerialization.jsonObject(with:data) as! [String:Any];var changed=object;changed["version"]=2
    XCTAssertThrowsError(try ColorRangeSettings.preset(JSONSerialization.data(withJSONObject:changed)))
  }
  func testHistoryAndCoverageActionsPreserveLayerPixels()throws {
    var d=try CraftDocument(width:4,height:1);d.layers[0].content = .raster(try strip([.black,.white,.black,.white]));let original=d
    var session=EditorSession(document:d);try session.startActionRecording(name:"Color Range")
    let mask=try ColorRangeSelection.mask(strip([.black,.white,.black,.white]),settings:.init());try session.execute(.colorRange(mask))
    XCTAssertEqual(session.undoStack.last?.label,"Color Range");XCTAssertEqual(session.document.layers,original.layers)
    var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==session.document)
    try session.undo();XCTAssertTrue(session.document==original);try session.redo();XCTAssertEqual(session.document.selectionMask,mask)
  }
}
