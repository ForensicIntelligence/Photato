import Foundation
import XCTest
@testable import PhotoCraftCore

final class SelectionPagingIntegrationTests:XCTestCase {
  func testSelectionValueFootprintRemainsBoundedForNestedWorkerCommands() {
    XCTAssertLessThanOrEqual(MemoryLayout<SelectionMask>.stride,64,"Coverage storage must not expand nested document/command stack frames.")
  }
  func testLegacyByteCodingAndSmallDocumentVersionRemainUnchanged()throws {
    let mask=try SelectionMask(width:4,height:1,bytes:[0,64,128,255])
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary
    let data=try encoder.encode(mask),root=try PropertyListSerialization.propertyList(from:data,format:nil)as![String:Any]
    XCTAssertEqual(root["bytes"]as?Data,Data([0,64,128,255]));XCTAssertNil(root["pagedCoverage"])
    XCTAssertEqual(try PropertyListDecoder().decode(SelectionMask.self,from:data),mask)
    var d=try CraftDocument(width:4,height:1);d.setCoverageSelection(mask)
    let file=try NativeArchive.encode(d),header=try PropertyListSerialization.propertyList(from:file,format:nil)as![String:Any]
    XCTAssertEqual(header["version"]as?Int,10);XCTAssertEqual(try NativeArchive.decode(file),d)
  }
  func testMaximumPagedSelectionNative64AndScratchHistory()throws {
    let initial=try CraftDocument(width:300000,height:300000)
    var session=EditorSession(document:initial,historyByteLimit:0)
    try session.execute(.selectShape(.ellipse(.init(x:299900,y:299900,width:80,height:80)),.replace,true,0))
    let selected=session.document,mask=try XCTUnwrap(selected.selectionMask)
    XCTAssertTrue(mask.isPaged);XCTAssertEqual(selected.minimumArchiveVersion,64);XCTAssertLessThan(selected.estimatedBytes,1024*1024)
    XCTAssertThrowsError(try mask.bytes);XCTAssertEqual(mask.coverage(x:299940,y:299940),1)
    try session.execute(.invertSelection);let inverse=session.document
    XCTAssertEqual(inverse.selectionMask?.coverage(x:0,y:0),1)
    try session.undo();XCTAssertEqual(session.document,selected);try session.redo();XCTAssertEqual(session.document,inverse)
    XCTAssertGreaterThan(session.historySpilledStates,0)
    let data=try NativeArchive.encode(inverse)
    XCTAssertEqual(data.withUnsafeBytes {$0.loadUnaligned(fromByteOffset:8,as:UInt32.self)}.littleEndian,64)
    XCTAssertEqual(String(data:data.subdata(in:data.count-56..<data.count-48),encoding:.utf8),"PHTEND64")
    XCTAssertEqual(try NativeArchive.decodePaged(data,heapByteLimit:1024*1024),inverse)
    let dimensions=try NativeArchive.dimensions(data);XCTAssertEqual(dimensions.width,300000)
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".photato");defer{try? FileManager.default.removeItem(at:url)}
    let context=Data("owned recovery64".utf8);try NativeArchive.writeRecovery(inverse,context:context,to:url)
    let recovered=try NativeArchive.readRecoveryPaged(url,heapByteLimit:1024*1024)
    XCTAssertEqual(recovered.document,inverse);XCTAssertEqual(recovered.context,context)
    var bad=data;bad[8]=63;XCTAssertThrowsError(try NativeArchive.decodePaged(bad))
  }
  func testActual40MPSelectionPagesAndPersistsAllCoverageBytes()throws {
    let w=8000,h=5000,bytes=(0..<w*h).map {UInt8(($0%w+3*($0/w))%256)}
    let mask=try SelectionMask(width:w,height:h,bytes:bytes)
    XCTAssertTrue(mask.isPaged);XCTAssertThrowsError(try mask.bytes);XCTAssertEqual(try mask.denseBytes(maximumPixels:w*h),bytes)
    var d=try CraftDocument(width:w,height:h);d.setCoverageSelection(mask);try d.validate()
    XCTAssertLessThan(d.estimatedBytes,1024*1024);XCTAssertGreaterThan(d.mappedRasterBytes,36_000_000)
    let data=try NativeArchive.encodeChunked(d),restored=try NativeArchive.decodePaged(data,heapByteLimit:2*1024*1024)
    XCTAssertEqual(try restored.selectionMask?.denseBytes(maximumPixels:w*h),bytes)
    XCTAssertEqual(restored,d)
  }
  func testMaximumChannelSaveLoadInversionAndImplicitFeather()throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32)
    try Command.selectShape(.ellipse(.init(x:299900,y:299900,width:80,height:80)),.replace,true,0).apply(to:&d)
    let original=d.selectionMask
    try Command.channel(.saveSelection(nil,"Owned coverage",.replace)).apply(to:&d)
    let channel=try XCTUnwrap(d.alphaChannels?.first)
    try Command.selection(nil).apply(to:&d);try Command.channel(.load(.alpha(channel.id),.replace,false)).apply(to:&d)
    XCTAssertEqual(d.selectionMask,original)
    try Command.channel(.quickMask(true,.init())).apply(to:&d);try Command.channel(.quickMask(false,.init())).apply(to:&d)
    XCTAssertEqual(d.selectionMask,original)
    let plane=try PagedSelectionCoverage.make(.rectangle(.init(x:0,y:0,width:300000,height:300000)),width:300000,height:300000).feathered(radius:3)
    let reference=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:100,height:100)),width:100,height:100).feathered(radius:3)
    XCTAssertEqual(plane.byte(x:0,y:0),reference.byte(at:0));XCTAssertEqual(plane.byte(x:150000,y:150000),255)
    XCTAssertLessThan(plane.allocatedBytes,1024*1024)
    let half=try AlphaChannel(name:"Owned half",pixels:Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.5,0.5,0.5))).selection(invert:true)
    XCTAssertEqual(half.byte(at:0),128)
  }
}
