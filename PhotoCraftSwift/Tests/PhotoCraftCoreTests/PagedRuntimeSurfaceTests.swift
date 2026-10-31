import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedRuntimeSurfaceTests:XCTestCase {
  private func palette(_ depth:PixelDepth) throws -> [Surface] {
    let store=try RasterTileStore();var result=[Surface]()
    for i in 0..<4 {
      var patch=try Surface(width:64,height:64,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      let color=Pixel(Float(i+1)/4,Float(i)/4,-0.0,1)
      for y in 0..<64 {for x in 0..<64 {
        if depth == .f32 {patch.setLinearPixel(x:x,y:y,color)}else{patch.setPixel(x:x,y:y,color)}
      }}
      if depth == .f32 {patch.setLinearPixel(x:0,y:0,Pixel(-0.0,2.5,-0.25,0.5))}
      var mapped=try Surface(width:64,height:64,depth:depth,colorEncoding:patch.colorEncoding)
      try mapped.importPatch(patch,atX:0,atY:0,backing:store);result.append(mapped)
    }
    return result
  }
  private func grid(_ depth:PixelDepth,width:Int=4099,height:Int=2113) throws -> Surface {
    let samples=try palette(depth),builder=try Surface.PagedBuilder(width:width,height:height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in stride(from:0,to:height,by:64) {for x in stride(from:0,to:width,by:64) {
      let patch=samples[(x/64+y/64)%4]
      try builder.append(patch.cropped(to:.init(x:0,y:0,width:min(64,width-x),height:min(64,height-y))),atX:x,atY:y)
    }}
    return try builder.finish()
  }
  private func expected(_ x:Int,_ y:Int,_ depth:PixelDepth) -> Pixel {
    if depth == .f32 && x%64==0 && y%64==0 {return Pixel(-0.0,2.5,-0.25,0.5)}
    let i=(x/64+y/64)%4;return Pixel(Float(i+1)/4,Float(i)/4,-0.0,1).quantized(depth)
  }
  private func temporary() throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-paged-surface-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testMappedPatchImportRegionsHiddenBitsAndAllDepths() throws {
    for depth in PixelDepth.allCases {
      let original=try grid(depth),region=IntRect(x:127,y:61,width:100,height:100),crop=try original.cropped(to:region)
      XCTAssertEqual(original.tileCount,2210);XCTAssertEqual(original.mappedTileCount,2210)
      XCTAssertEqual(original.mappedTileIndexBytes,2210*16);XCTAssertLessThan(original.allocatedBytes,8192)
      for y in 0..<100 {for x in 0..<100 {
        let value=depth == .f32 ? crop.linearPixel(x:x,y:y):crop.pixel(x:x,y:y)
        XCTAssertTrue(value.hasSameBits(as:expected(x+region.x,y+region.y,depth)))
      }}
      for (x,y) in [(0,0),(4098,2112),(4096,2112),(63,63),(64,64)] {
        let p=depth == .f32 ? original.linearPixel(x:x,y:y):original.pixel(x:x,y:y)
        XCTAssertTrue(p.hasSameBits(as:expected(x,y,depth)))
      }
      try original.validated();XCTAssertEqual(original.mappedTileCount,original.tileCount)
      let preview=try original.reducedPreview(in:region,width:20,height:20)
      let oracle=try crop.reducedPreview(in:.init(x:0,y:0,width:100,height:100),width:20,height:20)
      XCTAssertEqual(preview,oracle)
      let area=try original.sparseAreaSample(left:127,top:61,right:227,bottom:161,maximumSamples:10000)
      XCTAssertEqual(area.samples,10000)
      let whole=try crop.sparseAreaSample(left:0,top:0,right:100,bottom:100,maximumSamples:10000)
      XCTAssertTrue(area.pixel.hasSameBits(as:whole.pixel))
    }
  }
  func testStrokeHistoryChangedBoundsAutomaticIndexedSaveAndReopen() throws {
    let pixels=try grid(.f32);var document=try CraftDocument(width:pixels.width,height:pixels.height,depth:.f32,name:"Owned paged runtime workflow")
    document.layers[0].content = .raster(pixels);var session=EditorSession(document:document)
    var brush=Brush();brush.size=12;brush.color = .black
    try session.execute(.stroke(document.layers[0].id,[.init(x:3000.5,y:1800.5),.init(x:3040.5,y:1830.5)],brush))
    guard case .raster(let edited)=session.document.layers[0].content else {return XCTFail("Raster")}
    XCTAssertEqual(edited.mappedTileIndexBytes,pixels.mappedTileIndexBytes)
    XCTAssertLessThan(edited.mappedTileCount,pixels.mappedTileCount);XCTAssertLessThan(edited.allocatedBytes-pixels.allocatedBytes,16*65536)
    let changed=try XCTUnwrap(edited.changedTileBounds(comparedTo:pixels))
    XCTAssertTrue(changed.contains(3000,1800));XCTAssertLessThanOrEqual(changed.width,128);XCTAssertLessThanOrEqual(changed.height,128)
    XCTAssertTrue(pixels.linearPixel(x:3000,y:1800).hasSameBits(as:expected(3000,1800,.f32)))
    let after=session.document;try session.undo();XCTAssertEqual(session.document,document);try session.redo();XCTAssertEqual(session.document,after)
    let folder=try temporary(),url=folder.appendingPathComponent("owned.photato")
    try NativeArchive.write(after,to:url);let bytes=try Data(contentsOf:url)
    XCTAssertTrue(bytes.starts(with:NativeIndexedArchive.header));let reopened=try NativeArchive.readPaged(url)
    XCTAssertEqual(reopened,after);XCTAssertGreaterThan(reopened.mappedRasterIndexBytes,0)
    let prior=bytes
    XCTAssertThrowsError(try NativeArchive.write(after,to:url) {u,n in var operations=AtomicFileWriter.Operations();operations.write={_,_,_,_ in -1};return try AtomicFileWriter(to:u,maximumBytes:n,operations:operations)})
    XCTAssertEqual(try Data(contentsOf:url),prior);XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path),["owned.photato"])
  }
  func testMappedNative63AndLegacyDecodeBudgetsAreBoundedByRuntimeMetadata() throws {
    let pixels=try grid(.u16,width:2048,height:2048);var document=try CraftDocument(width:2048,height:2048,depth:.u16)
    document.layers[0].content = .raster(pixels)
    for version in [11,63] {
      let bytes=try NativeArchive.encodeChunked(document,minimumVersion:version)
      let decoded=try NativeArchive.decodePaged(bytes,heapByteLimit:512*1024)
      XCTAssertEqual(decoded,document);XCTAssertEqual(decoded.mappedRasterIndexBytes,1024*16)
      XCTAssertLessThan(decoded.estimatedBytes,16384)
      XCTAssertThrowsError(try NativeArchive.decodePaged(bytes,heapByteLimit:1024))
      XCTAssertThrowsError(try NativeArchive.decode(bytes,rasterByteLimit:512*1024)) {error in
        // Explicit small owned budget separately proves there is no silent mapped fallback.
        if !(error is NativeArchiveMemoryLimit) {XCTFail("Unexpected \(error)")}
      }
    }
  }
  func testSparseMaximumCanvasSmallPatchAndBuilderLifecycle() throws {
    let palette=try palette(.f32),builder=try Surface.PagedBuilder(width:300000,height:300000,depth:.f32,colorEncoding:.linearRGB)
    try builder.append(palette[2],atX:299904,atY:299904);let surface=try builder.finish()
    XCTAssertEqual(surface.tileCount,1);XCTAssertEqual(surface.mappedTileIndexBytes,0)
    XCTAssertTrue(surface.linearPixel(x:299904,y:299904).hasSameBits(as:Pixel(-0.0,2.5,-0.25,0.5)))
    XCTAssertEqual(surface.linearPixel(x:299999,y:299999),.clear)
    XCTAssertThrowsError(try builder.finish());XCTAssertThrowsError(try builder.append(palette[0],atX:0,atY:0))
    let order=try Surface.PagedBuilder(width:128,height:64,depth:.f32,colorEncoding:.linearRGB)
    try order.append(palette[0],atX:64,atY:0);XCTAssertThrowsError(try order.append(palette[1],atX:0,atY:0));XCTAssertThrowsError(try order.finish())
    let empty=try Surface.PagedBuilder(width:128,height:64);let none=try empty.finish();XCTAssertEqual(none.tileCount,0);XCTAssertEqual(none.allocatedBytes,0)
  }
  func testMappedPointwiseOperationsStreamTheirOutputIndex() throws {
    let input=try grid(.f32,width:2048,height:2048)
    let mapped=try input.mappedStoredSamples {p in Pixel(p.r*0.5,p.g+0.125,p.b,p.a)}
    XCTAssertGreaterThan(mapped.mappedTileIndexBytes,0);XCTAssertEqual(mapped.mappedTileCount,mapped.tileCount)
    let combined=try input.combiningStoredSamples(with:mapped) {a,b in Pixel(a.r+b.r,a.g-b.g,a.b,a.a)}
    XCTAssertGreaterThan(combined.mappedTileIndexBytes,0)
    for (x,y) in [(0,0),(100,200),(2047,2047)] {
      let a=input.linearPixel(x:x,y:y),b=mapped.linearPixel(x:x,y:y),c=combined.linearPixel(x:x,y:y)
      XCTAssertTrue(b.hasSameBits(as:Pixel(a.r*0.5,a.g+0.125,a.b,a.a)))
      XCTAssertTrue(c.hasSameBits(as:Pixel(a.r+b.r,a.g-b.g,a.b,a.a)))
    }
  }
  func testReal65537UniqueTileFilePaintingHistoryAndReopen() throws {
    let count=65537,width=16384,height=16448,start=Date()
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:.f32,colorEncoding:.linearRGB)
    for key in 0..<count {
      var patch=try Surface(width:64,height:64,depth:.f32,colorEncoding:.linearRGB)
      patch.setLinearPixel(x:0,y:0,Pixel(Float(key),Float(key%17)/16,-0.0,0.5))
      try builder.append(patch,atX:key%256*64,atY:key/256*64)
    }
    let surface=try builder.finish();XCTAssertEqual(surface.tileCount,count)
    XCTAssertEqual(surface.mappedBytes,4_295_032_832);XCTAssertEqual(surface.mappedTileIndexBytes,count*16)
    XCTAssertLessThan(surface.allocatedBytes,32768)
    var document=try CraftDocument(width:width,height:height,depth:.f32,name:"Owned65537 unique mapped tiles")
    document.layers[0].content = .raster(surface)
    let url=try temporary().appendingPathComponent("owned65537.photato")
    try NativeArchive.write(document,to:url)
    let bytes=try Data(contentsOf:url);XCTAssertTrue(bytes.starts(with:NativeIndexedArchive.header))
    let reopened=try NativeArchive.readPaged(url,heapByteLimit:2*1024*1024)
    guard case .raster(let pixels)=reopened.layers[0].content else {return XCTFail("Raster")}
    XCTAssertEqual(pixels.tileCount,count);XCTAssertEqual(pixels.mappedTileCount,count)
    XCTAssertEqual(reopened.mappedRasterIndexBytes,count*16);XCTAssertLessThan(reopened.estimatedBytes,65536)
    for key in [0,1,1023,1024,32768,65535,65536] {
      XCTAssertTrue(pixels.linearPixel(x:key%256*64,y:key/256*64).hasSameBits(as:Pixel(Float(key),Float(key%17)/16,-0.0,0.5)))
      XCTAssertEqual(pixels.linearPixel(x:key%256*64+1,y:key/256*64),.clear)
    }
    var session=EditorSession(document:reopened),brush=Brush();brush.size=8;brush.color = .white
    try session.execute(.stroke(reopened.layers[0].id,[.init(x:12.5,y:16400.5)],brush))
    XCTAssertNotEqual(session.document,reopened);try session.undo();XCTAssertEqual(session.document,reopened);try session.redo()
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let output=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
      try bytes.write(to:output.appendingPathComponent("owned65537-unique.photato"))
      try JSONSerialization.data(withJSONObject:["tileCount":count,"actualReferencedMappedSamples":surface.mappedBytes,"runtimeIndexBytes":surface.mappedTileIndexBytes,"reopenedHeapEstimate":reopened.estimatedBytes,"nativeFileBytes":bytes.count,"seconds":Date().timeIntervalSince(start),"scope":"65537 genuinely unique allocated raw tiles; highly compressible procedural contents. Not unique dense90GP/4TiB/RSS/Photoshop proof."],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("owned65537-unique.json"))
    }
  }

}
