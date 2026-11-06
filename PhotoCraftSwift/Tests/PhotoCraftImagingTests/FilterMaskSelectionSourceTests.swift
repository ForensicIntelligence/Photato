import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class FilterMaskSelectionSourceTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:8,depth:depth)
    d.layers[0].locked=false;d.layers[0].background=nil
    try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d)
    var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.gaussianBlur))]
    var mask=try Surface(width:2,height:2,depth:.u8,fill:.black)
    mask.setPixel(x:1,y:0,Pixel(64.0/255,64.0/255,64.0/255));mask.setPixel(x:0,y:1,Pixel(128.0/255,128.0/255,128.0/255));mask.setPixel(x:1,y:1,.white)
    stack.mask=mask;stack.maskProperties.transform = .translation(3,2);stack.maskProperties.outside=1
    stack.maskProperties.density=0.2;stack.maskProperties.feather=2;stack.enabled=false
    d.layers[0].mask=try Surface(width:8,height:8,depth:.u8,fill:.black)
    d.layers[0].smartFilters=stack;try d.validate();return d
  }
  func testFilterMaskUsesRawNumericPlaneDocumentTransformAndOutsideWithoutChangingSource()throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id,original=try NativeArchive.encodeChunked(d)
      let source=SelectionChannelSource.smartFilterMask(id),mask=try source.selection(in:d)
      XCTAssertTrue(SelectionChannelSource.choices(in:d).contains(source));XCTAssertEqual(source.title(in:d),d.layers[0].name+" Filter Mask")
      for y in 0..<8 {for x in 0..<8 {
        let expected:UInt8 = x==3 && y==2 ? 0:x==4 && y==2 ? 64:x==3 && y==3 ? 128:255
        XCTAssertEqual(mask.byte(at:y*8+x),expected,"depth=\(depth) x=\(x) y=\(y)")
      }}
      let inverted=try source.selection(in:d,invert:true);XCTAssertEqual(inverted.byte(at:2*8+3),255);XCTAssertEqual(inverted.byte(at:3*8+4),0)
      XCTAssertEqual(try NativeArchive.encodeChunked(d),original)
      XCTAssertNotEqual(mask,try SelectionChannelSource.layerMask(id).selection(in:d))
    }
  }
  func testMaximumSparseCanvasFilterMaskSourceRetainsBoundedCoverage()throws {
    var d=try fixture();d.width=300_000;d.height=300_000;d.layers[0].smartFilters?.maskProperties.transform = .translation(299_990,299_990)
    d.layers[0].mask=nil;try d.validate()
    let mask=try SelectionChannelSource.smartFilterMask(d.layers[0].id).selection(in:d,invert:true)
    XCTAssertEqual(mask.width,300_000);XCTAssertTrue(mask.isPaged);XCTAssertLessThan(mask.allocatedBytes,1_048_576)
    XCTAssertEqual(mask.byte(at:299_990*300_000+299_990),255);XCTAssertEqual(mask.byte(at:0),0)
    XCTAssertEqual(mask.bounds,.init(x:299_990,y:299_990,width:2,height:2))
  }
  func testMissingOwnersMasksAndCancellationDoNotReturnCoverage()async throws {
    var d=try fixture();let id=d.layers[0].id
    XCTAssertThrowsError(try SelectionChannelSource.smartFilterMask(UUID()).selection(in:d))
    d.layers[0].smartFilters?.mask=nil;XCTAssertFalse(SelectionChannelSource.choices(in:d).contains(.smartFilterMask(id)))
    XCTAssertThrowsError(try SelectionChannelSource.smartFilterMask(id).selection(in:d))
    let original=try fixture(),source=SelectionChannelSource.smartFilterMask(original.layers[0].id)
    let task=Task {try Task.checkCancellation();return try source.selection(in:original)};task.cancel()
    do{_ = try await task.value;XCTFail("Cancelled source returned")}catch is CancellationError{}
  }
}
