import CryptoKit
import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativePagedArchiveTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .f32)throws->CraftDocument {
    var d=try CraftDocument(width:64,height:64,depth:depth)
    var s=try Surface(width:64,height:64,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    if depth == .f32 {s.setLinearPixel(x:0,y:0,Pixel(-0.0,4,-0.25,0.5))}
    else{s.setPixel(x:0,y:0,Pixel(0.2,0.4,0.6,0.5))}
    d.layers[0].content = .raster(s);return d
  }
  /// Independent container assembly repeats one valid tile reference across a
  ///134MP grid. It exercises >2GiB decoded samples without allocating that raster.
  func expandedArchive(_ depth:PixelDepth)throws->Data {
    let original=try NativeArchive.encodeChunked(fixture(depth))
    func number(_ at:Int)->Int{original.withUnsafeBytes{Int(UInt64(littleEndian:$0.loadUnaligned(fromByteOffset:at,as:UInt64.self)))}}
    let offset=number(original.count-48),length=number(original.count-40)
    var table=try XCTUnwrap(PropertyListSerialization.propertyList(from:original.subdata(in:offset..<offset+length),format:nil)as?[String:Any])
    var d=try XCTUnwrap(table["document"]as?[String:Any]),layers=try XCTUnwrap(d["layers"]as?[[String:Any]])
    var content=try XCTUnwrap(layers[0]["content"]as?[String:Any]),raster=try XCTUnwrap(content["raster"]as?[String:Any]),s=try XCTUnwrap(raster["_0"]as?[String:Any])
    let tiles=try XCTUnwrap(s["tileData"]as?[String:String]),digest=try XCTUnwrap(tiles["0"])
    let width=16384,height=8192,count=(width/64)*(height/64)
    s["width"]=width;s["height"]=height;s["tileData"]=Dictionary(uniqueKeysWithValues:(0..<count).map{(String($0),digest)})
    raster["_0"]=s;content["raster"]=raster;layers[0]["content"]=content;d["layers"]=layers;d["width"]=width;d["height"]=height;table["document"]=d
    let manifest=try PropertyListSerialization.data(fromPropertyList:table,format:.binary,options:0)
    var output=original.prefix(offset);output.append(manifest);output.append(Data("PHTEND11".utf8))
    for n in [offset,manifest.count]{var v=UInt64(n).littleEndian;withUnsafeBytes(of:&v){output.append(contentsOf:$0)}}
    output.append(Data(SHA256.hash(data:manifest)));return Data(output)
  }
  func temporary()throws->URL {
    let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true)
    addTeardownBlock{try? FileManager.default.removeItem(at:u)};return u
  }
  func testLargeReferencedRastersUseMappedBudgetAndPreserveDepthBitsAndHistory()throws {
    for depth in PixelDepth.allCases {
      let bytes=try expandedArchive(depth)
      XCTAssertThrowsError(try NativeArchive.decode(bytes)) {XCTAssertTrue($0 is NativeArchiveMemoryLimit)}
      let d=try NativeArchive.decodePaged(bytes,heapByteLimit:8*1024*1024,scratchByteLimit:65536)
      guard case .raster(let s)=d.layers[0].content,case .raster(let reference)=try fixture(depth).layers[0].content else{return XCTFail("Missing raster")}
      XCTAssertEqual(d.width*d.height,134_217_728);XCTAssertEqual(s.mappedBytes,2_147_483_648)
      XCTAssertLessThan(d.estimatedBytes,8*1024*1024)
      for(x,y)in[(0,0),(64,64),(16320,8128)] {
        let a=depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y)
        let b=depth == .f32 ? reference.linearPixel(x:0,y:0):reference.pixel(x:0,y:0)
        XCTAssertTrue(a.hasSameBits(as:b))
      }
      var session=EditorSession(document:d);var brush=Brush();brush.size=8;brush.color = .white
      try session.execute(.stroke(d.layers[0].id,[.init(x:16370.5,y:8178.5)],brush))
      XCTAssertFalse(session.document == d,"The centered dab must modify the target");XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertTrue(session.document == d);try session.redo()
      XCTAssertEqual(s.mappedTileCount,32768)
    }
  }
  func testFileReadRecoveryContextAndMappingLifetimeSurviveSourceRemoval()throws {
    let folder=try temporary(),file=folder.appendingPathComponent("owned.photato"),d=try fixture(),context=Data("Owned recovery context".utf8)
    try NativeArchive.writeRecovery(d,context:context,to:file)
    let result=try NativeArchive.readRecoveryPaged(file,heapByteLimit:128,scratchByteLimit:65536)
    XCTAssertEqual(result.context,context);XCTAssertFalse(result.invalidContext);XCTAssertEqual(result.document,d)
    XCTAssertEqual(result.document.mappedRasterBytes,65536)
    try FileManager.default.removeItem(at:file)
    guard case .raster(let pixels)=result.document.layers[0].content,case .raster(let reference)=d.layers[0].content else{return XCTFail("Missing raster")}
    XCTAssertTrue(pixels.linearPixel(x:0,y:0).hasSameBits(as:reference.linearPixel(x:0,y:0)))
    let portable=try NativeArchive.encodeChunked(result.document);XCTAssertEqual(try NativeArchive.decode(portable),d)
    let legacy=try NativeArchive.encode(d);XCTAssertEqual(try NativeArchive.decodePaged(legacy),d)
    XCTAssertThrowsError(try NativeArchive.decodePaged(legacy,heapByteLimit:128))
  }
  func testHeapMetadataScratchAndCorruptionFailuresAreSeparateAndAtomic()throws {
    let original=try fixture(),data=try NativeArchive.encodeChunked(original)
    XCTAssertThrowsError(try NativeArchive.decodePaged(data,heapByteLimit:127)) {
      XCTAssertEqual($0 as? NativeArchiveMemoryLimit,.raster(requiredBytes:128,limitBytes:127))
    }
    XCTAssertThrowsError(try NativeArchive.decodePaged(data,scratchByteLimit:0)) {
      XCTAssertEqual($0 as? RasterScratchFailure,.capacity(requiredBytes:65536,limitBytes:0))
    }
    XCTAssertThrowsError(try NativeArchive.decodePaged(data,maximumMetadataBytes:0)) {XCTAssertTrue($0 is NativeArchiveMemoryLimit)}
    for (heap,scratch,metadata) in [(-1,65536,1024),(1024,-1,1024),(1024,65536,-1)] {
      XCTAssertThrowsError(try NativeArchive.decodePaged(data,heapByteLimit:heap,scratchByteLimit:scratch,maximumMetadataBytes:metadata))
    }
    var corrupt=data;corrupt[17] ^= 1
    XCTAssertThrowsError(try NativeArchive.decodePaged(corrupt))
    let folder=try temporary(),file=folder.appendingPathComponent("owned.photato");try corrupt.write(to:file)
    XCTAssertThrowsError(try NativeArchive.readPaged(file));XCTAssertEqual(try Data(contentsOf:file),corrupt)
    XCTAssertThrowsError(try NativeArchive.readPaged(folder))
    XCTAssertEqual(try NativeArchive.decodePaged(data),original)
  }
  func testCancelledPagedDecodeDoesNotPublish()async throws {
    let data=try expandedArchive(.f32)
    let task=Task.detached {while !Task.isCancelled {await Task.yield()};return try NativeArchive.decodePaged(data)}
    task.cancel()
    do{_ = try await task.value;XCTFail("Expected cancellation")}catch{XCTAssertTrue(error is CancellationError)}
  }
}

