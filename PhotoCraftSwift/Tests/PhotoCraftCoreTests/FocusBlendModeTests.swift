import Foundation
import XCTest
@testable import PhotoCraftCore

final class FocusBlendModeTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> Surface {
    var s = try Surface(width: 48, height: 32, depth: depth)
    for y in 0..<32 { for x in 0..<48 {
      s.setPixel(x:x,y:y,Pixel(x<24 ? 0.8:0.2,Float(y+1)/40,x<24 ? 0.3:0.7,x<4 ? 0:1))
    } }; return s
  }
  func stroke(_ tool: FocusTool, mode: BlendMode = .normal, mask: Bool = false) -> FocusStroke {
    var b=CloneBrush();b.size=12;b.hardness=0.6;b.opacity=0.63;b.flow=0.7;b.spacing=0.15;b.pressureSize=false;b.pressureOpacity=true;b.mode=mode
    var o=FocusOptions();o.strength=0.65;o.protectDetail=false
    let points:[StrokePoint]=tool == .smudge ? [.init(x:18.5,y:16.5,pressure:0.8),.init(x:31.5,y:16.5,pressure:0.6)]:[.init(x:23.5,y:16.5,pressure:0.8)]
    return .init(tool:tool,options:o,brush:b,points:points,mask:mask)
  }
  func surface(_ layer: Layer, mask: Bool = false) throws -> Surface {
    if mask { return try XCTUnwrap(layer.mask) }
    guard case .raster(let p)=layer.content else { throw CraftError.invalid("Expected raster") };return p
  }
  func raw(_ surface:Surface)->Data {
    var data=Data();for y in 0..<surface.height {for x in 0..<surface.width {let p=surface.pixel(x:x,y:y);for v in [p.r,p.g,p.b,p.a] {var bits=v.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}}};return data
  }
  func testNormalRaw456RegressionEveryToolDepthAndTarget()throws {
    for depth in PixelDepth.allCases {for tool in FocusTool.allCases {for mask in [false,true] {
      let s=try fixture(depth);var layer=Layer(name:"Owned",content:.raster(s));if mask {layer.mask=s}
      _=try FocusPainter.paint(stroke(tool,mask:mask),on:&layer,canvasWidth:48,canvasHeight:32)
      let bytes=raw(try surface(layer,mask:mask));let name="normal-\(tool.rawValue)-\(depth.rawValue)-\(mask ? "mask":"pixels")"
      let url=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"rgba32",subdirectory:"Fixtures/FocusNormal456"))
      XCTAssertEqual(bytes,try Data(contentsOf:url),name)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent(name+".rgba32"))}
    }}}
  }
  func testLiteralBlendColorsAlphaStencilAndScalarMaskPolicies()throws {
    let modes:[BlendMode]=[.normal,.darken,.lighten,.hue,.saturation,.color,.luminosity]
    XCTAssertEqual(FocusBlendModes.supported,modes)
    let expected:[[Float]]=[[0.4,0.7,0.5],[0.4,0.2,0.4],[0.8,0.7,0.5],[0.026,0.626,0.226],[0.601,0.301,0.401],[0.214,0.514,0.314],[0.986,0.386,0.586]]
    // Independent literal W3C nonseparable examples, not Photoshop numeric oracles.
    for (i,mode) in modes.enumerated() {
      for alpha:Float in [1,0.5] {for preserve in [false,true] {
        let before=Pixel(0.8,0.2,0.4,alpha),effect=Pixel(0.4,0.7,0.5,0.3)
        let result=FocusBlendModes.processed(effect,over:before,mode:mode,depth:.u8,mask:false,preserveTransparency:preserve)
        let overlap:Float=preserve ? 1:alpha
        for c in 0..<3 {let source:[Float]=[0.4,0.7,0.5];let want=mode == .normal ? source[c]:source[c]*(1-overlap)+expected[i][c]*overlap;XCTAssertEqual(result.rgb[c],want,accuracy:0.000002,"\(mode)")}
        XCTAssertEqual(result.a,effect.a)
      }}
      let hidden=Pixel(-100,400,0.2,0),effect=Pixel(0.1,0.2,0.3,0.4)
      XCTAssertTrue(FocusBlendModes.processed(effect,over:hidden,mode:mode,depth:.f32,mask:false,preserveTransparency:false).hasSameBits(as:effect))
      let gray=FocusBlendModes.processed(Pixel(0.4,0.4,0.4),over:Pixel(0.8,0.8,0.8),mode:mode,depth:.f32,mask:true,preserveTransparency:false)
      let want:Float=[.normal,.darken,.luminosity].contains(mode) ? 0.4:0.8
      XCTAssertEqual(gray,Pixel(want,want,want))
    }
  }
  func testAllModesCompleteIncrementalSelectionAlphaAndTargetEquality()throws {
    for depth in PixelDepth.allCases {for tool in FocusTool.allCases {for mask in [false,true] {
      var source=try fixture(depth);if !mask {source.mapPixels{x,y,p in Pixel(p.r,p.g,p.b,x<24 ? 0.45:0.8)}}
      let coverage=try SelectionMask(width:48,height:32,bytes:Array(repeating:128,count:48*32));let selection=IntRect(x:12,y:8,width:26,height:16)
      var original=Layer(name:"Owned",content:.raster(source));if mask {original.mask=source};original.protection.insert(.transparency)
      var normal=original;_=try FocusPainter.paint(stroke(tool,mask:mask),on:&normal,canvasWidth:48,canvasHeight:32,selection:selection,selectionMask:coverage)
      let alphaReference=try surface(normal,mask:mask)
      for mode in FocusBlendModes.supported {
        let paint=stroke(tool,mode:mode,mask:mask);var complete=original
        _=try FocusPainter.paint(paint,on:&complete,canvasWidth:48,canvasHeight:32,selection:selection,selectionMask:coverage)
        var prefix=paint;prefix.points=[paint.points[0]]
        let session=try FocusStrokeSession(layer:original,stroke:prefix,canvasWidth:48,canvasHeight:32,selection:selection,selectionMask:coverage)
        if paint.points.count>1 {_=try session.append(Array(paint.points.dropFirst()))}
        let out=try surface(complete,mask:mask);XCTAssertEqual(raw(out),raw(session.surface),"\(tool)/\(mode)/\(depth)/\(mask)")
        if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let name="focus-mode-\(tool.rawValue)-\(mode.rawValue)-\(depth.rawValue)-\(mask ? "mask":"pixels").rgba32"
          try raw(out).write(to:URL(fileURLWithPath:path).appendingPathComponent(name))
        }
        for y in 0..<32 {for x in 0..<48 {
          XCTAssertEqual(out.pixel(x:x,y:y).a,alphaReference.pixel(x:x,y:y).a)
          if !selection.contains(x,y) {XCTAssertEqual(out.pixel(x:x,y:y),try surface(original,mask:mask).pixel(x:x,y:y))}
        }}
      }
    }}}
  }
  func testInvalidModesNoOpsAndCancellationRemainAtomic()async throws {
    let original=Layer(name:"Owned",content:.raster(try fixture(.f32)))
    for tool in FocusTool.allCases {
      for mode:BlendMode in [.multiply,.screen,.dissolve] {var layer=original;XCTAssertThrowsError(try FocusPainter.paint(stroke(tool,mode:mode),on:&layer,canvasWidth:48,canvasHeight:32));XCTAssertEqual(layer,original)}
      var paint=stroke(tool,mode:.color);paint.options.strength=0;var layer=original
      XCTAssertFalse(try FocusPainter.paint(paint,on:&layer,canvasWidth:48,canvasHeight:32));XCTAssertEqual(layer,original)
    }
    let paint=stroke(.smudge,mode:.luminosity)
    let task=Task{withUnsafeCurrentTask{$0?.cancel()};var layer=original;do{_=try FocusPainter.paint(paint,on:&layer,canvasWidth:48,canvasHeight:32);return false}catch is CancellationError{return layer==original}catch{return false}}
    let cancelled=await task.value;XCTAssertTrue(cancelled)
  }
}
