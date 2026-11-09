import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDArtboardTests:XCTestCase {
  func fixtureURL(_ name:String) throws -> URL {
    try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("PSDArtboards/"+name)
  }
  func fixture(_ name:String) throws -> Data { try Data(contentsOf:fixtureURL(name)) }
  func rawMerged(_ data:Data) throws -> Data {
    var r=PSDReader(data:data);XCTAssertEqual(try r.string(4),"8BPS");let version=try r.u16()
    _ = try r.bytes(20);_ = try r.section();_ = try r.section();_ = try r.section(lengthBytes:version==2 ? 8:4)
    XCTAssertEqual(try r.u16(),0);return try r.bytes(r.remaining)
  }
  func assertBoards(_ d:CraftDocument,file:StaticString = #filePath,line:UInt = #line) throws {
    XCTAssertEqual(d.width,420,file:file,line:line);XCTAssertEqual(d.height,172,file:file,line:line)
    XCTAssertEqual(d.layers.count,4,file:file,line:line);XCTAssertEqual(d.artboards.count,2,file:file,line:line)
    XCTAssertEqual(d.artboardOrigin,.init(x:-20,y:-12),file:file,line:line)
    let first=d.artboards[0],second=d.artboards[1]
    XCTAssertEqual(first.name,"Artboard 1",file:file,line:line);XCTAssertEqual(second.name,"Second Board Ω",file:file,line:line)
    XCTAssertEqual(d.logicalArtboardBounds(first),IntRect(x:-20,y:-12,width:160,height:120),file:file,line:line)
    XCTAssertEqual(d.logicalArtboardBounds(second),IntRect(x:240,y:40,width:160,height:120),file:file,line:line)
    XCTAssertEqual(first.artboard?.background,.black,file:file,line:line)
    XCTAssertEqual(second.artboard?.guides.count,1,file:file,line:line)
    XCTAssertEqual(second.artboard?.guides.first?.axis,.vertical,file:file,line:line)
    XCTAssertEqual(second.artboard?.guides.first?.position,25,file:file,line:line)
    XCTAssertEqual(d.guides,[],file:file,line:line)
    let child=try XCTUnwrap(d.children(of:second.id).first,file:file,line:line)
    guard case .raster(let pixels)=child.content else { return XCTFail("Editable child raster was flattened",file:file,line:line) }
    XCTAssertEqual(pixels.width,21,file:file,line:line);XCTAssertEqual(pixels.height,21,file:file,line:line)
    XCTAssertEqual(child.x,319,file:file,line:line);XCTAssertEqual(child.y,103,file:file,line:line)
  }
  func testOwnedPhotoshopPSDBoardsAndPSBRetainAllDepthsGeometryGuidesAndPixels() throws {
    for bits in [8,16,32] { for ext in ["psd","psb"] {
      let input=try fixture("owned-guide-rgb\(bits).\(ext)"),doc=try PSDCodec.read(input)
      try assertBoards(doc)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(doc)),doc)
      let paged=try PSDCodec.readPaged(input,heapByteLimit:134_217_728)
      try assertBoards(paged)
      XCTAssertEqual(try Renderer.composite(doc),try Renderer.composite(paged))
      XCTAssertEqual(try fixture("owned-guide-rgb\(bits).\(ext)"),input)
    } }
  }
  func testMergedSamplesMatchIndependentPhotoshopPlanesExactly() throws {
    var records:[[String:Any]]=[]
    for bits in [8,16,32] { for format in [PSDFileFormat.psd,.psb] {
      let input=try fixture("owned-guide-rgb\(bits).\(format == .psd ? "psd":"psb")"),doc=try PSDCodec.read(input)
      let output=try PSDCodec.writeRasterLayers(doc,format:format,compositeCompression:.raw)
      let actual=try rawMerged(output),expected=try fixture("owned-merged-rgb\(bits).bin")
      let changed=zip(actual,expected).filter{$0 != $1}.count
      XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(changed,0,"RGB\(bits) \(format)")
      records.append(["depth":bits,"format":format.rawValue,"bytes":actual.count,"changed_bytes":changed])
      if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try output.write(to:URL(fileURLWithPath:folder).appendingPathComponent("artboard-rgb\(bits).\(format == .psd ? "psd":"psb")"))
      }
    } }
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:folder).appendingPathComponent("artboard-independent-merged.json"))
    }
  }
  func testFourBackgroundKindsAndOriginalDescriptorBytesRemainExact() throws {
    for (name,expected) in [("white",Pixel.white),("black",Pixel.black),("transparent",Pixel.clear)] {
      let doc=try PSDCodec.read(fixture("owned-\(name)-rgb8.psd")),layer=try XCTUnwrap(doc.artboards.first)
      XCTAssertEqual(layer.artboard?.background,expected)
      let prepared=try PSDArtboards.prepare(doc)
      XCTAssertEqual(prepared.layers[layer.id]?.1,layer.sourceTags?["artb"])
      XCTAssertEqual(prepared.global?.1,doc.sourceMetadata?["psdGlobal_artd"])
      XCTAssertEqual(try Renderer.composite(doc).pixel(x:20,y:20),expected)
    }
    for bits in [8,16,32] {
      let doc=try PSDCodec.read(fixture("owned-guide-rgb\(bits).psd")),prepared=try PSDArtboards.prepare(doc)
      for layer in doc.artboards { XCTAssertEqual(prepared.layers[layer.id]?.1,layer.sourceTags?["artb"]) }
      XCTAssertEqual(prepared.global?.1,doc.sourceMetadata?["psdGlobal_artd"])
    }
  }
  func testGeometryAppearancePresetGuideEditsHistoryAndUngroupReplaceActiveMetadata() throws {
    let original=try PSDCodec.read(fixture("owned-guide-rgb8.psd")),target=original.artboards[1]
    var board=try XCTUnwrap(target.artboard);board.width=140;board.height=100;board.background = .white;board.preset="Owned layout"
    board.guides=[.init(axis:.vertical,position:7.5),.init(axis:.horizontal,position:8.125)]
    var session=EditorSession(document:original)
    try session.execute(.artboard(.configure(target.id,name:"Board edited Ω",bounds:.init(x:260,y:60,width:140,height:100),appearance:board,moveContents:false)))
    let edited=session.document;try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,edited)
    for format in [PSDFileFormat.psd,.psb] {
      let read=try PSDCodec.read(PSDCodec.writeRasterLayers(edited,format:format)),layer=try XCTUnwrap(read.artboards.last)
      XCTAssertEqual(layer.name,"Board edited Ω");XCTAssertEqual(read.logicalArtboardBounds(layer),IntRect(x:260,y:60,width:140,height:100))
      XCTAssertEqual(layer.artboard?.background,.white);XCTAssertEqual(layer.artboard?.preset,"Owned layout")
      XCTAssertEqual(layer.artboard?.guides.map(\.position),[7.5,8.125]);XCTAssertEqual(read.guides,[])
      let before=try XCTUnwrap(original.children(of:target.id).first),after=try XCTUnwrap(read.children(of:layer.id).first)
      XCTAssertEqual(before.content,after.content);XCTAssertEqual(before.x,after.x);XCTAssertEqual(before.y,after.y)
    }
    try session.execute(.artboard(.removeMetadata(target.id)))
    let one=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document));XCTAssertEqual(one.artboards.count,1)
    let remaining=try XCTUnwrap(session.document.artboards.first)
    try session.execute(.artboard(.removeMetadata(remaining.id)))
    let none=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document));XCTAssertFalse(none.hasArtboards)
    XCTAssertNil(none.sourceMetadata?["psdGlobal_artd"])
    XCTAssertTrue(none.layers.allSatisfy{$0.sourceTags?["artb"]==nil})
  }
  func testCanvasGuidesAndArtboardGuidesRetainOwnershipAfterDuplicationAndExtraction() throws {
    var doc=try PSDCodec.read(fixture("owned-guide-rgb8.psd"));doc.guides=[.init(axis:.horizontal,position:10)]
    var session=EditorSession(document:doc);let target=doc.artboards[1]
    try session.execute(.artboard(.duplicate(target.id,x:500,y:40,name:"Copied board")))
    let saved=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document,format:.psb))
    XCTAssertEqual(saved.artboards.count,3);XCTAssertEqual(saved.guides?.map(\.position),[10])
    XCTAssertEqual(saved.artboards[1].artboard?.guides.map(\.position),[25]);XCTAssertEqual(saved.artboards[2].artboard?.guides.map(\.position),[25])
    let one=try doc.extractedArtboard(target.id),read=try PSDCodec.read(PSDCodec.writeRasterLayers(one))
    XCTAssertEqual(read.artboards.count,1);XCTAssertEqual(read.artboardOrigin,.init())
    XCTAssertEqual(read.artboards[0].artboardBounds,IntRect(x:0,y:0,width:160,height:120))
    XCTAssertEqual(read.artboards[0].artboard?.guides.map(\.position),[25]);XCTAssertEqual(read.guides?.map(\.position),[-42])
    let before=try XCTUnwrap(doc.children(of:target.id).first),after=try XCTUnwrap(read.children(of:read.artboards[0].id).first)
    XCTAssertEqual(before.content,after.content);XCTAssertEqual(after.x,59);XCTAssertEqual(after.y,51)
  }
  func testMalformedFieldsUnsupportedContextsAndCancellationRejectWithoutChangingSource() async throws {
    let input=try fixture("owned-guide-rgb8.psd"),original=try PSDCodec.read(input),id=original.artboards[1].id
    let index=try XCTUnwrap(original.layers.firstIndex{$0.id==id}),data=try XCTUnwrap(original.layers[index].sourceTags?["artb"])
    for change in [0,1,2,3] {
      var doc=original,d=try PSDDescriptor.read(data,padding:true)
      if change==0 { PSDArtboards.set(&d,"unknown",.boolean(true)) }
      if change==1 { PSDArtboards.set(&d,"artboardBackgroundType",.integer(5)) }
      if change==2 { var rect=try PSDArtboards.object(d["artboardRect"]);PSDArtboards.set(&rect,"Left",.number(0.5));PSDArtboards.set(&d,"artboardRect",.object(rect)) }
      if change==3 { PSDArtboards.set(&d,"guideIndeces",.list([.integer(0),.integer(0)])) }
      doc.layers[index].sourceTags?["artb"]=try d.encoded()
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
    }
    var doc=original,group=try XCTUnwrap(doc.layers[index].group),board=try XCTUnwrap(group.artboard)
    board.background.a=0.5;group.artboard=board;doc.layers[index].content = .group(group)
    XCTAssertNotNil(PSDArtboardInterchange.photoshopPersistenceIssue(doc));XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
    board.background = .white;board.guides=[.init(axis:.vertical,position:0.1)];group.artboard=board;doc.layers[index].content = .group(group)
    XCTAssertNotNil(PSDArtboardInterchange.photoshopPersistenceIssue(doc));XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
    let worker=Task { try Task.checkCancellation();return try PSDCodec.writeRasterLayers(original) };worker.cancel()
    do { _ = try await worker.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(try fixture("owned-guide-rgb8.psd"),input)
  }
  func testPSBRetainsMaximumWidthAndPSDRejectsWithoutWritingAReplacement() throws {
    var doc=try CraftDocument(width:300000,height:1)
    try Command.artboard(.create(name:"Maximum width",bounds:.init(x:0,y:0,width:300000,height:1),background:.white,children:[doc.layers[0].id])).apply(to:&doc)
    let preview=try Renderer.composite(doc)
    XCTAssertEqual(preview.pixel(x:0,y:0),.white);XCTAssertEqual(preview.pixel(x:299999,y:0),.white)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc,format:.psd))
    let bytes=try PSDCodec.writeRasterLayers(doc,format:.psb,compositeCompression:.raw),read=try PSDCodec.read(bytes)
    XCTAssertEqual(read.width,300000);XCTAssertEqual(read.height,1);XCTAssertEqual(read.artboards.first?.artboard?.width,300000)
    XCTAssertTrue(try rawMerged(bytes).allSatisfy{$0==255})
  }
}
