import Foundation
import XCTest
@testable import PhotoCraftCore

final class ComponentPlaneBuilderTests:XCTestCase {
  func testEvictionReloadAndRepeatedWritesPreserveRawSamples() throws {
    for depth in PixelDepth.allCases {for capacity in [1,2,64] {
      let fill:UInt32=depth == .f32 ? 0x80000000:17
      let original=try ComponentPlane(width:8193,height:2,depth:depth,defaultWord:fill)
      let b=try ComponentPlaneBuilder(plane:original,cacheBlocks:capacity)
      let words:[UInt32]=depth == .f32 ? [1,0x3f800001,0xc0500000]:depth == .u8 ? [1,255,127]:[1,65535,32769]
      for i in 0..<90 {try b.setWord(words[i%3],at:(i%4)*4096+i/4)}
      try b.setWord(fill,at:0)
      let result=try b.finish()
      XCTAssertLessThanOrEqual(b.maximumCachedBlocks,capacity);XCTAssertGreaterThan(b.maximumCachedBlocks,0)
      var expected=original
      for i in 0..<90 {try expected.setWord(words[i%3],at:(i%4)*4096+i/4)}
      try expected.setWord(fill,at:0)
      XCTAssertEqual(result,expected);XCTAssertEqual(original.word(at:4096),fill)
      XCTAssertEqual(result.residentEditBytes,0);XCTAssertGreaterThan(result.mappedSampleBytes,0)
      XCTAssertThrowsError(try b.finish());XCTAssertThrowsError(try b.setWord(0,at:1))
    }}
  }
  func testUniformMaximumGeometryRequiresNoScratch() throws {
    let p=try ComponentPlane(width:300000,height:300000,depth:.f32,defaultWord:0x80000000)
    let b=try ComponentPlaneBuilder(plane:p,maximumBytes:0)
    try b.setWord(0x80000000,at:p.count-1)
    XCTAssertEqual(try b.finish(),p);XCTAssertEqual(b.maximumCachedBlocks,0)
  }
  func testInvalidWritesPoisonCandidateWithoutChangingSource() throws {
    for kind in 0..<3 {
      let p=try ComponentPlane(width:65,height:65,depth:.f32),b=try ComponentPlaneBuilder(plane:p)
      try b.setWord(1,at:0)
      if kind==0 {XCTAssertThrowsError(try b.setWord(0,at:-1))}
      if kind==1 {XCTAssertThrowsError(try b.setWord(0,at:p.count))}
      if kind==2 {XCTAssertThrowsError(try b.setWord(0x7fc00000,at:1))}
      XCTAssertThrowsError(try b.finish());XCTAssertEqual(p.word(at:0),0)
    }
    var edited=try ComponentPlane(width:1,height:1,depth:.u8);try edited.setWord(1,at:0)
    XCTAssertThrowsError(try ComponentPlaneBuilder(plane:edited))
    XCTAssertThrowsError(try ComponentPlaneBuilder(plane:ComponentPlane(width:1,height:1,depth:.u8),cacheBlocks:65))
  }
  func testSharedScratchAdmissionAndIOFailureDiscardCandidate() throws {
    let p=try ComponentPlane(width:8193,height:1,depth:.u16)
    let budget=ComponentScratchBudget(limit:1),b=try ComponentPlaneBuilder(plane:p,reserve:budget.reserve)
    try b.setWord(65535,at:8192);XCTAssertThrowsError(try b.finish())
    XCTAssertThrowsError(try b.finish());XCTAssertEqual(p.word(at:8192),0)
    let missing=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let io=try ComponentPlaneBuilder(plane:p,directory:missing);try io.setWord(1,at:0)
    XCTAssertThrowsError(try io.finish());XCTAssertThrowsError(try io.setWord(1,at:1))
  }
  func testCancellationPreventsPublication() async throws {
    let task=Task<Void,Error> {
      let p=try ComponentPlane(width:10,height:10,depth:.u8),b=try ComponentPlaneBuilder(plane:p)
      try b.setWord(1,at:0);withUnsafeCurrentTask {$0?.cancel()}
      XCTAssertThrowsError(try b.finish());XCTAssertThrowsError(try b.setWord(1,at:1))
      XCTAssertEqual(p.word(at:0),0)
    }
    try await task.value
  }
}
