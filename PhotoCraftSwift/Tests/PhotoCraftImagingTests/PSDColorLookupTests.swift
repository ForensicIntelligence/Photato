import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDColorLookupTests: XCTestCase {
  func testEditablePSDPSBAndBakedRenderingAtEveryDepth() throws {
    let lut = try ColorLUTFile.read(ColorLUTFile.writeCube(ColorLUT.generated(title:"Swap",size:3) { SIMD3($0.z,$0.x,$0.y) }),name:"swap.cube")
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width:6,height:4,depth:depth)
      doc.layers[0].content = .raster(try Surface(width:6,height:4,depth:depth,fill:Pixel(0.8,0.2,0.4)))
      doc.selection = IntRect(x:1,y:0,width:3,height:4)
      let value = ColorLookupAdjustment(lut:lut,interpolation:.tetrahedral,dither:false)
      var baked = doc; try Command.applyAdjustment(doc.layers[0].id,.colorLookup(value)).apply(to:&baked)
      doc.layers.append(try value.layer(in:doc)); doc.selection = nil
      let expected = try Renderer.composite(doc), applied = try Renderer.composite(baked)
      for x in 0..<6 { XCTAssertEqual(expected.pixel(x:x,y:1).r,applied.pixel(x:x,y:1).r,accuracy:0.005) }
      for format in [PSDFileFormat.psd,.psb] {
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(doc,format:format))
        XCTAssertEqual(reopened.layers.last?.content,doc.layers.last?.content)
        let result = try Renderer.composite(reopened)
        for x in 0..<6 { XCTAssertEqual(result.pixel(x:x,y:1).r,expected.pixel(x:x,y:1).r,accuracy:0.001) }
      }
    }
  }
  func testLegacyDisplayNameUsesFormatDescriptorAndNameKey() throws {
    let encoded = try PSDColorLookup.write(.init(lut:ColorLUTPreset.warm.makeLUT(),interpolation:.tetrahedral,dither:false))
    var descriptor = try PSDDescriptor.read(Data(encoded.dropFirst(2)),padding:true)
    XCTAssertNil(descriptor["NM  "]); XCTAssertNotNil(descriptor["Nm  "])
    descriptor.items.removeAll { ["LUT3DFileName","Dthr"].contains($0.key.text) }
    descriptor.items.append(.init("LUT3DFileName",.text(Array("Legacy Look".utf16)+[0])))
    var data = Data([0,1]); data.append(try descriptor.encoded())
    while data.count%4 != 0{data.append(0)}
    let decoded = try PSDColorLookup.read(data)
    XCTAssertEqual(decoded.lut?.sourceFile,"Legacy Look.cube"); XCTAssertFalse(decoded.dither)
    XCTAssertEqual(decoded.lut?.size,33)
    XCTAssertEqual(try PSDColorLookup.write(decoded,original:data),data)
  }
  func testDescriptorRejectsTruncationAndUnsupportedInterpolation() throws {
    let value = ColorLookupAdjustment(lut:try ColorLUTPreset.warm.makeLUT(),interpolation:.tetrahedral)
    let data = try PSDColorLookup.write(value)
    for n in [0,1,data.count/2] { XCTAssertThrowsError(try PSDColorLookup.read(data.prefix(n))) }
    var legacy = value; legacy.interpolation = .trilinear
    XCTAssertThrowsError(try PSDColorLookup.write(legacy))
    XCTAssertThrowsError(try PSDColorLookup.write(.init()))
    let decoded = try PSDColorLookup.read(data)
    XCTAssertEqual(decoded.lut?.values,value.lut?.values)
    XCTAssertEqual(try PSDColorLookup.write(decoded,original:data),data)
  }
}
