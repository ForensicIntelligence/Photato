import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDPagedFileTests:XCTestCase {
  struct Manifest:Decodable {
    struct Vector:Decodable {let file:String;let depth:Int;let layered:Bool;let sha256:String}
    let cases:[Vector]
  }
  private func folder() throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    addTeardownBlock {try? FileManager.default.removeItem(at:url)};return url
  }
  private func samePixels(_ a:CraftDocument,_ b:CraftDocument) throws {
    XCTAssertEqual(a.width,b.width);XCTAssertEqual(a.height,b.height);XCTAssertEqual(a.depth,b.depth)
    XCTAssertEqual(a.layers.count,b.layers.count);XCTAssertEqual(a.sourceMetadata,b.sourceMetadata)
    for (x,y) in zip(a.layers,b.layers) {
      guard case .raster(let p)=x.content,case .raster(let q)=y.content else {return XCTFail("Missing raster")}
      let encoding:SurfaceColorEncoding=a.depth == .f32 ? .linearRGB:.sRGB
      XCTAssertEqual(try p.rgbaData(depth:.f32,colorEncoding:encoding),try q.rgbaData(depth:.f32,colorEncoding:encoding))
      XCTAssertEqual(try x.mask?.rgbaData(depth:.f32),try y.mask?.rgbaData(depth:.f32))
      XCTAssertEqual(x.maskProperties,y.maskProperties)
    }
  }
  func testIndependentAllDepthCompressionFlatAlphaLayersAndMasksRetainEveryBit() throws {
    let directory=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("psb-paged")
    let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:directory.appendingPathComponent("provenance.json")))
    XCTAssertEqual(manifest.cases.count,36)
    let previous=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("prior285.json")))as?[[String:Any]])
    for vector in manifest.cases {
      let url=directory.appendingPathComponent(vector.file),data=try Data(contentsOf:url)
      XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),vector.sha256)
      let owned=try PSDCodec.read(data),paged=try PSDCodec.readPaged(data)
      try samePixels(paged,owned);try samePixels(PSDCodec.read(url),owned)
      var hashes:[String]=[]
      for layer in paged.layers {
        if case .raster(let pixels)=layer.content {hashes.append(SHA256.hash(data:try pixels.rgbaData(depth:.f32,colorEncoding:paged.depth == .f32 ? .linearRGB:.sRGB)).map{String(format:"%02x",$0)}.joined())}
        if let mask=layer.mask {hashes.append(SHA256.hash(data:try mask.rgbaData(depth:.f32)).map{String(format:"%02x",$0)}.joined())}
      }
      XCTAssertEqual(hashes,try XCTUnwrap(previous.first{$0["file"]as?String == vector.file}?["pixelHashes"]as?[String]))
      try samePixels(RasterIO.read(url),owned)
      XCTAssertGreaterThan(paged.mappedRasterBytes,0)
      XCTAssertLessThan(paged.estimatedBytes,owned.estimatedBytes)
      XCTAssertThrowsError(try PSDCodec.readPaged(data,heapByteLimit:0))
      XCTAssertThrowsError(try PSDCodec.readPaged(data,scratchByteLimit:0))
      if vector.layered {
        var session=EditorSession(document:paged);var brush=Brush();brush.size=5;brush.color = .white
        try session.execute(.stroke(session.document.layers[0].id,[.init(x:64.5,y:32.5)],brush))
        XCTAssertNotEqual(session.document,paged);try session.undo();XCTAssertEqual(session.document,paged)
        let native=try NativeArchive.encodeChunked(paged,minimumVersion:63);XCTAssertEqual(try NativeArchive.decodePaged(native),paged)
      }
    }
  }
  func testBoundedCompositeRowsMatchWholeRendererAcrossBandsMasksGroupsAndDepths() throws {
    for depth in PixelDepth.allCases {
      var document=try CraftDocument(width:2113,height:67,depth:depth)
      var pixels=try Surface(width:2113,height:67,depth:depth,fill:Pixel(0.25,0.5,0.75,0.5),colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      if depth == .f32 {pixels.setLinearPixel(x:2048,y:64,Pixel(2,-0.25,-0.0,0.5))}
      else {pixels.setPixel(x:2048,y:64,Pixel(1,0,0,0.5))}
      var base=Layer(name:"Owned base",content:.raster(pixels));base.mask=try Surface(width:2113,height:67,depth:depth,fill:Pixel(0.75,0.75,0.75))
      let group=Layer(name:"Owned group",content:.group(GroupContent(passThrough:false)))
      var overlay=Layer(name:"Owned overlay",content:.fill(Pixel(0.75,0.25,0.5,0.25)));overlay.parentID=group.id
      document.layers=[base,overlay,group];document.activeLayerID=base.id
      let complete=try Renderer.composite(document),rows=PSDCompositeRows(document),bits=depth == .u8 ? 8:depth == .u16 ? 16:32
      for channel in 0..<4 {for y in 0..<document.height {
        var expected:[UInt8]=[]
        for x in 0..<document.width {
          let p=bits == 32 ? PSDMergedSample.encodeLinear(complete.linearPixel(x:x,y:y)):PSDMergedSample.encode(complete.pixel(x:x,y:y),depth:bits)
          try PSDChannelCodec.append([p.r,p.g,p.b,p.a][channel],depth:bits,to:&expected)
        }
        XCTAssertEqual(try rows.row(y,channel:channel,depth:bits),expected,"Depth\(bits), row\(y), channel\(channel)")
      }}
      XCTAssertThrowsError(try rows.row(document.height,channel:0,depth:bits))
    }
  }
  func testSparseMaximumRawPlaneAddressingAndMetadataAdmissionWithoutMaterialization() throws {
    let directory=try folder()
    do {
      let planes=try PSDPlaneScratch(width:300000,height:300000,depth:32,components:4,directory:directory)
      XCTAssertEqual(planes.byteCount,1_440_000_000_000)
      var row=[UInt8](repeating:0,count:1_200_000);row.replaceSubrange(1_199_996..<1_200_000,with:[0x40,0x80,0,0])
      try planes.write(row,row:299999,component:3)
      XCTAssertEqual(try planes.sample(x:299999,y:299999,component:3).bitPattern,Float(4).bitPattern)
      XCTAssertThrowsError(try planes.write(row,row:300000,component:0))
      XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
    let file=directory.appendingPathComponent("owned-sparse-metadata")
    FileManager.default.createFile(atPath:file.path,contents:nil)
    let handle=try FileHandle(forWritingTo:file);try handle.truncate(atOffset:4_294_967_312);try handle.close()
    let source=try PSDFileSource(file),reader=PSDReader(file:source)
    XCTAssertThrowsError(try reader.data)
    XCTAssertEqual(source.metrics.readCalls,0,"Metadata must reject before attempting huge materialization.")
    var view=reader;XCTAssertThrowsError(try view.retainedBytes(PSDCodec.maximumMetadataBytes+1))
    let budget=PSDMetadataBudget();try budget.reserve(PSDCodec.maximumMetadataBytes);XCTAssertThrowsError(try budget.reserve(1))
    XCTAssertThrowsError(try PSDPlaneScratch(width:1,height:1,depth:32,components:2))
  }
  func testActual40MPRGB16FileExceeds512MiBAndReopensPagedWithAtomicFailure() throws {
    let directory=try folder(),file=directory.appendingPathComponent("owned-40mp.psb")
    var model=try CraftDocument(width:8000,height:5000,depth:.u16)
    let surface=try Surface(width:8000,height:5000,depth:.u16,fill:Pixel(0.25,0.5,0.75,1))
    model.layers[0].content = .raster(surface)
    try PSDCodec.writeRasterLayers(model,to:file,compression:.raw,format:.psb,compositeCompression:.raw)
    let count=try XCTUnwrap(file.resourceValues(forKeys:[.fileSizeKey]).fileSize)
    XCTAssertGreaterThan(count,PSDCodec.maximumInputBytes)
    let reopened=try PSDCodec.read(file);XCTAssertEqual(reopened.width,8000);XCTAssertEqual(reopened.height,5000)
    XCTAssertGreaterThanOrEqual(reopened.mappedRasterBytes,640_000_000);XCTAssertLessThan(reopened.estimatedBytes,16*1024*1024)
    guard case .raster(let pixels)=reopened.layers[0].content else {return XCTFail("Raster")}
    for (x,y) in [(0,0),(2048,64),(7999,4999)] {XCTAssertTrue(pixels.pixel(x:x,y:y).hasSameBits(as:surface.pixel(x:x,y:y)))}
    XCTAssertThrowsError(try PSDCodec.read(Data(contentsOf:file,options:.mappedIfSafe)))
    let before=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize
    do {
      let transaction=try AtomicFileWriter(to:file,maximumBytes:100)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(model,compression:.raw,format:.psb,output:PSDOutput(file:transaction)))
    }
    XCTAssertEqual(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,before)
    if ProcessInfo.processInfo.environment["PHOTATO_CAPTURE_LARGE_PHOTOSHOP_FILE"] == "1",let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let destination=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
      try FileManager.default.copyItem(at:file,to:destination.appendingPathComponent("owned-40mp-rgb16.psb"))
    }
  }
  func testCancelledPagingCannotPublishPartlyDecodedPixels() async throws {
    let result=try await Task.detached { () throws -> Bool in
      let context=try PSDRasterPaging.Context();var calls=0
      do {
        _ = try PSDRasterPaging.layer(width:2049,height:65,depth:.u8,components:3,context:context) { y in
          calls += 1;if y == 2 {withUnsafeCurrentTask {$0?.cancel()}}
          return Array(repeating:Array(repeating:UInt8(128),count:2049),count:3)
        }
        return false
      } catch is CancellationError {return calls == 3} catch {return false}
    }.value
    XCTAssertTrue(result)
  }
}
