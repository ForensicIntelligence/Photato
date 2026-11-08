import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeModeRowBuilderTests: XCTestCase {
  func testInterleavedRowsRetainEveryRawWordAndImmutableSnapshots() throws {
    let b=try NativeModeRaster.RowBuilder(width:4100,height:3,mode:.grayscale,depth:.f32)
    for y in 0..<3 {
      var gray=[UInt32](repeating:0x80000000,count:4100),alpha=[UInt32](repeating:Float(1).bitPattern,count:4100)
      gray[4096]=Float(y == 1 ? -0.25:2.5).bitPattern;alpha[y]=Float(0.5).bitPattern
      try b.appendRow(gray,component:0);try b.appendRow(alpha,component:1)
    }
    let result=try b.finish()
    for y in 0..<3 {for x in 0..<4100 {
      XCTAssertEqual(result.rawWord(component:0,index:y*4100+x),x == 4096 ? Float(y == 1 ? -0.25:2.5).bitPattern:0x80000000)
      XCTAssertEqual(result.rawWord(component:1,index:y*4100+x),Float(x == y ? 0.5:1).bitPattern)
    }}
    XCTAssertEqual(result.residentComponentEditBytes,0);XCTAssertGreaterThan(result.mappedComponentSampleBytes,0)
    var branch=result;try branch.set(3,component:0,index:0)
    XCTAssertEqual(result.rawWord(component:0,index:0),0x80000000)
    XCTAssertThrowsError(try b.finish());XCTAssertThrowsError(try b.appendRow([0],component:0))
  }
  func testMissingRepeatedAndInvalidRowsPoisonOnlyTheCandidate() throws {
    let missing=try NativeModeRaster.RowBuilder(width:2,height:1,mode:.grayscale,depth:.u8)
    try missing.appendRow([1,2],component:0);XCTAssertThrowsError(try missing.finish())
    XCTAssertThrowsError(try missing.fill(component:1,word:255))
    for invalid:UInt32 in [Float.nan.bitPattern,Float.infinity.bitPattern,Float(2).bitPattern,Float(-0.5).bitPattern] {
      let b=try NativeModeRaster.RowBuilder(width:2,height:1,mode:.grayscale,depth:.f32)
      try b.fill(component:0,word:0);XCTAssertThrowsError(try b.appendRow([invalid,Float(1).bitPattern],component:1))
      XCTAssertThrowsError(try b.finish())
    }
    let extra=try NativeModeRaster.RowBuilder(width:2,height:1,mode:.grayscale,depth:.u8)
    try extra.appendRow([1,2],component:0);XCTAssertThrowsError(try extra.appendRow([1,2],component:0));XCTAssertThrowsError(try extra.finish())
    let range=try NativeModeRaster.RowBuilder(width:2,height:1,mode:.grayscale,depth:.u8)
    XCTAssertThrowsError(try range.appendRow([256,1],component:0));XCTAssertThrowsError(try range.finish())
  }
  func testSharedScratchAndMaximumUniformGeometryRemainBounded() throws {
    let uniform=try NativeModeRaster.RowBuilder(width:300000,height:300000,mode:.cmyk,depth:.u16,backing:RasterTileStore(maximumBytes:0))
    for c in 0..<5 {try uniform.fill(component:c,word:c == 4 ? 65535:12345)}
    let result=try uniform.finish();XCTAssertEqual(result.rawWord(component:3,index:89_999_999_999),12345)
    XCTAssertEqual(result.mappedComponentSampleBytes,0);XCTAssertEqual(result.residentComponentEditBytes,0)
    let b=try NativeModeRaster.RowBuilder(width:4096,height:1,mode:.grayscale,depth:.u8,backing:RasterTileStore(maximumBytes:8192))
    var row=[UInt32](repeating:0,count:4096);row[0]=1
    try b.appendRow(row,component:0);try b.appendRow(row,component:1)
    XCTAssertThrowsError(try b.finish());XCTAssertThrowsError(try b.finish())
  }
  func testSparseMappingPreservesOtherComponentsAndCancellationRejectsPublication() async throws {
    let b=try NativeModeRaster.RowBuilder(width:4097,height:2,mode:.grayscale,depth:.f32)
    for _ in 0..<2 {var row=[UInt32](repeating:Float(0.375).bitPattern,count:4097);row[4096]=Float(1.5).bitPattern;try b.appendRow(row,component:0)}
    try b.fill(component:1,word:Float(0.5).bitPattern)
    let source=try b.finish(),mapped=try source.mappingColorComponent(0) {v,a in (v-(1-a))/a}
    XCTAssertEqual(mapped.value(component:0,index:0),-0.25);XCTAssertEqual(mapped.value(component:0,index:4096),2)
    for i in 0..<8194 {XCTAssertEqual(mapped.rawWord(component:1,index:i),source.rawWord(component:1,index:i))}
    XCTAssertEqual(source.value(component:0,index:0),0.375)
    let task=Task<Void,Error> {
      let cancelled=try NativeModeRaster.RowBuilder(width:2,height:1,mode:.grayscale,depth:.u8)
      withUnsafeCurrentTask {$0?.cancel()}
      XCTAssertThrowsError(try cancelled.appendRow([0,0],component:0));XCTAssertThrowsError(try cancelled.finish())
    }
    try await task.value
  }
}