extension NativePagedArchiveTests {
  func testFileBeyond512MiBStreamsTilesWithIndependentMetadataAndDataLimits()throws {
    let folder=try temporary(),file=folder.appendingPathComponent("owned-native-over512.photato")
    let template=try NativeArchive.encodeChunked(fixture(.u8))
    func number(_ at:Int)->Int{template.withUnsafeBytes{Int(UInt64(littleEndian:$0.loadUnaligned(fromByteOffset:at,as:UInt64.self)))}}
    let start=number(template.count-48),length=number(template.count-40)
    var table=try XCTUnwrap(PropertyListSerialization.propertyList(from:template.subdata(in:start..<start+length),format:nil)as?[String:Any])
    var d=try XCTUnwrap(table["document"]as?[String:Any]),layers=try XCTUnwrap(d["layers"]as?[[String:Any]])
    var content=try XCTUnwrap(layers[0]["content"]as?[String:Any]),raster=try XCTUnwrap(content["raster"]as?[String:Any]),surface=try XCTUnwrap(raster["_0"]as?[String:Any])
    XCTAssertTrue(FileManager.default.createFile(atPath:file.path,contents:nil))
    let output=try FileHandle(forWritingTo:file);defer{try? output.close()}
    try output.write(contentsOf:template.prefix(16))
    let count=8193,bytesPerTile=65537
    var offset=16,records:[[String:Any]]=[],tiles:[String:String]=[:]
    for i in 0..<count {
      var bytes=Data(count:bytesPerTile)
      bytes.withUnsafeMutableBytes{$0.storeBytes(of:UInt32(i+1).littleEndian,toByteOffset:1,as:UInt32.self)}
      let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
      records.append(["digest":digest,"offset":UInt64(offset),"length":UInt64(bytesPerTile)])
      tiles[String(i)]=digest
      // Seek over zero samples: the owned source is logically >512MiB without
      // writing an unnecessary half-gigabyte zero buffer. Reads still hash/decode
      // every raw sample block and scratch capacity is charged for each unique tile.
      try output.seek(toOffset:UInt64(offset));try output.write(contentsOf:bytes.prefix(17));offset += bytesPerTile
    }
    d["width"]=8192;d["height"]=8192;surface["width"]=8192;surface["height"]=8192;surface["tileData"]=tiles
    raster["_0"]=surface;content["raster"]=raster;layers[0]["content"]=content;d["layers"]=layers;table["document"]=d;table["blobs"]=records
    let metadata=try PropertyListSerialization.data(fromPropertyList:table,format:.binary,options:0)
    try output.seek(toOffset:UInt64(offset));try output.write(contentsOf:metadata)
    var footer=Data("PHTEND11".utf8)
    for n in [offset,metadata.count]{var value=UInt64(n).littleEndian;withUnsafeBytes(of:&value){footer.append(contentsOf:$0)}}
    footer.append(Data(SHA256.hash(data:metadata)));try output.write(contentsOf:footer);try output.synchronize()
    let sourceBytes=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize!
    XCTAssertGreaterThan(sourceBytes,NativeArchive.maximumBytes)
    XCTAssertThrowsError(try NativeArchive.read(file),"Existing owned reader retains its512MiB policy")
    XCTAssertThrowsError(try NativeArchive.readPaged(file,maximumMetadataBytes:0))
    let started=Date(),document=try NativeArchive.readPaged(file,heapByteLimit:2*1024*1024,scratchByteLimit:count*65536)
    XCTAssertLessThan(document.estimatedBytes,2*1024*1024);XCTAssertEqual(document.mappedRasterBytes,count*65536)
    guard case .raster(let pixels)=document.layers[0].content else{return XCTFail("Missing raster")}
    for i in [0,4096,8192] {XCTAssertEqual(pixels.pixel(x:(i%128)*64,y:(i/128)*64).r.bitPattern,UInt32(i+1))}
    let saved=folder.appendingPathComponent("repacked.photato");try NativeArchive.write(document,to:saved)
    let reopened=try NativeArchive.readPaged(saved)
    XCTAssertTrue(reopened == document)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let out=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
      try FileManager.default.copyItem(at:file,to:out.appendingPathComponent(file.lastPathComponent))
      try JSONSerialization.data(withJSONObject:["sourceBytes":sourceBytes,"logicalPixels":8192*8192,"uniqueRawTiles":count,"mappedSampleBytes":document.mappedRasterBytes,"heapEstimateBytes":document.estimatedBytes,"seconds":Date().timeIntervalSince(started),"scope":"Owned independent sparse-file container with unique checked raw tile payloads; not a dense Photoshop pixel or RSS proof"],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("native-over512.json"))
    }
  }
}

