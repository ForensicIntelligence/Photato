import XCTest
@testable import PhotoCraftCore

final class ColorLookupTests: XCTestCase {
  func testCubeDomainsOneDimensionalAndInterpolation() throws {
    let table = try ColorLUT.generated(title:"Channels",size:3) { SIMD3($0.z,$0.x,$0.y) }
    let bytes = try ColorLUTFile.writeCube(table), loaded = try ColorLUTFile.read(bytes,name:"channels.cube")
    for mode in ColorLUT.Interpolation.allCases {
      let transfer = try ColorLookupTransfer(.init(lut:loaded,interpolation:mode,dither:false),depth:.u8)
      for p in [Pixel(0.2,0.4,0.7,0.3),Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)] {
        let q = transfer.apply(p); XCTAssertEqual(q.r,p.b,accuracy:1e-6); XCTAssertEqual(q.g,p.r,accuracy:1e-6); XCTAssertEqual(q.b,p.g,accuracy:1e-6); XCTAssertEqual(q.a,p.a)
      }
    }
    var domain = table; domain.domainMin = [-1,-1,-1]; domain.domainMax = [1,1,1]
    let transform = try ColorLookupTransfer(.init(lut:domain,dither:false),depth:.u8)
    XCTAssertEqual(transform.apply(Pixel(0,0,0)),Pixel(0.5,0.5,0.5))
    let one = Data("LUT_1D_SIZE 3\nDOMAIN_MIN -1 -1 -1\nDOMAIN_MAX 1 1 1\n0 0 0\n0.25 0.5 0.75\n1 1 1\n".utf8)
    let curve = try ColorLUTFile.read(one,name:"curve.cube")
    XCTAssertEqual(try ColorLookupTransfer(.init(lut:curve,dither:false),depth:.u8).apply(Pixel(0,0,0)),Pixel(0.25,0.5,0.75))
    XCTAssertEqual(try ColorLUTFile.export(curve).data,one)
  }
  func testNonuniformThreeDLGridAndSourceRetention() throws {
    var text = "0 1 4\n"
    // Three-number shaper lines are ambiguous with data; use the standard17-knot case below.
    text = (0..<17).map { String($0*$0) }.joined(separator:" ")+"\n"
    for r in 0..<17 { for g in 0..<17 { for b in 0..<17 { text += "\(r*4095/16) \(g*4095/16) \(b*4095/16)\n" } } }
    let bytes = Data(text.utf8), lut = try ColorLUTFile.read(bytes,name:"grid.3dl")
    XCTAssertEqual(lut.inputGrid?[8],0.25)
    let q = try ColorLookupTransfer(.init(lut:lut,dither:false),depth:.u8).apply(Pixel(0.25,0.25,0.25))
    XCTAssertEqual(q.r,Float(2047)/4095,accuracy:1e-6)
    XCTAssertEqual(try ColorLUTFile.export(lut).data,bytes)
  }
  func testNative18MaskAndMemoryAccounting() throws {
    var d = try CraftDocument(width:4,height:2); d.selection = IntRect(x:1,y:0,width:2,height:2)
    let lut = try ColorLUT.identity(size:4), value = ColorLookupAdjustment(lut:lut,dither:false)
    let oldBytes = d.estimatedBytes, layer = try value.layer(in:d); d.layers.append(layer)
    XCTAssertGreaterThanOrEqual(d.estimatedBytes-oldBytes,lut.estimatedBytes)
    XCTAssertEqual(d.minimumArchiveVersion,18)
    XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.black); XCTAssertEqual(layer.mask?.pixel(x:1,y:0),.white)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
  }
  func testLookFloatBytesAndGeneratedPresets() throws {
    let table = try ColorLUT.identity()
    let hex = table.values.map { f in (0..<4).map { String(format:"%02x",(f.bitPattern >> ($0*8)) & 255) }.joined() }.joined()
    let xml = Data("<look><LUT><size>2</size><data>\(hex)</data></LUT></look>".utf8)
    let lut = try ColorLUTFile.read(xml,name:"identity.look")
    XCTAssertEqual(lut.values,table.values); XCTAssertEqual(try ColorLUTFile.export(lut).data,xml)
    for preset in ColorLUTPreset.allCases {
      let lut = try preset.makeLUT(); XCTAssertNoThrow(try lut.validate()); XCTAssertEqual(lut.size,33)
      let reload = try ColorLUTFile.read(ColorLUTFile.writeCube(lut),name:"preset.cube")
      XCTAssertEqual(lut.values,reload.values)
    }
  }
  func testMalformedTablesRejectWithoutAllocatingDeclaredSizes() throws {
    for text in ["LUT_3D_SIZE 999999999\n", "LUT_3D_SIZE 2\n0 0 0\n", "LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n", "LUT_3D_SIZE 2\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n", "LUT_3D_SIZE 2\n0 nan 0\n", "LUT_IN_VIDEO_RANGE 1\nLUT_3D_SIZE 2\n"] {
      XCTAssertThrowsError(try ColorLUTFile.read(Data(text.utf8),name:"invalid.cube"))
    }
    XCTAssertThrowsError(try ColorLUTFile.read(Data("<!DOCTYPE a [<!ENTITY b 'value'>]><a/>".utf8),name:"invalid.look"))
  }
}
