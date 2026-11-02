import XCTest
import UniformTypeIdentifiers
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LinkedSmartObjectIOTests:XCTestCase {
  func bytes(_ width:Int=4,_ height:Int=3,_ color:Pixel=Pixel(0.2,0.4,0.6))throws->Data {
    try RasterIO.encoded(Surface(width:width,height:height,fill:color),type:.png)
  }
  func reference(_ data:Data,_ name:String="Logo.png")throws->LinkedSmartObjectSource {
    try .init(reference:"file:///does-not-exist/"+name,authorizationID:UUID(),contentHash:LinkedSmartObjectSource.fingerprint(data),byteLength:UInt64(data.count))
  }
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:24,height:20);let data=try bytes()
    var layer=try LinkedSmartObjectIO.place(data,fileName:"Logo.png",reference:reference(data),in:d)
    layer.x=3;layer.y=4;layer.affine = .scale(2,2);layer.mask=try Surface(width:4,height:3,fill:.white)
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  func testLinkedRefreshSharedInstancesGeometryMasksUndoAndLockAtomicity()throws {
    var d=try fixture();let id=d.layers[0].id;try Command.duplicateLayer(id).apply(to:&d)
    let before=d,transform=d.layers[0].coordinateTransform,mask=d.layers[0].maskCoordinateTransform,data=try bytes(3,6,Pixel(1,0,0))
    let command=try LinkedSmartObjectIO.replacement(data,fileName:"Changed.png",reference:reference(data,"Changed.png"),in:d,layerID:id)
    var session=EditorSession(document:d);try session.execute(command)
    for layer in session.document.layers {
      XCTAssertEqual(layer.smartObject?.width,3);XCTAssertEqual(layer.smartObject?.height,6)
      XCTAssertEqual(layer.coordinateTransform,transform);XCTAssertEqual(layer.maskCoordinateTransform,mask)
      XCTAssertEqual(layer.smartObject?.sourceID,before.layers[0].smartObject?.sourceID)
      XCTAssertNotNil(layer.smartObject?.linkedSource)
    }
    try session.undo();XCTAssertEqual(session.document,before)
    d.layers[1].locked=true;let locked=d
    XCTAssertThrowsError(try LinkedSmartObjectIO.replacement(data,fileName:"Changed.png",reference:reference(data),in:d,layerID:id));XCTAssertEqual(d,locked)
  }
  func testNativeLinkAndEmbedRetagRetainsPixelsAndRejectsMismatchedFile()throws {
    let d=try fixture(),id=d.layers[0].id,source=try XCTUnwrap(d.layers[0].smartObject)
    let command=try LinkedSmartObjectIO.retag(d,layerID:id,source:source.embedding(),title:"Embed Linked")
    var result=d;try command.apply(to:&result)
    XCTAssertNil(result.layers[0].smartObject?.linkedSource);XCTAssertEqual(result.layers[0].content,d.layers[0].content)
    XCTAssertEqual(result.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
    var wrong=try source.embedding();wrong.data=try bytes(4,3,.black)
    XCTAssertThrowsError(try LinkedSmartObjectIO.retag(d,layerID:id,source:wrong,title:"Mismatch"))
  }
  func testPSDAndPSBExternalRecordsRetainCachedPixelsAndNeverReadPaths()throws {
    let source=try fixture()
    for format in [PSDFileFormat.psd,.psb] {
      let data=try PSDCodec.writeRasterLayers(source,format:format)
      let decoded=try PSDCodec.read(data)
      let layer=try XCTUnwrap(decoded.layers.first),object=try XCTUnwrap(layer.smartObject)
      XCTAssertNotNil(object.linkedSource);XCTAssertNil(object.linkedSource?.authorizationID);XCTAssertTrue(object.data.isEmpty)
      XCTAssertNotNil(try layer.linkedSmartObjectPreview())
      XCTAssertEqual(try layer.smartObjectSourceTransform(),source.layers[0].coordinateTransform)
      let actual=try Renderer.composite(decoded),expected=try Renderer.composite(source)
      let a=try actual.rgbaData(depth:.u8),b=try expected.rgbaData(depth:.u8)
      if a != b {let differences=zip(a,b).enumerated().filter{$0.element.0 != $0.element.1}.prefix(16).map{[$0.offset,Int($0.element.0),Int($0.element.1)]};print("LINKED_PREVIEW_DIFFERENCES",differences,"cacheSize",[layer.smartObject?.width ?? 0,layer.smartObject?.height ?? 0],"maskTransform",layer.maskCoordinateTransform)}
      XCTAssertEqual(a,b)
      let reopened=try NativeArchive.decodePaged(NativeArchive.encodeChunked(decoded));XCTAssertEqual(reopened,decoded)
      let rewritten=try PSDCodec.read(PSDCodec.writeRasterLayers(decoded,format:format))
      XCTAssertEqual(try Renderer.composite(rewritten).rgbaData(depth:.u8),try Renderer.composite(decoded).rgbaData(depth:.u8))
    }
  }
  func testResolvingUnscaledCacheRestoresTrueTransformWithoutResamplingOriginal()throws {
    let original=try fixture(),encoded=try PSDCodec.writeRasterLayers(original)
    let cached=try PSDCodec.read(encoded),id=cached.layers[0].id,data=try bytes(3,6,Pixel(0,1,0))
    let command=try LinkedSmartObjectIO.replacement(data,fileName:"New.png",reference:reference(data,"New.png"),in:cached,layerID:id)
    var resolved=cached;try command.apply(to:&resolved)
    XCTAssertNil(try resolved.layers[0].linkedSmartObjectPreview())
    XCTAssertEqual(resolved.layers[0].coordinateTransform,original.layers[0].coordinateTransform)
    XCTAssertEqual(resolved.layers[0].maskCoordinateTransform,cached.layers[0].maskCoordinateTransform)
    guard case .raster(let surface)=resolved.layers[0].content else{return XCTFail()}
    XCTAssertEqual(surface.width,3);XCTAssertEqual(surface.height,6)
  }
}