extension NativePagedArchiveTests {
  func testActualHighEntropyNativeWriteExceeds512MiBAndReopensWithExactHDRBits()throws {
    let folder=try temporary(),file=folder.appendingPathComponent("owned-large-output.photato")
    var document=try CraftDocument(width:8192,height:8192,depth:.f32)
    var surface=try Surface(width:8192,height:8192,depth:.f32,colorEncoding:.linearRGB)
    let backing=try RasterTileStore(),count=9000
    var state:UInt32=0x53192a7b
    func next()->UInt32 {
      state ^= state << 13;state ^= state >> 17;state ^= state << 5
      return state
    }
    func finite()->Float {
      let raw=next(),bits=(raw & 0x7f800000) == 0x7f800000 ? raw ^ 0x00800000:raw
      return Float(bitPattern:bits)
    }
    var probes:[(Int,Int,Pixel)]=[]
    for i in 0..<count {
      var patch=try Surface(width:64,height:64,depth:.f32,colorEncoding:.linearRGB)
      for y in 0..<64 {for x in 0..<64 {
        let pixel=Pixel(finite(),finite(),finite(),Float(next() & 0xffffff)/Float(0xffffff))
        patch.setLinearPixel(x:x,y:y,pixel)
        if [0,4500,8999].contains(i) && ((x==0 && y==0)||(x==63 && y==63)) {
          probes.append(((i%128)*64+x,(i/128)*64+y,pixel))
        }
      }}
      try surface.importPatch(patch,atX:(i%128)*64,atY:(i/128)*64,backing:backing)
    }
    document.layers[0].content = .raster(surface)
    let start=Date(),writer=try AtomicFileWriter(to:file,maximumBytes:NativeArchive.maximumFileBytes)
    defer{writer.discard()}
    try NativeIndexedArchive.write(document,output:.init(file:writer,maximumBytes:NativeArchive.maximumFileBytes));try writer.commit()
    let header=try FileHandle(forReadingFrom:file);defer{try? header.close()}
    XCTAssertEqual(try header.read(upToCount:16),NativeIndexedArchive.header)
    XCTAssertLessThanOrEqual(writer.maximumWriteBytes,65536)
    let fileBytes=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize!
    XCTAssertGreaterThan(fileBytes,NativeArchive.maximumBytes,"Exercise actual native output above512MiB, not only file admission")
    XCTAssertThrowsError(try NativeArchive.read(file))
    let reopened=try NativeArchive.readPaged(file,heapByteLimit:2*1024*1024,scratchByteLimit:count*65536)
    XCTAssertLessThan(reopened.estimatedBytes,2*1024*1024)
    XCTAssertEqual(reopened.mappedRasterBytes,count*65536)
    guard case .raster(let result)=reopened.layers[0].content else{return XCTFail("Missing raster")}
    for(x,y,expected)in probes {XCTAssertTrue(result.linearPixel(x:x,y:y).hasSameBits(as:expected))}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let out=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
      try FileManager.default.copyItem(at:file,to:out.appendingPathComponent("native63-high-entropy.photato"))
      try JSONSerialization.data(withJSONObject:["formatVersion":63,"probes":probes.map{["x":$0.0,"y":$0.1,"bits":[$0.2.r.bitPattern,$0.2.g.bitPattern,$0.2.b.bitPattern,$0.2.a.bitPattern]]},"fileBytes":fileBytes,"logicalPixels":8192*8192,"storedPixels":count*4096,"mappedSampleBytes":reopened.mappedRasterBytes,"heapEstimateBytes":reopened.estimatedBytes,"exactHDRProbes":probes.count,"seconds":Date().timeIntervalSince(start),"scope":"Actual owned high-entropy finiteFloat32 RGB with unit alpha, native63 write/read across512MiB. Not Photoshop pixel, full4TiB or RSS qualification."],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("native-large-write.json"))
    }
  }
}
