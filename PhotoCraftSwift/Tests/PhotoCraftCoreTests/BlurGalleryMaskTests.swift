import Foundation
import XCTest
@testable import PhotoCraftCore

final class BlurGalleryMaskTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:20,height:16,depth:depth),s=try Surface(width:20,height:16,depth:depth)
    for y in 0..<16 {for x in 0..<20 {s.setPixel(x:x,y:y,Pixel(Float(x%7)/6,Float(y%5)/4,0.3,(x+y)%4==0 ? 0.4:1))}}
    d.layers[0].content = .raster(s);return d
  }
  func testOwnedPhotoshopFieldFiveMaskIsExactlyFullCoverage()throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"owned-field5-mask",withExtension:"u8",subdirectory:"Fixtures/BlurGalleryMasks"))
    let reference=try Data(contentsOf:url);XCTAssertEqual(reference.count,10000)
    var d=try CraftDocument(width:100,height:100),settings=BlurGallerySettings();settings.field[0].blur=5
    // Transparent source is deliberate: mask coverage is geometric, not image alpha.
    d.layers[0].content = .raster(try Surface(width:100,height:100))
    let mask=try BlurGalleryMask.surface(in:d,layer:d.layers[0],settings:settings)
    let actual=Data((0..<10000).map{UInt8((mask.pixel(x:$0%100,y:$0/100).r*255).rounded())})
    XCTAssertEqual(actual,reference)
  }
  func testNormalizedToolsSharpRegionsAndPathTaper()throws {
    for mode in BlurGallerySettings.Mode.allCases {
      var s=BlurGallerySettings();s.enabled=[mode]
      let center=BlurGalleryMask.value(s,x:10,y:8,width:20,height:16),edge=BlurGalleryMask.value(s,x:0,y:0,width:20,height:16)
      switch mode {
      case .field,.path:XCTAssertEqual(center,1);XCTAssertEqual(edge,1)
      case .iris,.tiltShift:XCTAssertEqual(center,0);XCTAssertEqual(edge,1)
      case .spin:XCTAssertEqual(center,1);XCTAssertEqual(edge,0)
      }
      s.enabled=[];XCTAssertEqual(BlurGalleryMask.value(s,x:10,y:8,width:20,height:16),0)
    }
    var s=BlurGallerySettings();s.enabled=[.path];s.paths[0].taper=100
    XCTAssertEqual(BlurGalleryMask.value(s,x:4,y:8,width:20,height:16),1,accuracy:1e-12)
    XCTAssertEqual(BlurGalleryMask.value(s,x:16,y:8,width:20,height:16),0,accuracy:1e-12)
    s=BlurGallerySettings();s.field[0].blur=5
    let low=BlurGalleryMask.value(s,x:2,y:3,width:20,height:16);s.field[0].blur=500
    XCTAssertEqual(BlurGalleryMask.value(s,x:2,y:3,width:20,height:16),low)
  }
  func testSparseMaximumCanvasTranslationClippingAndHugeTransformGuard()throws {
    var d=try CraftDocument(width:Surface.maxDimension,height:Surface.maxDimension)
    d.layers[0].content = .raster(try Surface(width:4,height:3));d.layers[0].x = -1;d.layers[0].y=2
    let m=try BlurGalleryMask.surface(in:d,layer:d.layers[0],settings:.init())
    XCTAssertEqual(m.width,Surface.maxDimension);XCTAssertEqual(m.pixel(x:0,y:2).r,1)
    XCTAssertEqual(m.pixel(x:2,y:4).r,1);XCTAssertEqual(m.pixel(x:3,y:4).r,0);XCTAssertEqual(m.pixel(x:0,y:1).r,0)
    d.layers[0].affine = .scale(10000,10000)
    XCTAssertThrowsError(try BlurGalleryMask.surface(in:d,layer:d.layers[0],settings:.init()))
    d.layers[0].affine = .scale(1e200,1e200)
    XCTAssertThrowsError(try BlurGalleryMask.surface(in:d,layer:d.layers[0],settings:.init()))
  }
  func testAtomicFilterPixelsAllModesDepthsAndUndoRedo()throws {
    for depth in PixelDepth.allCases {for mode in BlurGallerySettings.Mode.allCases {
      let d=try fixture(depth),id=d.layers[0].id;var settings=BlurGallerySettings();settings.enabled=[mode]
      let edit=BlurGalleryMaskEdit(layerID:id,settings:settings);var expected=d
      try edit.filterCommand(in:d).apply(to:&expected)
      var session=EditorSession(document:d);let command=Command.blurGalleryMask(edit)
      try session.execute(command);let after=session.document
      XCTAssertEqual(after.layers,expected.layers);XCTAssertEqual(after.selection,d.selection);XCTAssertEqual(after.alphaChannels?.count,1)
      XCTAssertEqual(after.alphaChannels?.first?.id,edit.channelID);XCTAssertEqual(after.alphaChannels?.first?.name,"Blur Mask")
      XCTAssertEqual(after.alphaChannels?.first?.pixels.depth,depth);XCTAssertEqual(after.alphaChannels?.first?.pixels.colorEncoding,.sRGB)
      XCTAssertEqual(command.filterRecallValue(in:d),edit.filter)
      XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,after)
    }}
  }
  func testFailureIsAtomicAndExistingChannelsAndSelectionSurvive()throws {
    var d=try fixture();let plane=try Surface(width:d.width,height:d.height,fill:.black)
    d.alphaChannels=[AlphaChannel(name:"Blur Mask",pixels:plane),AlphaChannel(name:"Blur Mask 2",pixels:plane)];d.selection = .init(x:3,y:2,width:6,height:5)
    let before=d,edit=BlurGalleryMaskEdit(layerID:d.layers[0].id,settings:.init());try Command.blurGalleryMask(edit).apply(to:&d)
    XCTAssertEqual(Array(d.alphaChannels!.prefix(2)),before.alphaChannels!);XCTAssertEqual(d.alphaChannels?.last?.name,"Blur Mask 3");XCTAssertEqual(d.selection,before.selection)
    var bad=before;let duplicate=BlurGalleryMaskEdit(layerID:bad.layers[0].id,settings:.init(),channelID:bad.alphaChannels![0].id)
    XCTAssertThrowsError(try Command.blurGalleryMask(duplicate).apply(to:&bad));XCTAssertEqual(bad,before)
    bad.layers[0].locked=true;let locked=bad
    XCTAssertThrowsError(try Command.blurGalleryMask(edit).apply(to:&bad));XCTAssertEqual(bad,locked)
    bad=before;bad.alphaChannels=(0..<CraftDocument.maximumAlphaChannels).map{AlphaChannel(name:"Channel \($0)",pixels:plane)};let full=bad
    XCTAssertThrowsError(try Command.blurGalleryMask(edit).apply(to:&bad));XCTAssertEqual(bad,full)
  }
  func testCancelledOutputDoesNotPublish()async throws {
    let d=try fixture(),edit=BlurGalleryMaskEdit(layerID:try XCTUnwrap(d.activeLayerID),settings:.init())
    let task=Task {var value=d;withUnsafeCurrentTask{$0?.cancel()};do{try Command.blurGalleryMask(edit).apply(to:&value);XCTFail("Expected cancellation")}catch is CancellationError{};XCTAssertEqual(value,d)}
    try await task.value
  }
}
