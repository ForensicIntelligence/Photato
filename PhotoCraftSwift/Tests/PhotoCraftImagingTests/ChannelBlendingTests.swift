import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ChannelBlendingTests:XCTestCase {
  func style(_ channels:[Int])->LayerStyle{var s=LayerStyle();s.restrictedChannels=channels;return s}
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
    var d=try CraftDocument(width:8,height:6,depth:depth);d.layers[0].content = .raster(try Surface(width:8,height:6,depth:depth,fill:Pixel(0.125,0.25,0.5),colorEncoding:encoding))
    let layer=Layer(name:"Upper",content:.raster(try Surface(width:8,height:6,depth:depth,fill:Pixel(0.75,0.5,0.25),colorEncoding:encoding)));d.layers.append(layer);d.activeLayerID=layer.id;return d
  }
  func assertChannels(_ actual:Surface,_ ordinary:Surface,_ before:Surface,_ excluded:[Int],file:StaticString=#filePath,line:UInt=#line)throws {
    for y in 0..<actual.height{for x in 0..<actual.width{
      let a=actual.colorEncoding == .linearRGB ? actual.linearPixel(x:x,y:y):actual.pixel(x:x,y:y)
      let b=before.colorEncoding == .linearRGB ? before.linearPixel(x:x,y:y):before.pixel(x:x,y:y)
      let p=ordinary.colorEncoding == .linearRGB ? ordinary.linearPixel(x:x,y:y):ordinary.pixel(x:x,y:y)
      let expected=excluded.count==3 ? b:Pixel(excluded.contains(0) ? b.r:p.r,excluded.contains(1) ? b.g:p.g,excluded.contains(2) ? b.b:p.b,p.a)
      XCTAssertTrue(a.hasSameBits(as:expected),"pixel\(x),\(y),channels\(excluded)",file:file,line:line)
    }}
  }
  func testAllEightChannelChoicesEveryDepthAndRegionalOutputKeepOtherWords()throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),ordinary=try Renderer.composite(d);var prior=d;prior.layers.removeLast();prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
      for bits in 0..<8 {let excluded=(0..<3).filter{bits&(1<<$0) != 0};var changed=d;changed.layers[1].style=style(excluded)
        let output=try Renderer.composite(changed);try assertChannels(output,ordinary,before,excluded)
        let patch=try Renderer.composite(changed,region:.init(x:2,y:1,width:3,height:3))
        for y in 1..<4{for x in 2..<5{XCTAssertTrue(patch.pixel(x:x,y:y).hasSameBits(as:output.pixel(x:x,y:y)))}}
        XCTAssertEqual(changed.layers[1].content,d.layers[1].content)
      }
    }
  }
  func testAffineMaskedAndAllBlendModesRestoreOnlyExcludedComponents()throws {
    for depth in PixelDepth.allCases {for mode in BlendMode.allCases {
      var d=try fixture(depth);d.layers[1].blendMode=mode;d.layers[1].affine = .translation(1,1);d.layers[1].mask=try Surface(width:8,height:6,fill:Pixel(0.5,0.5,0.5));d.layers[1].opacity=0.5
      let ordinary=try Renderer.composite(d);var prior=d;prior.layers.removeLast();prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
      d.layers[1].style=style([0]);try assertChannels(Renderer.composite(d),ordinary,before,[0])
    }}
  }
  func testGroupClippedAndEffectRestrictionsUseWholeNodeBackdrop()throws {
    for depth in PixelDepth.allCases {for pass in [false,true] {
      var d=try fixture(depth);var group=Layer(name:"Owned group",content:.group(GroupContent(passThrough:pass)));d.layers[1].parentID=group.id;d.layers.append(group);d.activeLayerID=group.id
      let ordinary=try Renderer.composite(d);var prior=try fixture(depth);prior.layers.removeLast();prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
      group.style=style([1]);d.layers[2]=group;try assertChannels(Renderer.composite(d),ordinary,before,[1])
    }}
    for grouped in [false,true] {
      var d=try fixture(.f32);d.layers[1].blendClippedAsGroup=grouped;var clip=Layer(name:"Clip",content:.raster(try Surface(width:8,height:6,depth:.f32,fill:Pixel(0.5,0.75,0.125),colorEncoding:.linearRGB)));clip.clipped=true;d.layers.append(clip)
      let ordinary=try Renderer.composite(d);var prior=d;prior.layers.removeLast(2);prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
      d.layers[1].style=style([2]);try assertChannels(Renderer.composite(d),ordinary,before,[2])
    }
    var d=try fixture();var overlay=LayerEffect(.colorOverlay);overlay.color=Pixel(1,0,0);d.layers[1].style=LayerStyle(effects:[overlay]);let ordinary=try Renderer.composite(d)
    var prior=d;prior.layers.removeLast();prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
    d.layers[1].style?.restrictedChannels=[0];try assertChannels(Renderer.composite(d),ordinary,before,[0])
  }
  func testAdjustmentChannelsAndIncrementalInvalidationKeepSamples()throws {
    var d=try fixture();d.layers[1].content = .adjustment(.brightnessContrast(0.25,0.1));let ordinary=try Renderer.composite(d)
    var prior=d;prior.layers.removeLast();prior.activeLayerID=prior.layers[0].id;let before=try Renderer.composite(prior)
    d.layers[1].style=style([1]);let baseline=try Renderer.render(prior),updated=try Renderer.render(d,reusing:baseline)
    try assertChannels(updated.surface,ordinary,before,[1]);XCTAssertEqual(updated.update,.full)
  }
  func testMaximumSparseChannelsNativeAndClipboardTransport()throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32);d.layers[0].content = .raster(try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.125,0.25,0.5),colorEncoding:.linearRGB))
    var layer=Layer(name:"Large",content:.raster(try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.75,0.5,0.25),colorEncoding:.linearRGB)));layer.style=style([0]);d.layers.append(layer);d.activeLayerID=layer.id
    let image=try Renderer.composite(d);XCTAssertEqual(image.tileCount,0)
    guard case .raster(let background)=d.layers[0].content,case .raster(let source)=layer.content else{return XCTFail("Missing owned raster input")}
    var unrestricted=d;unrestricted.layers[1].style=nil
    let ordinary=try Renderer.composite(unrestricted).linearPixel(x:299999,y:299999),b=background.linearPixel(x:299999,y:299999)
    let expected=Pixel(b.r,ordinary.g,ordinary.b,ordinary.a),actual=image.linearPixel(x:299999,y:299999)
    XCTAssertTrue(actual.hasSameBits(as:expected),"actual\(actual),expected restricted backdrop plus original blend\(expected)")
    XCTAssertEqual(source.width,300000)
    let content=try ClipboardRenderer.copy(d,layerIDs:[layer.id]),decoded=try ClipboardContent.decode(content.encoded());XCTAssertEqual(decoded.document.layers[0].style?.restrictedChannels,[0]);XCTAssertLessThan(try content.encoded().count,1024*1024)
  }
  func testPSDPSBAndStrictPublicBrstBytesPreserveEditableSettings()throws {
    XCTAssertEqual(try PSDChannelBlending.write([2,0]),Data([0,0,0,0,0,0,0,2]));XCTAssertEqual(try PSDChannelBlending.read(Data([0,0,0,1])),[1])
    for bytes in [Data([1]),Data([0,0,0,3]),Data([0,0,0,1,0,0,0,1])]{XCTAssertThrowsError(try PSDChannelBlending.read(bytes))}
    for depth in PixelDepth.allCases {for format in PSDFileFormat.allCases {for channels:[Int] in [[],[0],[0,2],[0,1,2]] {
      var d=try fixture(depth);d.layers[1].style=style(channels);let data=try PSDCodec.writeRasterLayers(d,format:format),next=try PSDCodec.read(data)
      XCTAssertEqual(next.layers[1].style?.restrictedChannels,channels);XCTAssertEqual(try Renderer.composite(next).rgbaData(depth:depth),try Renderer.composite(d).rgbaData(depth:depth))
      XCTAssertNotNil(data.range(of:Data("8BIMbrst".utf8)))
    }}}
  }
  func testStrictRawChannelCaptureEveryDepthAndChoice()throws {
    guard let dir=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]else{return};var data=Data()
    for depth in PixelDepth.allCases {for bits in 0..<8 {
      var d=try fixture(depth);d.layers[1].style=style((0..<3).filter{bits&(1<<$0) != 0});let output=try Renderer.composite(d)
      let p=output.colorEncoding == .linearRGB ? output.linearPixel(x:3,y:2):output.pixel(x:3,y:2)
      for v in [p.r,p.g,p.b,p.a]{var word=v.bitPattern.littleEndian;withUnsafeBytes(of:&word){data.append(contentsOf:$0)}}
    }}
    try data.write(to:URL(fileURLWithPath:dir).appendingPathComponent("channel-blending.f32"))
  }
  func testChannelOnlyPixelEditsRetainBoundedRenderDamage()throws {
    for depth in [PixelDepth.u8,.f32] {
      var d=try CraftDocument(width:256,height:256,depth:depth)
      d.layers[0].content = .raster(try Surface(width:256,height:256,depth:depth,fill:Pixel(0.125,0.25,0.5)))
      var source=try Surface(width:256,height:256,depth:depth,fill:Pixel(0.75,0.5,0.25))
      var upper=Layer(name:"Owned channel layer",content:.raster(source));upper.style=style([0]);d.layers.append(upper);d.activeLayerID=upper.id
      let before=try Renderer.render(d);source.setPixel(x:130,y:130,Pixel(0.25,0.75,0.5));d.layers[1].content = .raster(source)
      let after=try Renderer.render(d,reusing:before)
      if case .region(let area)=after.update{XCTAssertLessThanOrEqual(area.width*area.height,Surface.tileSide*Surface.tileSide)}else{XCTFail("A channel-only pixel edit requires bounded damage,got\(after.update)")}
      XCTAssertEqual(try after.surface.rgbaData(depth:.f32),try Renderer.composite(d).rgbaData(depth:.f32))
      d.layers[1].style?.restrictedChannels=[1];let changed=try Renderer.render(d,reusing:after);XCTAssertEqual(changed.update,.full)
    }
  }

}
