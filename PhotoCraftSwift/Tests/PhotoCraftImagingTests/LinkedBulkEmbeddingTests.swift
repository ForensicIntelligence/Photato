import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LinkedBulkEmbeddingTests:XCTestCase {
  func fixture()throws->(CraftDocument,[UUID:Data]) {
    var doc=try CraftDocument(width:12,height:8);var originals:[UUID:Data]=[:]
    for color in [Pixel(0.7,0.2,0.1),Pixel(0.1,0.4,0.8)] {
      let data=try RasterIO.encoded(Surface(width:4,height:2,fill:color))
      let reference=try LinkedSmartObjectSource(reference:"file:///fixture/"+UUID().uuidString+".png",contentHash:LinkedSmartObjectSource.fingerprint(data),byteLength:UInt64(data.count))
      let layer=try LinkedSmartObjectIO.place(data,fileName:"Artwork.png",reference:reference,in:doc,fit:false)
      originals[layer.smartObject!.sourceID]=data;try Command.addLayer(layer).apply(to:&doc)
    }
    var copy=doc.layers.last!;copy.id=UUID();copy.name="Shared instance";try Command.addLayer(copy).apply(to:&doc)
    return(doc,originals)
  }
  func testEmbedAllPreservesPixelsOriginalsSharedIdentityAndOneUndo()throws {
    let (original,bytes)=try fixture();var session=EditorSession(document:original)
    let pixels=try Renderer.composite(original).rgbaData(depth:.u8)
    try session.execute(LinkedSmartObjectIO.embed(original))
    XCTAssertTrue(session.document.layers.allSatisfy{$0.smartObject?.linkedSource==nil});XCTAssertEqual(session.undoStack.count,1)
    for layer in session.document.layers {if let source=layer.smartObject{XCTAssertEqual(source.data,bytes[source.sourceID])}}
    XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth:.u8),pixels)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document)
    try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertTrue(session.document.layers.allSatisfy{$0.smartObject?.linkedSource==nil})
  }
  func testUnresolvedAllNeedsEveryOriginalAndLockedSourceKeepsAtomicHistory()throws {
    let (original,bytes)=try fixture(),unresolved=try NativeArchive.decode(NativeArchive.encodeChunked(original))
    XCTAssertThrowsError(try LinkedSmartObjectIO.embed(unresolved))
    var partial=bytes;partial.removeValue(forKey:bytes.keys.first!);XCTAssertThrowsError(try LinkedSmartObjectIO.embed(unresolved,originals:partial))
    var session=EditorSession(document:unresolved);try session.execute(LinkedSmartObjectIO.embed(unresolved,originals:bytes));XCTAssertEqual(session.undoStack.count,1)
    var locked=unresolved;locked.layers[locked.layers.count-1].locked=true
    XCTAssertThrowsError(try LinkedSmartObjectIO.embed(locked,originals:bytes));XCTAssertEqual(unresolved,try NativeArchive.decode(NativeArchive.encodeChunked(original)))
  }
  func testEmbeddingPDFInstancesPreservesEachPageCropDimensionsAndPixels()throws {
    let helper=PDFSmartObjectTests(),bytes=try helper.data()
    var original=try CraftDocument(width:432,height:324)
    let reference=try LinkedSmartObjectSource(reference:"file:///fixture/pages.pdf",contentHash:LinkedSmartObjectSource.fingerprint(bytes),byteLength:UInt64(bytes.count))
    let first=try LinkedSmartObjectIO.linked(PDFSmartObjectIO.placed(bytes,fileName:"Pages.pdf",in:original,settings:helper.settings(.media,page:1),fit:false),reference:reference)
    var second=try LinkedSmartObjectIO.linked(PDFSmartObjectIO.placed(bytes,fileName:"Pages.pdf",in:original,settings:helper.settings(.trim,page:2),fit:false),reference:reference)
    try Command.addLayer(first).apply(to:&original);try Command.addLayer(second).apply(to:&original)
    var session=EditorSession(document:original);try session.execute(LinkedSmartObjectIO.embed(original))
    for index in [1,2] {
      XCTAssertEqual(session.document.layers[index].smartObject?.pdfSource,original.layers[index].smartObject?.pdfSource)
      XCTAssertEqual(session.document.layers[index].smartObject?.width,original.layers[index].smartObject?.width)
      XCTAssertEqual(session.document.layers[index].smartObject?.height,original.layers[index].smartObject?.height)
      XCTAssertEqual(session.document.layers[index].smartObject?.data,bytes)
    }
    XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth:.u8),try Renderer.composite(original).rgbaData(depth:.u8))
  }

}
