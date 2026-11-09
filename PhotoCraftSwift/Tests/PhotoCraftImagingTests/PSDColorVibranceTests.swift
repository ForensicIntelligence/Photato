import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDColorVibranceTests:XCTestCase {
  func fixture(_ name:String,_ suffix:String)throws->Data {
    let root=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil))
    return try Data(contentsOf:root.appendingPathComponent("ColorVibrance520/"+name+suffix))
  }
  func descriptor(_ fields:[PSDDescriptor.Item])throws->Data {try PSDDescriptor("null",items:fields).encoded()}
  func testModernAndLegacyRecordsRemainDistinctAndRejectUnknownSemantics()throws {
    let modern=try descriptor([.init("useLegacy",.boolean(false)),.init("vibrance",.integer(100))])
    XCTAssertEqual(try PSDColorVibrance.readAdjustment(modern,key:"vibA"),AdjustmentBrushKind.colorVibrance.initial)
    XCTAssertThrowsError(try PSDClassicAdjustment.read(modern,key:"vibA"))
    var legacy=ClassicAdjustment(.vibrance);legacy.vibrance=31;legacy.saturation = -19
    XCTAssertEqual(try PSDColorVibrance.readAdjustment(PSDClassicAdjustment.write(legacy),key:"vibA"),.classic(legacy))
    let explicit=try descriptor([.init("useLegacy",.boolean(true)),.init("vibrance",.integer(31)),.init("Strt",.integer(-19))])
    XCTAssertEqual(try PSDColorVibrance.readAdjustment(explicit,key:"vibA"),.classic(legacy))
    for fields:[PSDDescriptor.Item] in [
      [.init("useLegacy",.integer(0))],
      [.init("useLegacy",.boolean(false)),.init("vibrance",.boolean(true))],
      [.init("useLegacy",.boolean(false)),.init("temperature",.integer(101))],
      [.init("useLegacy",.boolean(false)),.init("whiteBalancePopupIndex",.integer(1))],
      [.init("useLegacy",.boolean(false)),.init("unrepresented",.integer(1))],
      [.init("useLegacy",.boolean(false)),.init("tint",.integer(2)),.init("tint",.integer(3))]
    ] {XCTAssertThrowsError(try PSDColorVibrance.readAdjustment(descriptor(fields),key:"vibA"))}
  }
  func testOwnedPhotoshopDescriptorsMasksNativeArchiveAndIndependentPixelAssessment()throws {
    var referenceMask:Surface?,referenceSource:Layer?
    for name in ["brush","controls"] {
      let bytes=try fixture(name,".psd"),d=try PSDCodec.read(bytes)
      XCTAssertEqual(d.width,1024);XCTAssertEqual(d.height,768);XCTAssertEqual(d.layers.count,2)
      let layer=try XCTUnwrap(d.layers.last)
      guard case .adjustment(.modern(let value))=layer.content else{return XCTFail("Modern PSD was interpreted as legacy Vibrance")}
      XCTAssertEqual(value.kind,.colorVibrance)
      XCTAssertEqual(value.values,name == "brush" ? ["temperature":0,"tint":0,"vibrance":100,"saturation":0]:["temperature":17,"tint":-23,"vibrance":31,"saturation":-19])
      let mask=try XCTUnwrap(layer.mask)
      XCTAssertEqual(mask.pixel(x:0,y:0).r,0)
      if let referenceMask {XCTAssertEqual(mask,referenceMask)}else{referenceMask=mask}
      if let referenceSource {XCTAssertEqual(d.layers[0].content,referenceSource.content)}else{referenceSource=d.layers[0]}
      XCTAssertNotNil(layer.sourceTags?["vibA"])
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))

      // Independent output assessment, not a transfer-equality assertion or a waiver.
      // The goal's Photoshop byte-equality gate consumes these mismatch counts separately.
      let expected=try PSDChannelCodec.inflate(fixture(name,"-merged.rgb.zlib"),expected:d.width*d.height*3)
      let actual=try Renderer.composite(d)
      let sampler=try MaskSampler(layer:layer,canvasSize:(d.width,d.height))
      var different=0,maximum=0,inside=0,outside=0
      for y in 0..<d.height {for x in 0..<d.width {
        let p=actual.pixel(x:x,y:y),channels=[p.r,p.g,p.b]
        for c in 0..<3 {
          let n=Int((min(1,max(0,channels[c]))*255).rounded()),delta=abs(n-Int(expected[(y*d.width+x)*3+c]))
          if delta != 0 {different+=1;if sampler.coverage(x:Double(x)+0.5,y:Double(y)+0.5)>0{inside+=1}else{outside+=1}}
          maximum=max(maximum,delta)
        }
      }}
      let assessment:[String:Any]=["fixture":name,"samples":expected.count,"differentSamples":different,"insideMaskDifferentSamples":inside,"outsideMaskDifferentSamples":outside,"maximumByteDelta":maximum,"PhotoshopByteEqualityPassed":different==0,"workflowTestsDoNotQualifyTransfer":true]
      print("ColorVibrance520 output assessment: "+String(decoding:try JSONSerialization.data(withJSONObject:assessment,options:.sortedKeys),as:UTF8.self))
      if let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try JSONSerialization.data(withJSONObject:assessment,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:root).appendingPathComponent("color-vibrance-"+name+"-assessment.json"))
      }
    }
  }
}
