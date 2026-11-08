import Foundation
import XCTest
@testable import PhotoCraftCore

final class MaskFilterTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,target:MaskFilterTarget = .layerMask) throws -> CraftDocument {
    var d=try CraftDocument(width:16,height:12,depth:depth)
    var layer=Layer(name:"Owned mask source",content:.raster(try Surface(width:8,height:6,depth:depth,fill:Pixel(0.2,0.7,0.3,0.75))))
    layer.x=1;layer.y=1
    var mask=try Surface(width:8,height:6,depth:depth)
    for y in 0..<6 {for x in 0..<8 {let v=Float((x+2*y)%5)/4;mask.setPixel(x:x,y:y,Pixel(v,v,v,(x+y)%2==0 ? 0:1))}}
    var properties=MaskProperties();properties.transform = .translation(2,1);properties.linked=false;properties.density=0.37;properties.feather=1;properties.outside=0.25
    if target == .layerMask {layer.mask=mask;layer.maskProperties=properties}
    else {
      // Opaque source sentinel: these tests never decode or replace its data.
      layer.smartObject=try SmartObject(fileName:"Owned.png",mediaType:"image/png",data:Data([1]),width:8,height:6)
      properties.transform = .translation(3,2)
      var stack=SmartFilterStack();stack.mask=mask;stack.maskProperties=properties;layer.smartFilters=stack
      layer.mask=try Surface(width:8,height:6,depth:depth,fill:Pixel(0.75,0.75,0.75))
    }
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  func mask(_ d:CraftDocument,_ target:MaskFilterTarget)->Surface? {target == .layerMask ? d.layers[0].mask:d.layers[0].smartFilters?.mask}
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind);if [.gaussianBlur,.boxBlur,.highPass,.unsharpMask].contains(kind){f.radius=1};if kind == .motionBlur{f.distance=3};if kind == .mosaic{f.cellSize=2};if kind == .addNoise{f.seed=42};return f
  }
  func testAllEightFiltersPreserveColorSourcePropertiesOtherMasksAndOneHistoryAtEveryDepth() throws {
    for depth in PixelDepth.allCases {for target in MaskFilterTarget.allCases {for kind in MaskFiltering.kinds {
      let original=try fixture(depth,target:target),id=original.layers[0].id
      var session=EditorSession(document:original)
      try session.execute(.maskFilter(.init(layerID:id,target:target,filter:filter(kind))))
      let result=session.document
      var expectedOwner=original.layers[0]
      if target == .layerMask {expectedOwner.mask=result.layers[0].mask}
      else {expectedOwner.smartFilters?.mask=result.layers[0].smartFilters?.mask}
      XCTAssertEqual(result.layers[0],expectedOwner);XCTAssertEqual(result.width,original.width)
      let changed=result != original
      XCTAssertEqual(session.undoStack.count,changed ? 1:0)
      if changed {try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,result)}
      let source=try XCTUnwrap(mask(original,target)),output=try XCTUnwrap(mask(result,target))
      XCTAssertEqual(output.depth,source.depth);XCTAssertEqual(output.colorEncoding,source.colorEncoding)
      for y in 0..<source.height {for x in 0..<source.width {XCTAssertEqual(output.pixel(x:x,y:y).a,source.pixel(x:x,y:y).a)}}
    }}}
  }
  func testAverageHasExactNumericGrayWithoutGammaOrMaskAlphaAndRetainsDisabledProperties() throws {
    var captured=Data()
    for depth in PixelDepth.allCases {for target in MaskFilterTarget.allCases {
      var d=try fixture(depth,target:target),samples=try Surface(width:4,height:1,depth:depth)
      for x in 0..<4 {let v:Float=x%2==0 ? 0:1;samples.setPixel(x:x,y:0,Pixel(v,v,v,x<2 ? 0:1))}
      if target == .layerMask {d.layers[0].mask=samples;d.layers[0].maskProperties?.inverted=true;d.layers[0].maskProperties?.enabled=false}
      else {d.layers[0].smartFilters?.mask=samples;d.layers[0].smartFilters?.maskProperties.inverted=true;d.layers[0].smartFilters?.maskProperties.enabled=false}
      let before=d,request=MaskFilterRequest(layerID:d.layers[0].id,target:target,filter:filter(.average))
      try Command.maskFilter(request).apply(to:&d)
      let result=try XCTUnwrap(mask(d,target)),displayed=Pixel(0.5,0.5,0.5).quantized(depth).r
      let value=Pixel(1-displayed,1-displayed,1-displayed).quantized(depth).r
      for x in 0..<4 {
        let p=result.pixel(x:x,y:0)
        XCTAssertEqual(p.r,value);XCTAssertEqual(p.g,value);XCTAssertEqual(p.b,value);XCTAssertEqual(p.a,x<2 ? 0:1)
        for v in [p.r,p.g,p.b,p.a] {var bits=v.bitPattern.littleEndian;withUnsafeBytes(of:&bits){captured.append(contentsOf:$0)}}
      }
      XCTAssertEqual(d.layers[0].content,before.layers[0].content)
      XCTAssertEqual(d.layers[0].maskProperties,before.layers[0].maskProperties)
      XCTAssertEqual(d.layers[0].smartFilters?.maskProperties,before.layers[0].smartFilters?.maskProperties)
    }}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try captured.write(to:URL(fileURLWithPath:path).appendingPathComponent("mask-filter-average.f32"))}
  }
  func testSelectionUsesStoredMaskPlacementAndPreservesUnselectedSamplesExactly() throws {
    for depth in PixelDepth.allCases {for target in MaskFilterTarget.allCases {
      var d=try fixture(depth,target:target),source=try Surface(width:4,height:1,depth:depth)
      for x in 0..<4 {let v:Float=x%2==0 ? 0:1;source.setPixel(x:x,y:0,Pixel(v,v,v))}
      if target == .layerMask {d.layers[0].mask=source}else{d.layers[0].smartFilters?.mask=source}
      d.selection = .init(x:3,y:2,width:2,height:1)
      let before=d
      try Command.maskFilter(.init(layerID:d.layers[0].id,target:target,filter:filter(.average))).apply(to:&d)
      let result=try XCTUnwrap(mask(d,target)),expected=Pixel(0.5,0.5,0.5).quantized(depth).r
      XCTAssertEqual(result.pixel(x:0,y:0).r,expected);XCTAssertEqual(result.pixel(x:1,y:0).r,expected)
      XCTAssertEqual(result.pixel(x:2,y:0),source.pixel(x:2,y:0));XCTAssertEqual(result.pixel(x:3,y:0),source.pixel(x:3,y:0))
      XCTAssertEqual(d.selection,before.selection);XCTAssertEqual(d.layers[0].content,before.layers[0].content)
    }}
  }
  func testSparseMaximumGeometryUsesExistingConstantFilterProofWithoutDenseAllocation() throws {
    var d=try CraftDocument(width:300_000,height:300_000,depth:.f32)
    let layer=Layer(name:"Sparse owner",content:.fill(.white));d.layers=[layer];d.activeLayerID=layer.id
    d.layers[0].mask=try Surface(width:300_000,height:300_000,depth:.f32,fill:Pixel(0,0,0,0.375))
    XCTAssertTrue(MaskFiltering.available(d,layerID:layer.id,target:.layerMask,kind:.average))
    let before=d
    try Command.maskFilter(.init(layerID:layer.id,target:.layerMask,filter:filter(.average))).apply(to:&d)
    XCTAssertEqual(d,before);XCTAssertEqual(d.layers[0].mask?.tileCount,0)
  }
  func testMaskFilteringDoesNotRequireRasterOrSmartObjectColorContent() throws {
    for content:LayerContent in [.fill(Pixel(1,0,0)),.text(TextContent(text:"Owned")),.group(.init())] {
      var d=try fixture();d.layers[0].content=content
      let before=d
      try Command.maskFilter(.init(layerID:d.layers[0].id,target:.layerMask,filter:filter(.average))).apply(to:&d)
      XCTAssertEqual(d.layers[0].content,before.layers[0].content)
    }
  }
  func testInvalidKindsMissingMasksAndLocksCannotPublish() throws {
    var d=try fixture(),before=d
    XCTAssertThrowsError(try Command.maskFilter(.init(layerID:d.layers[0].id,target:.smartFilterMask,filter:filter(.average))).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try Command.maskFilter(.init(layerID:d.layers[0].id,target:.layerMask,filter:filter(.cameraRaw))).apply(to:&d));XCTAssertEqual(d,before)
    d.layers[0].locked=true;before=d
    XCTAssertFalse(MaskFiltering.available(d,layerID:d.layers[0].id,target:.layerMask,kind:.boxBlur))
    XCTAssertThrowsError(try Command.maskFilter(.init(layerID:d.layers[0].id,target:.layerMask,filter:filter(.average))).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testCancelledMaskFilterLeavesTheOriginalUnchanged() async throws {
    let original=try fixture(),task=Task {var d=original;while !Task.isCancelled {await Task.yield()};try Command.maskFilter(.init(layerID:d.layers[0].id,target:.layerMask,filter:RasterFilter(.boxBlur))).apply(to:&d);return d}
    task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled filter published")}
    catch is CancellationError {} catch {XCTFail("Unexpected cancellation error: \(error)")}
    XCTAssertNotNil(original.layers[0].mask)
  }
  func testLinearStorageAndUnselectedIgnoredSamplesRemainBitIdentical() throws {
    for target in MaskFilterTarget.allCases {
      var d=try fixture(.f32,target:target)
      let raw=try XCTUnwrap(mask(d,target))
      let linear=try raw.mappedStoredSamples(encoding:.linearRGB){SRGBTransfer.linear($0)}.retaggedCoverageStorage(depth:.f32,encoding:.linearRGB)
      if target == .layerMask {d.layers[0].mask=linear}else{d.layers[0].smartFilters?.mask=linear}
      d.selection = .init(x:0,y:11,width:1,height:1)
      let before=d
      try Command.maskFilter(.init(layerID:d.layers[0].id,target:target,filter:filter(.average))).apply(to:&d)
      XCTAssertEqual(d,before)
    }
  }
  func testRecordingMaskFilterNeverSubstitutesAColorFilter() throws {
    let d=try fixture(),command=Command.maskFilter(.init(layerID:d.layers[0].id,target:.layerMask,filter:filter(.boxBlur)))
    let operation=ActionOperation(recording:command,in:d)
    guard case .unsupported(let reason)=operation else {return XCTFail("Mask filter was misrecorded as another target")}
    XCTAssertTrue(reason.contains("Mask filtering"))
  }

}
