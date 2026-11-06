import XCTest
@testable import PhotoCraftCore

final class CustomKernelPresetTests:XCTestCase {
  func owned()throws->Data {
    try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:"owned-asymmetric",withExtension:"acf",subdirectory:"Fixtures/CustomKernelOwned")))
  }
  func testPhotoshopOwnedLayoutAndByteIdenticalExport()throws {
    let bytes=try owned(),settings=try CustomKernelPreset.decode(bytes,format:.acf)
    XCTAssertEqual(bytes.count,54);XCTAssertEqual(settings.kernel,[-999]+Array(-11...11)+[999])
    XCTAssertEqual(settings.scale,37);XCTAssertEqual(settings.offset,-11)
    XCTAssertEqual(try CustomKernelPreset.encode(settings,format:.acf),bytes)
    XCTAssertEqual(try CustomKernelPreset.decode(bytes),settings)
  }
  func testSignedLimitsAndNonzeroDataSliceIndex()throws {
    var settings=OtherVideoSettings();settings.kernel=[Int](repeating:-999,count:25);settings.kernel[24]=999;settings.scale=9999;settings.offset = -9999
    let bytes=try CustomKernelPreset.encode(settings,format:.acf)
    XCTAssertEqual(Array(bytes.prefix(2)),[0xfc,0x19]);XCTAssertEqual(Array(bytes.suffix(6)),[0x03,0xe7,0x27,0x0f,0xd8,0xf1])
    let padded=Data([0xaa])+bytes,slice=padded.dropFirst()
    XCTAssertNotEqual(slice.startIndex,0);XCTAssertEqual(try CustomKernelPreset.decode(slice,format:.acf),settings)
    settings.offset=9999;XCTAssertEqual(try CustomKernelPreset.decode(CustomKernelPreset.encode(settings,format:.acf),format:.acf),settings)
  }
  func testMalformedLengthsAndEverySignedFieldRangeReject()throws {
    let bytes=try owned()
    for n in 0..<54 {XCTAssertThrowsError(try CustomKernelPreset.decode(bytes.prefix(n),format:.acf),"length \(n)")}
    XCTAssertThrowsError(try CustomKernelPreset.decode(bytes+Data([0]),format:.acf))
    for (index,value) in [(0,1000),(24,-1000),(25,0),(25,10000),(25,-1),(26,10000),(26,-10000)] {
      var bad=bytes;let bits=UInt16(bitPattern:Int16(value));bad[2*index]=UInt8(truncatingIfNeeded:bits>>8);bad[2*index+1]=UInt8(truncatingIfNeeded:bits)
      XCTAssertThrowsError(try CustomKernelPreset.decode(bad,format:.acf),"\(index) \(value)")
    }
  }
  func testFractionsRemainLosslessJSONAndNeverRoundForACF()throws {
    var settings=OtherVideoSettings();settings.scale=1.5;settings.offset = -0.25;settings.kernel[0] = -17
    XCTAssertThrowsError(try CustomKernelPreset.encode(settings,format:.acf))
    let json=try CustomKernelPreset.encode(settings,format:.json)
    XCTAssertEqual(json,try settings.encodedCustomPreset());XCTAssertEqual(try CustomKernelPreset.decode(json),settings)
    XCTAssertEqual(try CustomKernelPreset.decode(json,format:.json),settings)
    settings.scale=1;XCTAssertThrowsError(try CustomKernelPreset.encode(settings,format:.acf))
  }
  func testJSONCompatibilityAutoDetectionAndStrictExplicitFormats()throws {
    var short=Data("{\"kind\":\"customFilter\",\"otherVideo\":{}}".utf8)
    short.append(Data(repeating:32,count:54-short.count));XCTAssertEqual(short.count,54)
    XCTAssertEqual(try CustomKernelPreset.decode(short),OtherVideoSettings())
    XCTAssertThrowsError(try CustomKernelPreset.decode(short,format:.acf))
    XCTAssertThrowsError(try CustomKernelPreset.decode(owned(),format:.json))
    XCTAssertThrowsError(try CustomKernelPreset.decode(Data(repeating:32,count:16_385),format:.json))
    XCTAssertThrowsError(try CustomKernelPreset.decode(Data("{\"kind\":\"offset\"}".utf8)))
  }
  @MainActor func testCancellationPrecedesCodecWork()async throws {
    let settings=OtherVideoSettings(),bytes=try owned()
    let encode=Task { @MainActor in try CustomKernelPreset.encode(settings,format:.acf) };encode.cancel()
    do{_ = try await encode.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("\(error)")}
    let decode=Task { @MainActor in try CustomKernelPreset.decode(bytes,format:.acf) };decode.cancel()
    do{_ = try await decode.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("\(error)")}
  }
}
