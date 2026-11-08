import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDLargeModeFileTests: XCTestCase {
  struct Manifest: Decodable {
    struct Vector: Decodable {
      struct Probe: Decodable { let x: Int; let y: Int; let expected_native: [Float] }
      let file: String; let sha256: String; let width: Int; let height: Int
      let depth: Int; let mode: Int; let channels: Int
      let expected_native_plane_SHA256_big_endian: [String]
      let probes: [Probe]
    }
    let cases: [Vector]
  }
  private func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
  private func reference(_ name: String) throws -> (URL, Manifest.Vector) {
    let folder = try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("PSBLargeComponents")
    let manifest = try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("provenance.json")))
    let vector = try XCTUnwrap(manifest.cases.first { $0.file == name })
    let url = folder.appendingPathComponent(name)
    XCTAssertEqual(hash(try Data(contentsOf:url)),vector.sha256)
    return (url,vector)
  }
  private func componentHashes(_ native: NativeModeRaster) throws -> [String] {
    try (0...native.mode.componentCount).map { c in
      var sha = SHA256()
      for y in 0..<native.height {
        try Task.checkCancellation()
        var row = Data(count:native.width*native.bytesPerSample)
        row.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
          for x in 0..<native.width {
            let word = native.rawWord(component:c,index:y*native.width+x)
            for b in 0..<native.bytesPerSample { bytes[x*native.bytesPerSample+b] = UInt8(truncatingIfNeeded:word >> (8*(native.bytesPerSample-1-b))) }
          }
        }
        sha.update(data:row)
      }
      return sha.finalize().map { String(format:"%02x",$0) }.joined()
    }
  }
  private func checkLarge(_ name: String) throws {
    let (url,v) = try reference(name)
    let document = try PSDCodec.read(url)
    XCTAssertEqual(document.width,v.width); XCTAssertEqual(document.height,v.height)
    XCTAssertGreaterThan(v.width*v.height,NativeModeRaster.maximumPixels)
    let native = try XCTUnwrap(document.layers.first?.nativeMode)
    XCTAssertEqual(native.mode,try PSDModeStorage.mode(v.mode))
    XCTAssertEqual(native.bytesPerSample,v.depth/8)
    XCTAssertEqual(try componentHashes(native),v.expected_native_plane_SHA256_big_endian,"Every retained component word, not only probes")
    for p in v.probes { for c in 0..<v.channels {
      let expected = v.depth == 32 ? p.expected_native[c] : p.expected_native[c]/(v.depth == 8 ? 255:65535)
      XCTAssertEqual(native.value(component:c,index:p.y*v.width+p.x).bitPattern,expected.bitPattern)
    }}
    XCTAssertLessThan(native.residentComponentEditBytes,1_048_576)
    XCTAssertLessThan(document.estimatedBytes,8*1_024*1_024)
    XCTAssertThrowsError(try native.planes,"Dense access must remain explicitly bounded")
  }
  func testLargeGray8RetainsEveryWord() throws { try checkLarge("independent-large-gray8.psb") }
  func testLargeGray16RetainsEveryWord() throws { try checkLarge("independent-large-gray16.psb") }
  func testLargeGray32RetainsEveryHDRWord() throws { try checkLarge("independent-large-gray32.psb") }
  func testLargeCMYK8RetainsEveryInkAndAlphaWord() throws { try checkLarge("independent-large-cmyk8.psb") }
  func testLargeCMYK16RetainsEveryInkAndAlphaWord() throws { try checkLarge("independent-large-cmyk16.psb") }
  func testLargeLab8RetainsEveryComponentWord() throws { try checkLarge("independent-large-lab8.psb") }
  func testLargeLab16RetainsEveryComponentWord() throws { try checkLarge("independent-large-lab16.psb") }
  func testLargeLayerRoundTripRetainsHDRBitsGroupsAndMaskWithoutDenseCanvas() throws {
    let b=try NativeModeRaster.RowBuilder(width:4097,height:2049,mode:.grayscale,depth:.f32)
    try b.fill(component:0,word:Float(0.25).bitPattern);try b.fill(component:1,word:Float(1).bitPattern)
    var source=try b.finish()
    try source.set(-0.0,component:0,index:0);try source.set(-0.25,component:0,index:4096)
    try source.set(2.5,component:0,index:8_394_752);try source.set(0.5,component:1,index:8_394_752)
    var document=try CraftDocument(width:73,height:69,depth:.f32)
    document.modeDescriptor=try .init(mode:.grayscale,depth:.f32,profile:source.profile)
    let group=Layer(name:"Large source group",content:.group(.init(passThrough:false)))
    var layer=Layer(name:"Original HDR separations",content:.raster(try source.surface()));layer.nativeMode=source;layer.parentID=group.id
    layer.mask=try Surface(width:73,height:69,depth:.f32,fill:Pixel(0.75,0.75,0.75))
    document.layers=[layer,group];document.activeLayerID=layer.id
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let file=directory.appendingPathComponent("large-layer-gray32.psb")
    try PSDCodec.writeRasterLayers(document,to:file,compression:.zipPrediction,format:.psb,compositeCompression:.zipPrediction)
    let restored=try PSDCodec.read(file),raster=try XCTUnwrap(restored.layers.first{$0.nativeMode != nil})
    let native=try XCTUnwrap(raster.nativeMode)
    XCTAssertEqual(try componentHashes(native),try componentHashes(source))
    XCTAssertEqual(native.width,source.width);XCTAssertEqual(native.height,source.height)
    XCTAssertEqual(native.profile,source.profile);XCTAssertEqual(native.rawWord(component:0,index:0),0x80000000)
    XCTAssertEqual(restored.layers.first{$0.id == raster.parentID}?.name,group.name)
    XCTAssertEqual(raster.mask,layer.mask);XCTAssertLessThan(restored.estimatedBytes,8*1_024*1_024)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let target=URL(fileURLWithPath:path).appendingPathComponent(file.lastPathComponent)
      try FileManager.default.copyItem(at:file,to:target)
    }
  }
  func testLargeGrayCanvasStreamsEditablePSBOutputAndReopensEveryWord() throws {
    let (url,v)=try reference("independent-large-gray8.psb")
    let document=try PSDCodec.read(url)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let file=directory.appendingPathComponent("large-canvas-gray8.psb")
    try PSDCodec.writeRasterLayers(document,to:file,compression:.zipPrediction,format:.psb,compositeCompression:.zipPrediction)
    let restored=try PSDCodec.read(file),native=try XCTUnwrap(restored.layers.first?.nativeMode)
    XCTAssertEqual(restored.width,4097);XCTAssertEqual(restored.height,2049)
    XCTAssertEqual(try componentHashes(native),v.expected_native_plane_SHA256_big_endian)
    XCTAssertEqual(native.profile,document.layers[0].nativeMode?.profile)
    XCTAssertLessThan(restored.estimatedBytes,8*1_024*1_024)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try FileManager.default.copyItem(at:file,to:URL(fileURLWithPath:path).appendingPathComponent(file.lastPathComponent))
    }
  }
  func testLargeInputKeepsHeapScratchChecksumAndTruncationGuards() throws {
    let (url,_)=try reference("independent-large-gray8.psb"),bytes=try Data(contentsOf:url)
    XCTAssertThrowsError(try PSDCodec.readPaged(bytes,heapByteLimit:PSDCodec.pagedWorkingHeapReserveBytes)) { error in
      XCTAssertTrue(error.localizedDescription.contains("heap budget"),"Must reach heap admission: \(error)")
    }
    XCTAssertThrowsError(try PSDCodec.readPaged(bytes,scratchByteLimit:0)) { error in
      guard let failure=error as? RasterScratchFailure,case .capacity = failure else {return XCTFail("Must reach shared scratch admission: \(error)")}
    }
    for malformed in [Data(bytes.dropLast()),bytes+Data([0])] {
      XCTAssertThrowsError(try PSDCodec.readPaged(malformed)) { error in
        XCTAssertTrue(error.localizedDescription.contains("ZIP"),"Must reach ZIP validation: \(error)")
      }
    }
  }
  func testRetainedSmallGrayUnmattingAndZeroAlphaPolicy() throws {
    // Literal public PSD envelopes qualify the existing white fallback. This
    // regression does not claim Photoshop hidden-color or ColorSync parity.
    for bits in [8,16,32] {
      var file = PSDWriter(); file.text("8BPS"); file.n(1,2); file.data.append(Data(repeating:0,count:6))
      file.n(2,2); file.n(1,4); file.n(2,4); file.n(bits,2); file.n(1,2); file.n(0,4); file.n(0,4)
      var section=PSDWriter(); section.n(0,4); section.n(0,4); section.text("8BIM");section.text(bits == 8 ? "Mtrn":bits == 16 ? "Mt16":"Mt32");section.n(0,4)
      file.section(section.data);file.n(0,2)
      let raw: [UInt8] = bits == 8 ? [170,255,85,0] : bits == 16 ? [0xaa,0xaa,0xff,0xff,0x55,0x55,0,0] : [0x3e,0xc0,0,0,0x3f,0x80,0,0,0x3f,0,0,0,0,0,0,0]
      file.data.append(contentsOf:raw)
      let native=try XCTUnwrap(PSDCodec.read(file.data).layers.first?.nativeMode)
      XCTAssertEqual(native.value(component:0,index:1),1)
      XCTAssertEqual(native.value(component:1,index:1),0)
      XCTAssertEqual(native.value(component:0,index:0),bits == 32 ? -0.25:0)
    }
  }
}
