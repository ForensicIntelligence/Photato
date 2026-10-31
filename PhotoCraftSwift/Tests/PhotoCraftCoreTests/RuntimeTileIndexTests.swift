import Foundation
import XCTest
@testable import PhotoCraftCore

final class RuntimeTileIndexTests: XCTestCase {
  private func capture(_ name:String,_ value:[String:Any]) throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return}
    let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent(name))
  }
  private func temporary() throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-runtime-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
  }
  func testMaximumIndexCOWRangesHistoryAndBufferStability() throws {
    let store=try RasterTileStore();var samples=[RasterTile]()
    for i in 0..<1100 {samples.append(try store.append(RasterTile(repeating:Pixel(Float(i),Float(i%17)/16,-0.0,0.5),count:4096)))}
    let start=Date(),builder=try RuntimeTileIndex.Builder(),count=RuntimeTileIndex.maximumEntries
    for key in 0..<count {try builder.append(key:key,tile:samples[key%1100])}
    let index=try builder.finish();var map=RasterTileMap(base:index);let original=map
    XCTAssertEqual(count,21_977_344);XCTAssertEqual(index.mappedBytes,351_637_504)
    XCTAssertEqual(map.count,count);XCTAssertLessThan(map.residentBytes,2048);XCTAssertEqual(index.lowerBound(count),count)
    for key in [0,1,1023,1024,16_777_216,count/2,count-1] {
      XCTAssertTrue(try XCTUnwrap(map[key]?[0]).hasSameBits(as:Pixel(Float(key%1100),Float(key%1100%17)/16,-0.0,0.5)))
    }
    map[count-1,default:samples[0]][0] = .white
    let identity=map[count-1]!.identity,path=map.editPathIDs(for:count-1)
    for i in 0..<100_000 {map[count-1,default:samples[0]][1] = Pixel(Float(i),0,0)}
    XCTAssertEqual(map[count-1]!.identity,identity);XCTAssertEqual(map.editPathIDs(for:count-1),path)
    XCTAssertEqual(path.count,4);XCTAssertEqual(Array(map.candidateKeys(comparedTo:original)),[count-1])
    XCTAssertEqual(original[count-1]?[0].r,Float((count-1)%1100));XCTAssertEqual(map.mappedTileCount,count-1)
    map[0]=nil;XCTAssertEqual(map.count,count-1);XCTAssertEqual(Array(map.entries(in:0..<4).map(\.0)),[1,2,3])
    map[0]=samples[0];XCTAssertEqual(map.count,count)
    var seen=Set<UInt>();let baseline=original.accountHistory(&seen),delta=map.accountHistory(&seen)
    XCTAssertLessThan(baseline,2048);XCTAssertLessThan(delta,131072);XCTAssertLessThanOrEqual(builder.maximumPhysicalWrite,65536)
    try capture("runtime-maximum-index.json",["records":count,"mappedIndexBytes":index.mappedBytes,"referencedSampleBytes":count*65536,"actualSampleScratchBytes":store.storedBytes,"heapEstimateBytes":map.residentBytes,"historyBaselineEstimate":baseline,"historyDeltaEstimate":delta,"cowPathNodes":path.count,"maximumPhysicalWrite":builder.maximumPhysicalWrite,"seconds":Date().timeIntervalSince(start)])
    if ProcessInfo.processInfo.environment["PHOTATO_CAPTURE_MAXIMUM_RUNTIME_INDEX"]=="1",let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url=URL(fileURLWithPath:folder).appendingPathComponent("runtime-maximum-index.records")
      XCTAssertTrue(FileManager.default.createFile(atPath:url.path,contents:nil));let file=try FileHandle(forWritingTo:url);defer{try? file.close()}
      try index.withUnsafeRecordBytes { bytes in
        for offset in stride(from:0,to:bytes.count,by:65536) {try file.write(contentsOf:Data(bytes:bytes.baseAddress!.advanced(by:offset),count:min(65536,bytes.count-offset)))}
      }
    }
  }
  func testRandomEditsMatchIndependentDictionaryOracleAndRetainedSnapshots() throws {
    let store=try RasterTileStore();var palette=[RasterTile]()
    for i in 0..<8 {palette.append(try store.append(RasterTile(repeating:Pixel(Float(i+1),0.25,-0.0,1),count:4096)))}
    var map=RasterTileMap(persistent:true),expected=[Int:UInt32](),mapped=[Int:Bool](),seed:UInt64=284
    var retained=[(RasterTileMap,[Int:UInt32])]();var checksum:UInt64=0
    for step in 0..<10_000 {
      seed=seed&*6364136223846793005&+1442695040888963407;let key=Int((seed>>16)%UInt64(RuntimeTileIndex.maximumEntries)),action=Int(seed%10),which=Int(seed>>32)%8
      if action<4 {map[key]=palette[which];expected[key]=Float(which+1).bitPattern;mapped[key]=true}
      else if action<6 {map[key]=nil;expected[key]=nil;mapped[key]=nil}
      else {let value=Float(step)+0.5;map[key,default:RasterTile(repeating:.clear,count:4096)][0] = Pixel(value,0.5,-0.0,1);expected[key]=value.bitPattern;mapped[key]=false}
      XCTAssertEqual(map.count,expected.count);XCTAssertEqual(map.mappedTileCount,mapped.values.filter{$0}.count)
      XCTAssertTrue(map.isStructurallyValid(maximumKey:RuntimeTileIndex.maximumEntries))
      if step%511==0 {
        XCTAssertEqual(Array(map.keys),expected.keys.sorted())
        let low=max(0,key-100000),high=min(RuntimeTileIndex.maximumEntries,key+100000)
        XCTAssertEqual(Array(map.entries(in:low..<high).map(\.0)),expected.keys.filter{$0>=low && $0<high}.sorted())
        retained.append((map,expected));if retained.count>8 {retained.removeFirst()}
      }
      checksum &+= UInt64(map[key]?[0].r.bitPattern ?? 0)
    }
    for (snapshot,oracle) in retained {
      XCTAssertEqual(snapshot.count,oracle.count)
      for (key,bits) in oracle {XCTAssertEqual(snapshot[key]?[0].r.bitPattern,bits)}
    }
    let old=map,ids=map.editPathIDs(for:12345)
    map[12345,default:palette[0]][0] = .black
    XCTAssertLessThanOrEqual(map.editPathIDs(for:12345).count,4)
    XCTAssertTrue(Set(map.editPathIDs(for:12345)).isDisjoint(with:Set(ids)))
    XCTAssertTrue(Array(map.candidateKeys(comparedTo:old)).contains(12345))
    XCTAssertLessThanOrEqual(Array(map.candidateKeys(comparedTo:old)).count,256)
    try capture("runtime-tree-oracle.json",["edits":10000,"retainedSnapshots":retained.count,"finalTiles":map.count,"checksum":String(checksum)])
  }
  func testDirectWorkingSetTransitionsToPersistentTreeWithoutChangingSamples() throws {
    let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096))
    var map=RasterTileMap()
    for key in 0...RasterTileMap.directLimit {map[key]=tile}
    let before=map
    XCTAssertEqual(map.count,RasterTileMap.directLimit+1);XCTAssertEqual(map.editPathIDs(for:0).count,4)
    map[0,default:tile][0] = .black
    XCTAssertEqual(before[0]?[0],.white);XCTAssertEqual(map[0]?[0],.black)
    XCTAssertLessThanOrEqual(Array(map.candidateKeys(comparedTo:before)).count,256)
    XCTAssertEqual(Array(map.entries(in:10..<20).map(\.0)),Array(10..<20))
  }
  func testImmutableIndexLifetimeAndBuilderFailureLifecycle() throws {
    func makeIndex() throws -> RuntimeTileIndex {
      let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:Pixel(0.25,0.5,0.75),count:4096)),builder=try RuntimeTileIndex.Builder()
      try builder.append(key:12,tile:tile);return try builder.finish()
    }
    var index:RuntimeTileIndex?=try makeIndex();let tile=try XCTUnwrap(index?.tile(for:12));index=nil
    XCTAssertEqual(tile[4095],Pixel(0.25,0.5,0.75))
    XCTAssertThrowsError(try RuntimeTileIndex.Builder(maximumBytes:-1))
    XCTAssertThrowsError(try RuntimeTileIndex.Builder(directory:URL(string:"https://invalid.example/")!))
    for mode in 0..<4 {
      let builder=try RuntimeTileIndex.Builder(maximumBytes:mode==0 ? 0:32)
      if mode==0 {XCTAssertThrowsError(try builder.append(key:0,tile:tile))}
      if mode==1 {XCTAssertThrowsError(try builder.append(key:0,tile:RasterTile(repeating:.white,count:4096)))}
      if mode==2 {try builder.append(key:1,tile:tile);XCTAssertThrowsError(try builder.append(key:1,tile:tile))}
      if mode==3 {XCTAssertThrowsError(try builder.append(key:RuntimeTileIndex.maximumEntries,tile:tile))}
      XCTAssertThrowsError(try builder.finish());XCTAssertThrowsError(try builder.append(key:2,tile:tile))
    }
    let empty=try RuntimeTileIndex.Builder(),finished=try empty.finish();XCTAssertEqual(finished.count,0)
    XCTAssertThrowsError(try empty.finish());XCTAssertThrowsError(try empty.append(key:0,tile:tile))
    let reserve=try RuntimeTileIndex.Builder(reserveSegment:{_ in throw CraftError.invalid("Injected admission")})
    XCTAssertThrowsError(try reserve.append(key:0,tile:tile));XCTAssertThrowsError(try reserve.finish())
    let folder=try temporary();let scratch=try RuntimeTileIndex.Builder(directory:folder);try scratch.append(key:0,tile:tile)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path),[])
    XCTAssertEqual(try scratch.finish().tile(for:0)?[0],tile[0])
  }
  func testDenseAndGappedIndexLowerBoundsMatchIndependentOracleAtIntegerExtremes() throws {
    let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096))
    for keys in [[],[13],[13,14,15,16],[13,15,16,25]] as [[Int]] {
      let builder=try RuntimeTileIndex.Builder()
      for key in keys {try builder.append(key:key,tile:tile)}
      let index=try builder.finish()
      for key in [Int.min,-1,0,12,13,14,15,16,17,24,25,26,Int.max] {
        XCTAssertEqual(index.lowerBound(key),keys.firstIndex(where:{$0>=key}) ?? keys.count)
        XCTAssertEqual(index.tile(for:key) != nil,keys.contains(key))
      }
    }
  }
  func testConcurrentSnapshotEditsDoNotMutateSharedIndexOrSamples() async throws {
    let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096)),builder=try RuntimeTileIndex.Builder()
    for key in 0..<4096 {try builder.append(key:key,tile:tile)}
    let original=RasterTileMap(base:try builder.finish())
    let results=await withTaskGroup(of:Bool.self,returning:[Bool].self) { group in
      for i in 0..<16 {group.addTask {var copy=original;copy[i,default:tile][0] = Pixel(Float(i),0,0);return copy[i]?[0].r==Float(i) && original[i]?[0] == .white && copy.count==4096}}
      var values=[Bool]();for await value in group {values.append(value)};return values
    }
    XCTAssertEqual(results.count,16);XCTAssertTrue(results.allSatisfy{$0});XCTAssertEqual(original.editEntryCount,0)
  }
  func testCancelledBuilderCannotPublishPartialIndex() async throws {
    let ready=expectation(description:"First index record appended")
    let task=Task.detached { () throws -> RuntimeTileIndex in
      let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096)),builder=try RuntimeTileIndex.Builder()
      try builder.append(key:0,tile:tile);ready.fulfill()
      try await Task.sleep(for:.seconds(30));try builder.append(key:1,tile:tile);return try builder.finish()
    }
    await fulfillment(of:[ready],timeout:5)
    task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled index published")} catch {XCTAssertTrue(error is CancellationError)}
  }
  func testPriorQualifiedSurfaceAndNativeSerializationBytesRemainExact() throws {
    let directory=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("RuntimeTileIndex")
    for depth in PixelDepth.allCases {
      let bytes=try Data(contentsOf:directory.appendingPathComponent("surface-\(depth.rawValue).plist"))
      let surface=try PropertyListDecoder().decode(Surface.self,from:bytes),encoder=PropertyListEncoder();encoder.outputFormat = .binary
      XCTAssertEqual(try encoder.encode(surface),bytes)
      let native=try Data(contentsOf:directory.appendingPathComponent("native63-\(depth.rawValue).photato"))
      let document=try NativeArchive.decode(native)
      XCTAssertEqual(try NativeArchive.encodeChunked(document,minimumVersion:63),native)
      XCTAssertEqual(try NativeArchive.decodePaged(native),document)
    }
  }
}
