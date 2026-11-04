import Foundation
import XCTest
@testable import PhotoCraftCore

final class ComponentDocumentAdmissionTests: XCTestCase {
  func large(_ mode: DocumentColorMode = .cmyk, _ depth: PixelDepth = .u16) throws -> CraftDocument {
    try DocumentCreation.blank(width:300000,height:300000,depth:depth,background:Pixel(0.2,0.4,0.8,0.5),mode:mode)
  }
  func testMaximumCreationAllComponentModesDepthsUsesOwnedMemoryAdmission() throws {
    XCTAssertEqual(NativeModeRaster.maximumDocumentPixels,90_000_000_000)
    XCTAssertEqual(NativeModeRaster.maximumPixels,8_388_608)
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let d = try large(mode,depth); try d.validate()
      XCTAssertEqual(d.width,300000); XCTAssertEqual(d.height,300000)
      XCTAssertLessThan(d.estimatedBytes,2_000_000)
      if mode != .rgb {
        let n = try XCTUnwrap(d.layers[0].nativeMode)
        XCTAssertEqual(n.logicalSampleBytes,90_000_000_000 * n.bytesPerSample * (mode.componentCount+1))
        XCTAssertEqual(n.residentComponentEditBytes,0); XCTAssertEqual(d.minimumArchiveVersion,86)
      }
    } }
    XCTAssertThrowsError(try DocumentCreation.blank(width:300001,height:1,mode:.cmyk))
    XCTAssertThrowsError(try DocumentCreation.blank(width:300000,height:300001,mode:.grayscale))
  }
  func testCrossingOldAdmissionKeepsDenseExportsChecked() throws {
    let n = try NativeModeRaster(width:4096,height:2049,mode:.cmyk,depth:.u16)
    XCTAssertTrue(n.requiresPagedArchive); XCTAssertLessThan(n.estimatedBytes,2_000_000)
    XCTAssertThrowsError(try n.planes); XCTAssertThrowsError(try n.planeBytes(0))
    XCTAssertThrowsError(try PropertyListEncoder().encode(n))
    XCTAssertEqual(n.rawWord(component:0,index:4096*2049-1),0)
  }
  func testMaximumNativeFileDataAndHistoryRetainSparseLastSample() throws {
    var session = EditorSession(document:try large(.grayscale,.f32))
    let original = session.document, id = try XCTUnwrap(original.activeLayerID)
    var channel = try original.modeChannel(layerID:id,component:0)
    channel.setPixel(x:299999,y:299999,Pixel(Float(bitPattern:0x3f800001),0,0))
    try session.execute(.modeChannel(.init(layerID:id,component:0,pixels:channel)))
    let edited = session.document, n = try XCTUnwrap(edited.layers[0].nativeMode)
    XCTAssertEqual(n.rawWord(component:0,index:90_000_000_000-1),0x3f800001)
    XCTAssertLessThan(edited.estimatedBytes,3_000_000)
    let bytes = try NativeArchive.encode(edited)
    XCTAssertTrue(bytes.starts(with:NativeIndexedArchive.containerHeader(86))); XCTAssertLessThan(bytes.count,1_000_000)
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] {
      try bytes.write(to:URL(fileURLWithPath:folder).appendingPathComponent("large-gray32-native86.photato"))
    }
    let reopened = try NativeArchive.decodePaged(bytes)
    XCTAssertEqual(reopened,edited); XCTAssertGreaterThan(reopened.mappedRasterBytes,0)
    XCTAssertGreaterThan(reopened.mappedRasterIndexBytes,0); XCTAssertGreaterThan(reopened.mappedNativeComponentVirtualBytes,0)
    XCTAssertEqual(reopened.nativeComponentLogicalBytes,720_000_000_000)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
    let url = folder.appendingPathComponent("large.photato");try NativeArchive.write(edited,to:url)
    XCTAssertEqual(try NativeArchive.readPaged(url),edited)
    try FileManager.default.removeItem(at:url); XCTAssertEqual(reopened,edited)
    let history = try HistorySnapshot(edited,store:HistoryScratchStore(parent:folder,limit:5_000_000))
    XCTAssertEqual(try history.restore(),edited)
    try session.undo();XCTAssertEqual(session.document,original)
    try session.redo();XCTAssertEqual(session.document,edited)
  }
  func testMappedSamplesAndIndexAccountingRemainSeparateFromLogicalAndVirtual() throws {
    var n = try NativeModeRaster(width:65,height:65,mode:.rgb,depth:.f32)
    try n.set(1,component:0,index:4224)
    let context = ComponentArchiveTestContext(), e = PropertyListEncoder();e.userInfo[.historyTileEncoder]=context
    let bytes = try e.encode(n), d = PropertyListDecoder();d.userInfo[.historyTileDecoder]=context
    let mapped = try d.decode(NativeModeRaster.self,from:bytes)
    XCTAssertEqual(mapped,n);XCTAssertEqual(mapped.mappedComponentSampleBytes,16384)
    XCTAssertGreaterThan(mapped.mappedComponentIndexBytes,0)
    XCTAssertGreaterThan(mapped.mappedComponentVirtualBytes,mapped.mappedComponentSampleBytes)
    XCTAssertLessThan(mapped.estimatedBytes,n.estimatedBytes)
    var model = try CraftDocument(width:65,height:65,depth:.f32)
    model.modeDescriptor = try .init(mode:.rgb,depth:.f32,profile:mapped.profile)
    model.layers[0].nativeMode=mapped;model.layers[0].content = .raster(try mapped.surface())
    XCTAssertEqual(model.mappedRasterBytes,mapped.mappedComponentSampleBytes)
    XCTAssertEqual(model.mappedRasterIndexBytes,mapped.mappedComponentIndexBytes)
  }
  func testLargeConversionAndNumericRGBInterpretationRetainRawBits() throws {
    var source = try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(-0.0,2,-3,0.5)).interpretingSamples(as:.linearRGB)
    source.setLinearPixel(x:299999,y:299999,Pixel(Float(bitPattern:1),2,-3,0.5))
    let n = try NativeModeRaster.retainingRGBSamples(source)
    XCTAssertEqual(n.rawWord(component:0,index:0),0x80000000)
    XCTAssertEqual(n.rawWord(component:0,index:90_000_000_000-1),1)
    XCTAssertEqual(try n.surface(),source)
    let gray = try large(.grayscale,.u16).convertingMode(.init(mode:.cmyk,depth:.u16))
    XCTAssertEqual(gray.colorMode,.cmyk);XCTAssertLessThan(gray.estimatedBytes,2_000_000)
  }
  func testSparseDefaultChangeAndAlphaOnlyReconciliationPreserveUntouchedWords() throws {
    let input = try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(-0.0,2,-3,0.5)).interpretingSamples(as:.linearRGB)
    let n = try NativeModeRaster.retainingRGBSamples(input)
    let alpha = try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(-0.0,2,-3,0.25)).interpretingSamples(as:.linearRGB)
    let changed = try n.reconciled(with:alpha,previous:input)
    for index in [0,90_000_000_000-1] {
      for c in 0..<3 { XCTAssertEqual(changed.rawWord(component:c,index:index),n.rawWord(component:c,index:index)) }
      XCTAssertEqual(changed.rawWord(component:3,index:index),Float(0.25).bitPattern)
    }
    XCTAssertEqual(changed.residentComponentEditBytes,0)
    let newColor = try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.5,0.25,0.75,0.25)).interpretingSamples(as:.linearRGB)
    let filled = try n.reconciled(with:newColor,previous:input)
    XCTAssertLessThan(filled.estimatedBytes,2_000_000); XCTAssertEqual(try filled.surface(),newColor)
    try capture("large-alpha-words",[changed.rawWord(component:0,index:0),changed.rawWord(component:1,index:0),changed.rawWord(component:2,index:0),changed.rawWord(component:3,index:0)])
  }
  func testDefaultChangingReconciliationMatchesPreservedDenseAlgorithm() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      var native = try NativeModeRaster.converting(Surface(width:65,height:65,depth:depth,fill:Pixel(0.2,0.4,0.6,0.5)),to:mode)
      try native.set(0.125,component:0,index:4224)
      let previous = try native.surface()
      var edited = try Surface(width:65,height:65,depth:depth,fill:Pixel(0.6,0.3,0.2,0.75))
      if depth == .f32 {edited = try edited.interpretingSamples(as:.linearRGB)}
      if depth == .f32 {edited.setLinearPixel(x:64,y:64,previous.linearPixel(x:64,y:64))}
      else {edited.setPixel(x:64,y:64,previous.pixel(x:64,y:64))}
      let actual = try native.reconciled(with:edited,previous:previous)
      var expected = native
      let transform = try NativeModeTransform(mode:mode,depth:depth,profile:native.profile,intent:native.intent)
      for y in 0..<65 {for x in 0..<65 {
        let old = depth == .f32 ? previous.linearPixel(x:x,y:y):previous.pixel(x:x,y:y)
        let p = depth == .f32 ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y), i=y*65+x
        if old.hasSameBits(as:p) {continue}
        if old.r.bitPattern != p.r.bitPattern || old.g.bitPattern != p.g.bitPattern || old.b.bitPattern != p.b.bitPattern {
          let values = try transform.components(p);for c in 0..<mode.componentCount {try expected.set(values[c],component:c,index:i)}
        }
        if old.a.bitPattern != p.a.bitPattern {try expected.set(p.a,component:mode.componentCount,index:i)}
      }}
      XCTAssertEqual(actual,expected,"\(mode)/\(depth)")
      for c in 0...mode.componentCount {XCTAssertEqual(actual.rawWord(component:c,index:4224),native.rawWord(component:c,index:4224))}
    }}
  }
  func testLargeCropAndUnfinishedDenseOperationsRejectAtomically() throws {
    let d = try large(), n = try XCTUnwrap(d.layers[0].nativeMode)
    XCTAssertEqual(try n.reframedExactly(bounds:.init(x:0,y:0,width:300000,height:300000)),n)
    XCTAssertEqual(try n.cropped(to:.init(x:299000,y:299000,width:1000,height:1000)).width,1000)
    XCTAssertNoThrow(try n.transformed(by:.identity,bounds:.init(x:0,y:0,width:1,height:1),method:.nearest))
    XCTAssertThrowsError(try n.reframedExactly(bounds:.init(x:-1,y:0,width:300001,height:300000)))
    XCTAssertThrowsError(try n.trimBounds(.init()))
    var candidate=d
    XCTAssertNoThrow(try ModeComponentEdit(layerID:d.layers[0].id,components:[0],operation:.invert).apply(to:&candidate))
    XCTAssertEqual(candidate.layers[0].nativeMode?.value(component:0,index:0),n.depth.quantize(1-n.value(component:0,index:0)))
    XCTAssertEqual(candidate.layers[0].nativeMode?.rawWord(component:1,index:0),n.rawWord(component:1,index:0))
  }
  func capture(_ name:String,_ words:[UInt32]) throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"]else{return}
    var bytes=Data();for word in words {for shift in [0,8,16,24] {bytes.append(UInt8(truncatingIfNeeded:word>>shift))}}
    try bytes.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".bin"))
  }
}
