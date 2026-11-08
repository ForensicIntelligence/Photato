import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

struct SourceProbeDetector: ObjectDetecting, AllObjectsDetecting, PeopleDetecting {
  func mask(for image:Surface,at point:PathPoint) async throws -> SelectionMask {
    let p=image.pixel(x:4,y:3),x=p.r>p.g ? 1:8
    return try .make(.rectangle(.init(x:x,y:1,width:2,height:2)),width:image.width,height:image.height,antiAlias:false)
  }
  func masks(for image:Surface) async throws -> [DetectedObjectMask] {
    [.init(instanceID:1,mask:try await mask(for:image,at:.init(0,0)))]
  }
  func people(in image:Surface) async throws -> [DetectedObjectMask] {try await masks(for:image)}
}

final class SelectionSourcePolicyTests:XCTestCase {
  func fixture(_ content:LayerContent = .fill(Pixel(1,0,0)),depth:PixelDepth = .u8,width:Int = 16,height:Int = 8) throws -> CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    d.layers[0]=Layer(name:"Analysis source",content:content);d.activeLayerID=d.layers[0].id
    d.layers.append(Layer(name:"Unrelated cover",content:.raster(try Surface(width:width,height:height,depth:depth,fill:Pixel(0,1,0)))))
    return d
  }
  func testSolidCurrentAndExplicitCompositeHaveExactLiteralInputsAtEveryDepth() throws {
    var captured=Data()
    for depth in PixelDepth.allCases {
      let d=try fixture(depth:depth,width:8,height:6),original=d
      for all in [false,true] {
        let image=try SelectionToolPreparation.input(d,layerID:d.activeLayerID,allLayers:all)
        let expected=all ? Pixel(0,1,0):Pixel(1,0,0)
        for y in 0..<6 {for x in 0..<8 {
          let p=image.pixel(x:x,y:y);XCTAssertEqual(p,expected)
          for v in [p.r,p.g,p.b,p.a] {var bits=v.bitPattern.littleEndian;withUnsafeBytes(of:&bits){captured.append(contentsOf:$0)}}
        }}
      }
      XCTAssertEqual(d,original)
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try captured.write(to:URL(fileURLWithPath:path).appendingPathComponent("rich-selection-inputs.f32"))
    }
  }
  func testTypeShapePatternAndGradientUseTheirOwnRenderedContent() throws {
    let pattern=try RasterPattern(name:"Owned red",surface:Surface(width:2,height:2,fill:Pixel(1,0,0)))
    let cases:[LayerContent]=[.text(TextContent(text:"A",size:24,color:Pixel(1,0,0))),
      .shape(.init(kind:.rectangle,width:16,height:12,color:Pixel(1,0,0))),
      .patternFill(.init(patternID:pattern.id)),.gradientFill(.init(dither:false))]
    for content in cases {
      var d=try fixture(content,width:64,height:48);d.patterns=[pattern]
      let original=d,id=d.activeLayerID
      XCTAssertTrue(SelectionToolPreparation.canSample(d,layerID:id,allLayers:false))
      let current=try SelectionToolPreparation.input(d,layerID:id,allLayers:false)
      let composite=try SelectionToolPreparation.input(d,layerID:id,allLayers:true)
      XCTAssertNotEqual(current,composite,"\(content.label)")
      var ownContent=false
      for y in 0..<48 {for x in 0..<64 {
        let p=current.pixel(x:x,y:y)
        if p.a>0.1 && p.r>0.1 {ownContent=true}
        XCTAssertEqual(composite.pixel(x:x,y:y),Pixel(0,1,0))
      }}
      XCTAssertTrue(ownContent,"\(content.label)");XCTAssertEqual(d,original)
    }
  }
  func testHiddenLockedTransformedMaskedShapeDoesNotReadTheCover() throws {
    var d=try fixture(.shape(.init(kind:.rectangle,width:8,height:4,color:Pixel(1,0,0))))
    d.layers[0].x=2;d.layers[0].y=1;d.layers[0].visible=false;d.layers[0].locked=true
    var mask=try Surface(width:8,height:4,fill:.black)
    for y in 0..<4 {for x in 0..<3 {mask.setPixel(x:x,y:y,.white)}}
    d.layers[0].mask=mask
    let original=d,image=try SelectionToolPreparation.input(d,layerID:d.activeLayerID,allLayers:false)
    XCTAssertEqual(image.pixel(x:3,y:2),Pixel(1,0,0));XCTAssertEqual(image.pixel(x:6,y:2).a,0)
    XCTAssertEqual(image.pixel(x:0,y:0).a,0);XCTAssertEqual(d,original)
  }
  func testGroupsAdjustmentsAndMissingCurrentSourcesNeverFallBackSilently() throws {
    for content:LayerContent in [.group(.init()),.adjustment(.invert)] {
      let d=try fixture(content)
      XCTAssertFalse(SelectionToolPreparation.canSample(d,layerID:d.activeLayerID,allLayers:false))
      XCTAssertThrowsError(try SelectionToolPreparation.input(d,layerID:d.activeLayerID,allLayers:false))
      XCTAssertTrue(SelectionToolPreparation.canSample(d,layerID:d.activeLayerID,allLayers:true))
      XCTAssertEqual(try SelectionToolPreparation.input(d,layerID:d.activeLayerID,allLayers:true).pixel(x:0,y:0),Pixel(0,1,0))
    }
    var d=try fixture();d.activeLayerID=nil
    XCTAssertThrowsError(try SelectionToolPreparation.input(d,layerID:nil,allLayers:false))
    XCTAssertFalse(SelectionToolPreparation.canSample(d,layerID:nil,allLayers:false))
    for all in [false,true] {
      XCTAssertThrowsError(try SelectionToolPreparation.input(d,layerID:UUID(),allLayers:all))
      XCTAssertFalse(SelectionToolPreparation.canSample(d,layerID:UUID(),allLayers:all))
    }
  }
  func testObjectAndPeopleDetectionShareTheExplicitInputChoice() async throws {
    let d=try fixture(),original=d,detector=SourceProbeDetector()
    for all in [false,true] {
      let object=try await ObjectFinderScene.detect(d,layerID:d.activeLayerID,sampleAllLayers:all,detector:detector)
      let people=try await PeopleScene.detect(d,layerID:d.activeLayerID,sampleAllLayers:all,detector:detector)
      let expected=IntRect(x:all ? 8:1,y:1,width:2,height:2)
      XCTAssertEqual(object.objects.first?.bounds,expected);XCTAssertEqual(people.people.first?.bounds,expected)
      var request=SelectionToolRequest(kind:.object);request.layerID=d.activeLayerID;request.sampleAllLayers=all;request.points=[.init(x:4,y:3)]
      var session=EditorSession(document:d)
      try session.execute(try await SelectionToolPreparation.command(request,in:d,detector:detector))
      XCTAssertEqual(session.document.selection,expected);XCTAssertEqual(session.document.layers,d.layers)
      let after=session.document;try session.undo();XCTAssertEqual(session.document,d)
      try session.redo();XCTAssertEqual(session.document,after)
    }
    XCTAssertEqual(d,original)
  }
  func testCancelledRichSamplingDoesNotChangeSourceState() async throws {
    let d=try fixture()
    await Task.detached {
      withUnsafeCurrentTask{$0?.cancel()}
      do {_ = try SelectionToolPreparation.input(d,layerID:d.activeLayerID,allLayers:false);XCTFail("Cancelled sampling completed")}
      catch is CancellationError {} catch {XCTFail("\(error)")}
    }.value
  }
}
