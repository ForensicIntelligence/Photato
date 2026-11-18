import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class BrushPresetCodecTests: XCTestCase {
  func testWideSoftNativeVersionTipLockAndABRTransport() throws {
    let preset = try XCTUnwrap(BrushPresets.builtins().first { $0.name == "Soft Round" })
    var legacy = preset
    legacy.brush.settings?.roundTipProfile = nil
    let previous = BrushPresetFile(presets: [legacy])
    XCTAssertEqual(try BrushPresetFile.decode(previous.encoded()), previous)
    XCTAssertEqual(previous.version, 1)
    let native = BrushPresetFile(presets: [preset])
    XCTAssertEqual(try BrushPresetFile.decode(native.encoded()), native)
    XCTAssertEqual(native.version, 2)
    var mislabeled = native
    mislabeled.version = 1
    XCTAssertThrowsError(try BrushPresetFile.decode(JSONEncoder().encode(mislabeled)))
    let abr = try XCTUnwrap(ABRCodec.read(ABRCodec.write([preset])).presets.first)
    XCTAssertEqual(abr.brush.hardness, preset.brush.hardness)
    XCTAssertEqual(abr.brush.size, preset.brush.size)
    XCTAssertNil(abr.brush.settings?.roundTipProfile)
    var locked = legacy.brush
    locked.settings?.lockedSections = ["tip"]
    XCTAssertNil(preset.applying(to: locked).settings?.roundTipProfile)
    locked.settings?.roundTipProfile = .wideSoft
    XCTAssertEqual(legacy.applying(to: locked).settings?.roundTipProfile, .wideSoft)
  }

  func testMaximumDiameterRoundTripsNativeAndComputedABR() throws {
    var preset = BrushPresets.builtins()[0]
    preset.brush.size = 5_000
    let source = BrushPresetFile(presets:[preset])
    XCTAssertEqual(try BrushPresetFile.decode(source.encoded()).presets,[preset])
    let decoded = try ABRCodec.read(ABRCodec.write([preset]))
    XCTAssertEqual(decoded.warnings,[])
    XCTAssertEqual(decoded.presets.map { $0.brush.size },[5_000])
    preset.brush.size = 5_001
    XCTAssertThrowsError(try BrushPresetFile(presets:[preset]).encoded())
    XCTAssertThrowsError(try ABRCodec.write([preset]))
  }

  func testNativePresetsAndCaptureOptions() throws {
    let presets=BrushPresets.builtins()
    XCTAssertEqual(presets.count,12)
    XCTAssertEqual(try BrushPresetFile.decode(BrushPresetFile(presets:presets).encoded()).presets,presets)
    var current=Brush();current.size=77;current.opacity=0.4;current.color=Pixel(1,0,0);current.settings = .init();current.settings!.flow=0.3
    var preset=presets[1];preset.includeSize=false
    let selected=preset.applying(to:current)
    XCTAssertEqual(selected.size,77);XCTAssertEqual(selected.color,current.color);XCTAssertEqual(selected.opacity,0.4);XCTAssertEqual(selected.settings!.flow,0.3)
    preset.includeToolSettings=true;preset.brush.settings!.smoothing.amount=0.75
    XCTAssertEqual(preset.applying(to:current).settings!.smoothing.amount,0.75)
    var image=try Surface(width:2,height:2,fill:.white);image.setPixel(x:0,y:0,.black)
    XCTAssertEqual(try BrushPresets.define(from:image,bounds:.init(x:0,y:0,width:2,height:2)).bytes,Data([255,0,0,0]))
    XCTAssertThrowsError(try BrushPresets.define(from:Surface(width:2,height:2,fill:.white),bounds:.init(x:0,y:0,width:2,height:2)))
  }
  func testModernABRTipsDynamicsAndEmbeddedTexture() throws {
    var presets=BrushPresets.builtins()
    presets[0].includeToolSettings=true
    presets[0].brush.settings!.mode = .multiply
    presets[0].brush.settings!.flow=0.35
    let data=try ABRCodec.write(presets),decoded=try ABRCodec.read(data)
    XCTAssertEqual(decoded.version,6);XCTAssertEqual(decoded.presets.map(\.name),presets.map(\.name));XCTAssertEqual(decoded.warnings,[])
    for (before,after) in zip(presets,decoded.presets) {
      XCTAssertEqual(before.brush.size,after.brush.size)
      XCTAssertEqual(before.brush.settings!.tip,after.brush.settings!.tip)
      XCTAssertEqual(before.brush.settings!.shape,after.brush.settings!.shape)
      XCTAssertEqual(before.brush.settings!.scattering,after.brush.settings!.scattering)
      XCTAssertEqual(before.brush.settings!.dual,after.brush.settings!.dual)
      if before.brush.settings!.texture.enabled { XCTAssertNotNil(after.brush.settings!.texture.bitmap) }
    }
    XCTAssertEqual(decoded.presets[0].brush.settings!.flow,0.35,accuracy:0.000001)
    XCTAssertEqual(decoded.presets[0].brush.settings!.mode,.multiply)
  }
  func testIndependentLegacyComputedFixtureAndMalformedData() throws {
    // Literal ABR v1 computed brush: spacing25,diameter20,roundness50,angle45,hardness75.
    let data=Data([0,1,0,1,0,1,0,0,0,14,0,0,0,0,0,25,0,20,0,50,0,45,0,75])
    let result=try ABRCodec.read(data)
    XCTAssertEqual(result.presets[0].brush.size,20);XCTAssertEqual(result.presets[0].brush.hardness,0.75)
    XCTAssertEqual(result.presets[0].brush.settings!.roundness,0.5);XCTAssertEqual(result.presets[0].brush.settings!.angle,45)
    XCTAssertThrowsError(try ABRCodec.read(data+Data([1])))
    for size in 0..<data.count { XCTAssertThrowsError(try ABRCodec.read(data.prefix(size))) }
    var preset=BrushPresets.builtins()[0];preset.includeColor=true
    XCTAssertThrowsError(try ABRCodec.write([preset]))
    XCTAssertThrowsError(try BrushPresetFile(presets:[preset,preset]).encoded())
  }
}
