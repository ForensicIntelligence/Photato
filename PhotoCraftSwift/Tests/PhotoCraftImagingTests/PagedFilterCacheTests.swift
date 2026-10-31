import CryptoKit
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PagedFilterCacheTests:XCTestCase {
  func folder()throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-filter-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
  }
  func testStreamedCacheMatchesSixPriorWireAndThreePagedMaskVectors()throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/filter-cache-streaming")
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("manifest.json")))as![[String:Any]]
    XCTAssertEqual(manifest.count,9)
    for row in manifest {
      let file=row["file"]as!String,bytes=try Data(contentsOf:folder.appendingPathComponent(file))
      XCTAssertEqual(SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),row["sha256"]as?String)
    }
    for(di,depth)in PixelDepth.allCases.enumerated(){for variant in 0..<2 {
      let d=try PagedFilterCacheFixture.document(depth,variant:variant),wire=try PSDSmartFilters.cacheData(d)
      XCTAssertEqual(wire,try Data(contentsOf:folder.appendingPathComponent("\(di)-\(variant).cache")))
      if variant==1 {
        let masks=try PSDSmartFilters.masks(in:d,readers:[PSDReader(data:wire)],paging:PSDRasterPaging.Context())
        let mask=try XCTUnwrap(masks[d.layers[0].id.uuidString]),entry=manifest.first{$0["file"]as?String=="\(di)-mask.rgba"}!
        XCTAssertEqual(try mask.pixels.rgbaData(depth:.f32,colorEncoding:.sRGB),try Data(contentsOf:folder.appendingPathComponent("\(di)-mask.rgba")))
        XCTAssertEqual(mask.transform.tx,entry["x"]as?Double);XCTAssertEqual(mask.transform.ty,entry["y"]as?Double)
      }
    }}
  }
  func testFileCacheSkipsLargePlanesAndPagesEveryNineMillionMaskSample()throws {
    let d=try PagedFilterCacheFixture.large(),directory=try folder();defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("owned-raw-cache.bin"),transaction=try AtomicFileWriter(to:url,maximumBytes:60_000_000)
    try PSDSmartFilters.writeCache(d,to:PSDOutput(file:transaction,maximumBytes:60_000_000),compression:.raw);try transaction.commit()
    let source=try PSDFileSource(url);XCTAssertGreaterThan(source.count,45_000_000)
    let masks=try PSDSmartFilters.masks(in:d,readers:[PSDReader(file:source)],paging:PSDRasterPaging.Context(heapByteLimit:128*1_024*1_024))
    let mask=try XCTUnwrap(masks[d.layers[0].id.uuidString]).pixels
    XCTAssertEqual(mask.width,6000);XCTAssertEqual(mask.height,1500);XCTAssertGreaterThan(mask.mappedBytes,144_000_000);XCTAssertLessThan(mask.allocatedBytes,8*1_024*1_024)
    XCTAssertTrue(try mask.allStoredSamplesSatisfy{$0.r==1 && $0.g==1 && $0.b==1 && $0.a==1})
    XCTAssertLessThanOrEqual(source.metrics.maximumReadBytes,65_536);XCTAssertLessThanOrEqual(source.metrics.peakCachedBytes,8*65_536)
    try source.validateUnchanged()
  }
  func testGlobalFileCacheExceedsDataBudgetWithoutMetadataMaterialization()throws {
    var d=try CraftDocument(width:8000,height:5000,depth:.f32)
    try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d)
    var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.highPass))]
    d.layers[0].smartFilters=stack // Source cache only; no mask plane to decode.
    let directory=try folder();defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("owned-large-cache.psb"),transaction=try AtomicFileWriter(to:url,maximumBytes:700_000_000)
    let output=PSDOutput(file:transaction,maximumBytes:700_000_000)
    // An authored1x1 PSB with an unreferenced40MP RGB32 filter source cache.
    // The cache alone exceeds the512MiB Data/retained-metadata budget.
    try output.text("8BPS");try output.n(2,2);try output.append(Data(count:6));try output.n(3,2)
    try output.n(1,4);try output.n(1,4);try output.n(32,2);try output.n(3,2)
    try output.section(Data());try output.section(Data())
    let section=try output.reserveLength(8);try output.n(0,8);try output.n(0,4)
    try output.text("8BIMFEid");let cache=try output.reserveLength(8),start=output.count
    try PSDSmartFilters.writeCache(d,to:output,compression:.raw)
    let bytes=output.count-start;XCTAssertGreaterThan(bytes,PSDCodec.maximumInputBytes)
    try output.finishLength(cache,width:8)
    for _ in 0..<((4-bytes%4)%4){try output.n(0,1)}
    try output.finishLength(section,width:8);try output.n(0,2)
    for _ in 0..<3 {try output.n(0x3f800000,4)}
    try transaction.commit()
    let source=try PSDFileSource(url),result=try PSDCodec.read(PSDReader(file:source),name:"Owned",paging:PSDRasterPaging.Context())
    XCTAssertNil(result.sourceMetadata?["psdGlobal_FEid"])
    XCTAssertEqual(result.width,1);XCTAssertEqual(result.height,1)
    XCTAssertLessThan(source.metrics.readCalls,128);XCTAssertLessThanOrEqual(source.metrics.maximumReadBytes,65_536)
    try source.validateUnchanged()
  }
  func testLargePSDPSBNativeFilesRetainEditableFilterSourceMaskAndPixels()throws {
    let d=try PagedFilterCacheFixture.large(),directory=try folder();defer{try? FileManager.default.removeItem(at:directory)}
    for format in PSDFileFormat.allCases {
      let url=directory.appendingPathComponent("owned.\(format == .psd ? "psd":"psb")")
      try PSDCodec.writeRasterLayers(d,to:url,compression:.zipPrediction,format:format,compositeCompression:.zipPrediction)
      let reopened=try PSDCodec.read(url)
      XCTAssertEqual(reopened.width,d.width);XCTAssertEqual(reopened.height,d.height)
      let layer=reopened.layers[0],source=try XCTUnwrap(layer.smartObject)
      XCTAssertEqual(source.width,6000);XCTAssertEqual(source.height,1500)
      XCTAssertEqual(layer.smartFilters?.filters[0].filter,d.layers[0].smartFilters?.filters[0].filter)
      let mask=try XCTUnwrap(layer.smartFilters?.mask);XCTAssertGreaterThan(mask.mappedBytes,0)
      XCTAssertTrue(try mask.allStoredSamplesSatisfy{$0.r==1 && $0.a==1})
      let rect=IntRect(x:2990,y:745,width:23,height:13)
      XCTAssertEqual(try Renderer.composite(d,region:rect).cropped(to:rect).rgbaData(depth:.f32),
        try Renderer.composite(reopened,region:rect).cropped(to:rect).rgbaData(depth:.f32))
      XCTAssertLessThan(reopened.estimatedBytes,128*1_024*1_024)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(reopened)),reopened)
    }
  }
  func testCacheErrorsCancellationAndAtomicOutputPreserveDestination()async throws {
    var d=try PagedFilterCacheFixture.document(.u8,variant:1)
    let bytes=try PSDSmartFilters.cacheData(d)
    for data in [Data(bytes.dropLast(5)),Data([0,0,0,9])+bytes.dropFirst(4)] {
      XCTAssertThrowsError(try PSDSmartFilters.masks(in:d,readers:[PSDReader(data:data)],paging:PSDRasterPaging.Context()))
    }
    let directory=try folder();defer{try? FileManager.default.removeItem(at:directory)}
    let target=directory.appendingPathComponent("existing.bin"),original=Data("Owned destination".utf8);try original.write(to:target)
    do {let writer=try AtomicFileWriter(to:target,maximumBytes:500);XCTAssertThrowsError(try PSDSmartFilters.writeCache(d,to:PSDOutput(file:writer,maximumBytes:500)))}
    XCTAssertEqual(try Data(contentsOf:target),original)
    let cancelledDocument=d
    let task=Task {withUnsafeCurrentTask{$0?.cancel()};XCTAssertThrowsError(try PSDSmartFilters.cacheData(cancelledDocument))};try await task.value
    d.sourceMetadata=["psdGlobal_FEid":bytes];XCTAssertEqual(try PSDSmartFilters.masks(in:d).count,1)
  }
}
