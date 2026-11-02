import XCTest
@testable import PhotoCraftCore

final class LinkedSmartObjectTests:XCTestCase {
  func fixture()throws->(CraftDocument,Data) {
    var d=try CraftDocument(width:300_000,height:300_000)
    let bytes=Data(repeating:73,count:1_000_000)
    let reference=try LinkedSmartObjectSource(reference:"file:///definitely-missing/Logo.png",authorizationID:UUID(),
      contentHash:LinkedSmartObjectSource.fingerprint(bytes),byteLength:UInt64(bytes.count))
    d.layers[0].content = .raster(try Surface(width:2,height:2,fill:Pixel(0.2,0.4,0.6)))
    d.layers[0].smartObject=try SmartObject(fileName:"Logo.png",mediaType:"image/png",data:bytes,width:2,height:2).linked(to:reference)
    return (d,bytes)
  }
  func testNative66OmitsOriginalBytesRetainsPreviewIdentityAndLogicalRevision()throws {
    let (d,bytes)=try fixture();XCTAssertEqual(d.minimumArchiveVersion,66)
    let archive=try NativeArchive.encodeChunked(d);XCTAssertLessThan(archive.count,65536)
    let restored=try NativeArchive.decodePaged(archive)
    XCTAssertEqual(restored,d);XCTAssertTrue(restored.layers[0].smartObject!.data.isEmpty)
    XCTAssertEqual(restored.layers[0].smartObject?.linkedSource,d.layers[0].smartObject?.linkedSource)
    XCTAssertEqual(restored.layers[0].smartObject?.revision,d.layers[0].smartObject?.revision)
    XCTAssertEqual(d.layers[0].smartObject?.data,bytes)
    XCTAssertEqual(restored.layers[0].content,d.layers[0].content)
  }
  func testHydrationKeepsHistoryAndRejectsChangedBytesAtomically()throws {
    let (source,bytes)=try fixture();let saved=try NativeArchive.decodePaged(NativeArchive.encodeChunked(source))
    var session=EditorSession(document:saved);let revision=saved.layers[0].smartObject!.revision
    try session.hydrateLinkedSmartObject(saved.layers[0].smartObject!.sourceID,bytes:bytes)
    XCTAssertEqual(session.document,saved);XCTAssertEqual(session.document.layers[0].smartObject?.data,bytes)
    XCTAssertTrue(session.undoStack.isEmpty);XCTAssertEqual(session.document.layers[0].smartObject?.revision,revision)
    let before=session.document
    XCTAssertThrowsError(try session.hydrateLinkedSmartObject(saved.layers[0].smartObject!.sourceID,bytes:Data([1,2,3])))
    XCTAssertEqual(session.document,before);XCTAssertEqual(session.document.layers[0].smartObject?.data,bytes)
  }
  func testRemoteLocatorNeverArchivesPresignedCredentialsAndDecodeDoesNotResolve()throws {
    let bytes=Data([1,2,3]);let url=try XCTUnwrap(URL(string:"https://user:password@example.invalid/assets/logo.png?signature=secret#private"))
    let ref=try LinkedSmartObjectSource.remote(url,data:bytes)
    XCTAssertEqual(ref.reference,"https://example.invalid/assets/logo.png");XCTAssertNil(ref.authorizationID)
    XCTAssertThrowsError(try LinkedSmartObjectSource(reference:url.absoluteString,kind:.remote,byteLength:3))
    XCTAssertThrowsError(try LinkedSmartObjectSource(reference:"bad\0link",byteLength:3))
    XCTAssertThrowsError(try LinkedSmartObjectSource(reference:"file:///tmp/source",contentHash:"wrong",byteLength:3))
    let (d,_)=try fixture();let encoded=try JSONEncoder().encode(d.layers[0].smartObject!)
    let fields=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded)as?[String:Any])
    XCTAssertNil(fields["data"]);XCTAssertNil(fields["sourceBlob"]);XCTAssertNotNil(fields["linkedSource"])
  }
  func testEmbeddingRequiresTheMatchingResolvedFileAndPreparedEditRejectsStaleTarget()throws {
    let (source,bytes)=try fixture();let old=source.layers[0].smartObject!
    let saved=try NativeArchive.decodePaged(NativeArchive.encodeChunked(source))
    XCTAssertThrowsError(try saved.layers[0].smartObject!.embedding())
    let embedded=try saved.layers[0].smartObject!.hydrating(bytes).embedding();XCTAssertNil(embedded.linkedSource);XCTAssertEqual(embedded.data,old.data)
    var result=source;result.layers[0].smartObject=embedded
    let command=Command.linkedSmartObject(try .init(source:source,result:result,title:"Embed Linked"))
    var session=EditorSession(document:source);try session.execute(command);XCTAssertNil(session.document.layers[0].smartObject?.linkedSource)
    try session.undo();XCTAssertEqual(session.document,source)
    var changed=source;changed.name="Changed";let before=changed
    XCTAssertThrowsError(try command.apply(to:&changed));XCTAssertEqual(changed,before)
  }
}
